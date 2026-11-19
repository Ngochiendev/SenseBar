import AppKit
import Foundation

nonisolated(unsafe) let mediaRemoteHandle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY)
private let maximumArtworkBytes = 8 * 1_024 * 1_024
private let emissionLock = NSLock()
private nonisolated(unsafe) var watching = false
private nonisolated(unsafe) var previousArtwork: Data?
private nonisolated(unsafe) var previousTitle: String?
private nonisolated(unsafe) var previousArtist: String?
private nonisolated(unsafe) var previousSource: String?
private nonisolated(unsafe) var pauseRecovery = PauseRecovery()
private let recoveryNotification = Notification.Name("SenseBarMediaRecoverySample")

func resolveSymbol<T>(_ handle: UnsafeMutableRawPointer?, _ name: String, as type: T.Type) -> T? {
    if let handle, let address = dlsym(handle, name) { return unsafeBitCast(address, to: type) }
    return nil
}

private func emitJSON(_ payload: [String: Any]) {
    let finiteValues = payload.filter { entry in
        guard let number = entry.value as? Double else { return true }
        return number.isFinite
    }
    guard JSONSerialization.isValidJSONObject(finiteValues),
          var bytes = try? JSONSerialization.data(withJSONObject: finiteValues) else { return }
    bytes.append(0x0A)
    emissionLock.withLock { FileHandle.standardOutput.write(bytes) }
}

/// Mỗi lần đọc sở hữu bộ tích lũy riêng; callback đến sau deadline không đổi snapshot đã xuất.
private final class MediaReadback: @unchecked Sendable {
    private let mutex = NSLock()
    private let completions = DispatchGroup()
    private let callbacks = DispatchQueue(label: "SenseBar.media.sample")
    private var closed = false
    private var values: [String: Any] = [:]
    private var fields: [String: Any] = [:]
    private var supported: Set<Int32>?

    private func merge(_ additions: [String: Any]) {
        mutex.withLock {
            if !closed { values.merge(additions) { _, new in new } }
        }
    }

    func collect(endpoint: MediaRemoteEndpoint?, fallback: Bool) {
        if let endpoint {
            let application = NSRunningApplication.runningApplications(withBundleIdentifier: endpoint.presentationBundle).first
                ?? NSRunningApplication(processIdentifier: endpoint.owner.pid)
            var identity: [String: Any] = ["pid": Int(endpoint.owner.pid), "bundleID": endpoint.presentationBundle]
            if let name = application?.localizedName { identity["appName"] = name }
            merge(identity)
            completions.enter()
            MediaRemoteIO.metadata(endpoint, artwork: true, queue: callbacks) { [self] in metadata($0) }
            completions.enter()
            MediaRemoteIO.commands(endpoint, queue: callbacks) { [self] commands in
                mutex.withLock { if !closed { supported = commands } }
                completions.leave()
            }
            completions.enter()
            MediaRemoteIO.state(endpoint, queue: callbacks) { [self] state in
                if let state, (1...4).contains(state) { merge(["isPlaying": state == 1]) }
                completions.leave()
            }
        } else if fallback {
            collectGlobalSession()
        }
    }

    private func metadata(_ raw: NSDictionary?) {
        mutex.withLock { if !closed { fields = raw as? [String: Any] ?? [:] } }
        completions.leave()
    }

