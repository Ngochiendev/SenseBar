import AppKit
import Foundation

private typealias InfoCallback = @convention(block) (NSDictionary?) -> Void
private typealias InfoFunction = @convention(c) (DispatchQueue, @escaping InfoCallback) -> Void
private typealias PIDCallback = @convention(block) (Int32) -> Void
private typealias PIDFunction = @convention(c) (DispatchQueue, @escaping PIDCallback) -> Void
private typealias DisplayIDCallback = @convention(block) (NSString?) -> Void
private typealias DisplayIDFunction = @convention(c) (DispatchQueue, @escaping DisplayIDCallback) -> Void
private typealias IsPlayingCallback = @convention(block) (Bool) -> Void
private typealias IsPlayingFunction = @convention(c) (DispatchQueue, @escaping IsPlayingCallback) -> Void

private let maximumArtworkBytes = 8 * 1_024 * 1_024
nonisolated(unsafe) let mediaRemoteHandle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY)
private nonisolated(unsafe) var watching = false
private nonisolated(unsafe) var previousArtwork: Data?
private nonisolated(unsafe) var previousTitle: String?
private nonisolated(unsafe) var previousArtist: String?
private nonisolated(unsafe) var previousSource: String?
private let emissionLock = NSLock()
private nonisolated(unsafe) var pauseRecovery = PauseRecovery()
private let recoveryNotification = Notification.Name("SenseBarMediaRecoverySample")

func resolveSymbol<T>(_ handle: UnsafeMutableRawPointer?, _ name: String, as type: T.Type) -> T? {
    guard let handle, let symbol = dlsym(handle, name) else { return nil }
    return unsafeBitCast(symbol, to: type)
}

private func emitJSON(_ payload: [String: Any]) {
    let sanitized = payload.filter { ($0.value as? Double)?.isFinite != false }
    guard JSONSerialization.isValidJSONObject(sanitized),
          let data = try? JSONSerialization.data(withJSONObject: sanitized) else { return }
    emissionLock.lock()
    defer { emissionLock.unlock() }
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
}