    private func collectGlobalSession() {
        typealias MetadataReply = @convention(block) (NSDictionary?) -> Void
        typealias MetadataCall = @convention(c) (DispatchQueue, @escaping MetadataReply) -> Void
        typealias ProcessReply = @convention(block) (Int32) -> Void
        typealias ProcessCall = @convention(c) (DispatchQueue, @escaping ProcessReply) -> Void
        typealias BundleReply = @convention(block) (NSString?) -> Void
        typealias BundleCall = @convention(c) (DispatchQueue, @escaping BundleReply) -> Void
        typealias PlayingReply = @convention(block) (Bool) -> Void
        typealias PlayingCall = @convention(c) (DispatchQueue, @escaping PlayingReply) -> Void
        if let call = resolveSymbol(mediaRemoteHandle, "MRMediaRemoteGetNowPlayingInfo", as: MetadataCall.self) {
            completions.enter()
            call(callbacks) { [self] in metadata($0) }
        }
        if let call = resolveSymbol(mediaRemoteHandle, "MRMediaRemoteGetNowPlayingApplicationPID", as: ProcessCall.self) {
            completions.enter()
            call(callbacks) { [self] pid in
                if pid > 0 {
                    var identity: [String: Any] = ["pid": Int(pid)]
                    if let app = NSRunningApplication(processIdentifier: pid) {
                        if let name = app.localizedName { identity["appName"] = name }
                        if let bundle = app.bundleIdentifier { identity["bundleID"] = bundle }
                    }
                    merge(identity)
                }
                completions.leave()
            }
        }
        if let call = resolveSymbol(mediaRemoteHandle, "MRMediaRemoteGetNowPlayingApplicationDisplayID", as: BundleCall.self) {
            completions.enter()
            call(callbacks) { [self] identifier in
                if let identifier, identifier.length > 0 { merge(["bundleID": identifier as String]) }
                completions.leave()
            }
        }
        if let call = resolveSymbol(mediaRemoteHandle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying", as: PlayingCall.self) {
            completions.enter()
            call(callbacks) { [self] playing in
                merge(["isPlaying": playing])
                completions.leave()
            }
        }
    }

    func finish() -> (snapshot: [String: Any], fields: [String: Any], commands: Set<Int32>?) {
        _ = completions.wait(timeout: .now() + 1.8)
        return mutex.withLock {
            closed = true
            for (key, suffix) in [("title", "Title"), ("artist", "Artist"), ("album", "Album")] {
                if let text = fields["kMRMediaRemoteNowPlayingInfo" + suffix] as? String { values[key] = text }
            }
            for (key, suffix) in [("duration", "Duration"), ("rate", "PlaybackRate")] {
                if let number = fields["kMRMediaRemoteNowPlayingInfo" + suffix] as? NSNumber {
                    values[key] = number.doubleValue
                }
            }
            return (values, fields, supported)
        }
    }
}

@_cdecl("sensebar_now_playing_get")
public func sensebarNowPlayingGet() {
    let coordinator = MediaSessionCoordinator.shared
    let target = coordinator.choose()
    let readback = MediaReadback()
    readback.collect(endpoint: target, fallback: target == nil && coordinator.isAutomatic)
    let result = readback.finish()
    var snapshot = result.snapshot
    let currentRecording = result.fields
    let currentCommands = result.commands
    let currentSample: (elapsed: Double, timestamp: Date?)? =
        (currentRecording["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? NSNumber).map {
            ($0.doubleValue, currentRecording["kMRMediaRemoteNowPlayingInfoTimestamp"] as? Date)
        }
    let isPlaying = (snapshot["isPlaying"] as? Bool) ?? (((snapshot["rate"] as? Double) ?? 0) > 0)
    snapshot["isPlaying"] = isPlaying
    NotificationCenter.default.post(name: Notification.Name("SenseBarPlaybackActivity"), object: nil, userInfo: ["playing": isPlaying])
    // A selected browser may advertise commands while another app owns the
    // system route. Keep those facts separate for app-scoped delivery.
    snapshot["playerSupportsNext"] = currentCommands?.contains(4) == true
    snapshot["playerSupportsPrevious"] = currentCommands?.contains(5) == true
    if let context = MediaSessionCoordinator.shared.present(target, fields: currentRecording) {
        snapshot["playbackRevision"] = context.revision.uuidString
        snapshot["controlPID"] = context.pid
        // Discovery and metadata callbacks can straddle a pause/handoff.
        // Publish capabilities using ownership at the end of this read.
        let owned = target.map { $0.alive && MediaRemoteIO.discover(includeClients: false).current == $0.owner.pid } == true
        snapshot["supportsTransportControls"] = owned && (currentCommands == nil
            || currentCommands?.contains(isPlaying ? 1 : 0) == true || currentCommands?.contains(2) == true)
        snapshot["supportsNext"] = owned && currentCommands?.contains(4) == true
        snapshot["supportsPrevious"] = owned && currentCommands?.contains(5) == true
        snapshot["supportsSeeking"] = owned && currentCommands?.contains(24) == true
            && MediaRemoteIO.constant("kMRMediaRemoteOptionPlaybackPosition") != nil
    } else {
        snapshot["supportsTransportControls"] = false
    }
    let artwork = currentRecording["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data
    let title = snapshot["title"] as? String
    let artist = snapshot["artist"] as? String
    let source = "\(snapshot["bundleID"] ?? ""):\(snapshot["pid"] ?? 0):\(snapshot["playbackRevision"] ?? "")"
    let sameRecording = source == previousSource && title == previousTitle && artist == previousArtist
    if let artwork, !artwork.isEmpty, artwork.count <= maximumArtworkBytes {
        if watching && sameRecording && artwork == previousArtwork {
            snapshot["artworkUnchanged"] = true
        } else { snapshot["artworkBase64"] = artwork.base64EncodedString() }
        previousArtwork = artwork
    } else if watching && sameRecording && previousArtwork != nil {
        snapshot["artworkUnchanged"] = true
    } else { previousArtwork = nil }
    previousSource = source
    previousTitle = title
    previousArtist = artist
    let audioOutput = BrowserAudioSnapshot.read()
    let closedBrowsers = coordinator.closedBrowserBundles
    snapshot["closedBrowserBundles"] = Array(closedBrowsers)
    snapshot["runningOutputBrowsers"] = audioOutput.browsers.filter { !closedBrowsers.contains($0["bundleID"] as? String ?? "") }
    snapshot["runningOutputApplications"] = audioOutput.applications.filter { !closedBrowsers.contains($0["bundleID"] as? String ?? "") }
    snapshot["availableSources"] = coordinator.availableSources
    snapshot["preferredSource"] = coordinator.preferredBundleID

    if let currentSample {
        let reportedRate = (snapshot["rate"] as? Double) ?? 0
        let rate = isPlaying ? (reportedRate.isFinite && reportedRate > 0 ? reportedRate : 1) : 0
        let age = currentSample.timestamp.map { max(0, Date().timeIntervalSince($0)) } ?? 0
        snapshot["elapsed"] = currentSample.elapsed + age * rate
    }

    if watching {
        let now = ProcessInfo.processInfo.systemUptime
        let delays = pauseRecovery.observe(playing: isPlaying, now: now)
        let recovering = pauseRecovery.isActive(at: now)
        NotificationCenter.default.post(name: recoveryNotification, object: nil,
            userInfo: ["active": recovering, "delays": delays])
    }
    emitJSON(snapshot)
}

/// Tập trung lịch refresh trên main queue, còn đọc media và điều khiển chạy tuần tự ở worker.
private final class MediaWatchSession: @unchecked Sendable {
    private let executor = DispatchQueue(label: "SenseBar.media.events")
    private var idle = false
    private var lastRefresh = -Double.infinity
    private var busy = false
    private var dirty = false
    private var scheduled: DispatchWorkItem?
    private var reconciliation: DispatchWorkItem?
    private var recovery: [DispatchWorkItem] = []
    private var tokens: [NSObjectProtocol] = []
    private var workspaceToken: NSObjectProtocol?
    private var heartbeat: Timer?
    private var input = PlaybackLineFramer()

    func request() {
        DispatchQueue.main.async { [self] in
            if busy { dirty = true; return }
            scheduled?.cancel()
            scheduled = nil
            lastRefresh = ProcessInfo.processInfo.systemUptime
            busy = true
            executor.async { [self] in
                sensebarNowPlayingGet()
                DispatchQueue.main.async { [self] in
                    busy = false
                    if dirty { dirty = false; request() }
                }
            }
        }
    }

    private func enqueue(after delay: Double) {
        DispatchQueue.main.async { [self] in
            if scheduled == nil {
                let job = DispatchWorkItem { [self] in scheduled = nil; request() }
                scheduled = job
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: job)
            }
            if reconciliation == nil {
                let job = DispatchWorkItem { [self] in reconciliation = nil; request() }
                reconciliation = job
                DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.5, execute: job)
            }
        }
    }

    func run() {
        typealias NotificationRegistration = @convention(c) (DispatchQueue) -> Void
        guard let register = resolveSymbol(mediaRemoteHandle, "MRMediaRemoteRegisterForNowPlayingNotifications",
                                           as: NotificationRegistration.self) else {
            emitJSON(["error": "notifications unavailable"])
            return
        }
        tokens.append(NotificationCenter.default.addObserver(forName: Notification.Name("SenseBarPlaybackActivity"), object: nil, queue: .main) { [self] event in
            idle = event.userInfo?["playing"] as? Bool != true
        })
        watching = true
        register(.main)
        let suffixes = ["NowPlayingInfoDidChangeNotification", "NowPlayingApplicationDidChangeNotification",
                        "NowPlayingApplicationIsPlayingDidChangeNotification", "PlayerNowPlayingInfoDidChangeNotification",
                        "NowPlayingPlayerStateDidChange", "NowPlayingApplicationClientStateDidChange",
                        "PlayerIsPlayingDidChangeNotification", "NowPlayingPlayerDidChange", "ActivePlayerPathsDidChange",
                        "OriginNowPlayingInfoDidChangeNotification", "PlayerPlaybackStateDidChangeNotification"]
        var names = Set(suffixes.map { "kMRMediaRemote" + $0 })
        names.insert("_kMRMediaRemotePlayerPlaybackStateDidChangeNotification")
        for suffix in suffixes {
            if let actual = MediaRemoteIO.constant("kMRMediaRemote" + suffix) { names.insert(actual) }
        }
        for name in names {
            tokens.append(NotificationCenter.default.addObserver(forName: Notification.Name(name), object: nil,
                                                                 queue: .main) { [self] _ in enqueue(after: 0.03) })
        }
        tokens.append(NotificationCenter.default.addObserver(forName: recoveryNotification, object: nil,
                                                             queue: .main) { [self] event in
            let active = event.userInfo?["active"] as? Bool == true
            let delays = event.userInfo?["delays"] as? [Double] ?? []
            if !active || !delays.isEmpty {
                recovery.forEach { $0.cancel() }
                recovery = active ? delays.map { delay in
                    let job = DispatchWorkItem { [self] in request() }
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: job)
                    return job
                } : []
            }
        })
        workspaceToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [self] _ in enqueue(after: 0.03) }
        heartbeat = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [self] _ in
            guard ProcessInfo.processInfo.systemUptime - lastRefresh >= (idle ? 5.8 : 1.8) else { return }
            request()
        }
        heartbeat?.tolerance = 0.4
        FileHandle.standardInput.readabilityHandler = { [self] stream in
            let bytes = stream.availableData
            guard !bytes.isEmpty else { exit(0) }
            DispatchQueue.main.async { [self] in
                for command in input.append(bytes) {
                    if command == "refresh" { enqueue(after: 0); continue }
                    executor.async { [self] in execute(command); enqueue(after: 0.14) }
                }
            }
        }
        request()
        RunLoop.main.run()
    }

    private func execute(_ command: String) {
        if let bytes = command.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
           object["command"] as? String == "set_preferred_source" {
            MediaSessionCoordinator.shared.setPreferredSource(object["bundleID"] as? String ?? "auto")
        } else if let action = PlaybackRequest(command) {
            emitJSON(["commandAccepted": MediaSessionCoordinator.shared.perform(action)])
        }
    }
}

@_cdecl("sensebar_now_playing_watch")
public func sensebarNowPlayingWatch() {
    let session = MediaWatchSession()
    withExtendedLifetime(session) { session.run() }
}