@_cdecl("sensebar_now_playing_get")
public func sensebarNowPlayingGet() {
    let handle = mediaRemoteHandle

    let queue = DispatchQueue(label: "com.ngochiendev.sensebar.nowplaying")
    let group = DispatchGroup()
    let lock = NSLock()
    var reply: [String: Any] = [:]
    var sample: (elapsed: Double, timestamp: Date?)?
    var recording: [String: Any] = [:]
    var commands: Set<Int32>?
    let coordinator = MediaSessionCoordinator.shared
    let target = coordinator.choose()
    let useGlobalFallback = target == nil && coordinator.isAutomatic

    func set(_ key: String, _ value: Any?) {
        guard let value else { return }
        lock.lock()
        reply[key] = value
        lock.unlock()
    }

    let receiveInfo: (NSDictionary?) -> Void = { rawInfo in
        let info = (rawInfo as? [String: Any]) ?? [:]
        lock.withLock {
            recording = info
            reply["title"] = info["kMRMediaRemoteNowPlayingInfoTitle"] as? String
            reply["artist"] = info["kMRMediaRemoteNowPlayingInfoArtist"] as? String
            reply["album"] = info["kMRMediaRemoteNowPlayingInfoAlbum"] as? String
            reply["duration"] = (info["kMRMediaRemoteNowPlayingInfoDuration"] as? NSNumber)?.doubleValue
            reply["rate"] = (info["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? NSNumber)?.doubleValue
            if let elapsed = (info["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? NSNumber)?.doubleValue {
                sample = (elapsed, info["kMRMediaRemoteNowPlayingInfoTimestamp"] as? Date)
            }
        }

        group.leave()
    }
    group.enter()
    if let target {
        set("pid", Int(target.owner.pid))
        let presentationID = target.presentationBundle
        set("bundleID", presentationID)
        let app = NSRunningApplication.runningApplications(withBundleIdentifier: presentationID).first
            ?? NSRunningApplication(processIdentifier: target.owner.pid)
        set("appName", app?.localizedName)
        MediaRemoteIO.metadata(target, artwork: true, queue: queue, receive: receiveInfo)
        group.enter()
        MediaRemoteIO.commands(target, queue: queue) { supported in
            lock.withLock { commands = supported }
            group.leave()
        }
        group.enter()
        MediaRemoteIO.state(target, queue: queue) { state in
            switch state {
            case 1: set("isPlaying", true)
            case 2, 3, 4: set("isPlaying", false)
            default: break
            }
            group.leave()
        }
    } else if useGlobalFallback, let getInfo = resolveSymbol(handle, "MRMediaRemoteGetNowPlayingInfo", as: InfoFunction.self) {
        getInfo(queue, receiveInfo)
    } else {
        receiveInfo(nil)
    }

    if useGlobalFallback, let getPID = resolveSymbol(handle, "MRMediaRemoteGetNowPlayingApplicationPID", as: PIDFunction.self) {
        group.enter()
        getPID(queue) { pid in
            if pid > 0 {
                set("pid", Int(pid))
                if let app = NSRunningApplication(processIdentifier: pid) {
                    set("appName", app.localizedName)
                    if let bundleID = app.bundleIdentifier {
                        set("bundleID", bundleID)
                    }
                }
            }
            group.leave()
        }
    }

    if useGlobalFallback, let getDisplayID = resolveSymbol(handle, "MRMediaRemoteGetNowPlayingApplicationDisplayID", as: DisplayIDFunction.self) {
        group.enter()
        getDisplayID(queue) { identifier in
            if let id = identifier as String?, !id.isEmpty {
                set("bundleID", id)
            }
            group.leave()
        }
    }

    if useGlobalFallback, let getIsPlaying = resolveSymbol(handle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying", as: IsPlayingFunction.self) {
        group.enter()
        getIsPlaying(queue) { playing in
            set("isPlaying", playing)
            group.leave()
        }
    }

    _ = group.wait(timeout: .now() + 1.8)

    lock.lock()
    var snapshot = reply
    let currentSample = sample
    let currentRecording = recording
    let currentCommands = commands
    lock.unlock()

    let isPlaying = (snapshot["isPlaying"] as? Bool) ?? (((snapshot["rate"] as? Double) ?? 0) > 0)
    snapshot["isPlaying"] = isPlaying
    if let context = MediaSessionCoordinator.shared.present(target, fields: currentRecording) {
        snapshot["playbackRevision"] = context.revision.uuidString
        snapshot["controlPID"] = context.pid
        let owned = target?.ownsSystemSession == true
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
    snapshot["runningOutputBrowsers"] = BrowserAudioSnapshot.read()
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

@_cdecl("sensebar_now_playing_watch")
public func sensebarNowPlayingWatch() {
    typealias RegisterFn = @convention(c) (DispatchQueue) -> Void
    let handle = mediaRemoteHandle
    guard let register = resolveSymbol(handle, "MRMediaRemoteRegisterForNowPlayingNotifications", as: RegisterFn.self) else {
        emitJSON(["error": "notifications unavailable"])
        return
    }

    watching = true
    register(.main)

    let worker = DispatchQueue(label: "com.ngochiendev.sensebar.nowplaying.watch")
    nonisolated(unsafe) var pendingWork: DispatchWorkItem?
    nonisolated(unsafe) var followUpWork: DispatchWorkItem?
    nonisolated(unsafe) var refreshInFlight = false
    nonisolated(unsafe) var refreshRequested = false
    nonisolated(unsafe) var recoveryWork: [DispatchWorkItem] = []

    @Sendable func requestRefresh() {
        DispatchQueue.main.async {
            guard !refreshInFlight else { refreshRequested = true; return }
            refreshInFlight = true
            worker.async {
                sensebarNowPlayingGet()
                DispatchQueue.main.async {
                    refreshInFlight = false
                    if refreshRequested {
                        refreshRequested = false
                        requestRefresh()
                    }
                }
            }
        }
    }

    @Sendable func scheduleRefresh(delay: TimeInterval = 0.03) {
        DispatchQueue.main.async {
            // Keep the first deadline: timestamp notifications must not postpone pause.
            if pendingWork == nil {
                let item = DispatchWorkItem {
                    pendingWork = nil
                    requestRefresh()
                }
                pendingWork = item
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
            }
            if followUpWork == nil {
                let followUp = DispatchWorkItem {
                    followUpWork = nil
                    requestRefresh()
                }
                followUpWork = followUp
                DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.5, execute: followUp)
            }
        }
    }

    let baseNames = [
        "kMRMediaRemoteNowPlayingInfoDidChangeNotification",
        "kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
        "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
        "kMRMediaRemotePlayerNowPlayingInfoDidChangeNotification",
        "kMRMediaRemoteNowPlayingPlayerStateDidChange",
        "kMRMediaRemoteNowPlayingApplicationClientStateDidChange",
        "kMRMediaRemotePlayerIsPlayingDidChangeNotification",
        "kMRMediaRemoteNowPlayingPlayerDidChange",
        "kMRMediaRemoteActivePlayerPathsDidChange",
        "kMRMediaRemoteOriginNowPlayingInfoDidChangeNotification",
        "_kMRMediaRemotePlayerPlaybackStateDidChangeNotification"
    ]
    let resolvedSymbols = [
        "kMRMediaRemotePlayerPlaybackStateDidChangeNotification",
        "kMRMediaRemoteNowPlayingPlayerDidChange",
        "kMRMediaRemoteActivePlayerPathsDidChange",
        "kMRMediaRemoteOriginNowPlayingInfoDidChangeNotification"
    ].compactMap { MediaRemoteIO.constant($0) }

    let notificationNames = Array(Set(baseNames + resolvedSymbols))

    let observers = notificationNames.map { name in
        NotificationCenter.default.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { _ in
            scheduleRefresh()
        }
    }

    let recoveryObserver = NotificationCenter.default.addObserver(
        forName: recoveryNotification, object: nil, queue: .main
    ) { notification in
        if notification.userInfo?["active"] as? Bool != true {
            recoveryWork.forEach { $0.cancel() }
            recoveryWork.removeAll()
            return
        }
        let delays = notification.userInfo?["delays"] as? [TimeInterval] ?? []
        guard !delays.isEmpty else { return }
        recoveryWork.forEach { $0.cancel() }
        recoveryWork = delays.map { delay in
            let item = DispatchWorkItem { requestRefresh() }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
            return item
        }
    }

    // Bộ đồng bộ định kỳ nhẹ (2s) giúp tự động làm mới ngay cả khi trình duyệt chuyển tab âm thầm
    let pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
        requestRefresh()
    }
    pollTimer.tolerance = 0.4

    let appTerminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
        forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
    ) { _ in
        scheduleRefresh()
    }

    var framer = PlaybackLineFramer()
    FileHandle.standardInput.readabilityHandler = { input in
        let chunk = input.availableData
        if chunk.isEmpty { exit(0) }
        DispatchQueue.main.async {
            for line in framer.append(chunk) {
                if line == "refresh" {
                    scheduleRefresh(delay: 0)
                    continue
                }
                worker.async {
                    handleCommand(line)
                    scheduleRefresh(delay: 0.14)
                }
            }
        }
    }

    requestRefresh()
    withExtendedLifetime((observers, recoveryObserver, appTerminationObserver, pollTimer)) {
        RunLoop.main.run()
    }
}

private func handleCommand(_ line: String) {
    if let data = line.data(using: .utf8),
       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let command = json["command"] as? String {
        if command == "set_preferred_source" {
            let bundleID = (json["bundleID"] as? String) ?? "auto"
            MediaSessionCoordinator.shared.setPreferredSource(bundleID)
            return
        }
    }
    guard let request = PlaybackRequest(line) else { return }
    emitJSON(["commandAccepted": MediaSessionCoordinator.shared.perform(request)])
}
