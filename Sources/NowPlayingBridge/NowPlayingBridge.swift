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
private typealias SendCommandFunction = @convention(c) (Int32, CFDictionary?) -> Bool

private let maximumArtworkBytes = 8 * 1_024 * 1_024
private var watching = false
private var previousArtwork: Data?
private var previousTitle: String?
private var previousArtist: String?
private let emissionLock = NSLock()

private func resolveSymbol<T>(_ handle: UnsafeMutableRawPointer?, _ name: String, as type: T.Type) -> T? {
    guard let handle, let symbol = dlsym(handle, name) else { return nil }
    return unsafeBitCast(symbol, to: type)
}

private func stringConstant(_ handle: UnsafeMutableRawPointer?, _ name: String) -> String? {
    guard let handle, let symbol = dlsym(handle, name) else { return nil }
    return symbol.assumingMemoryBound(to: NSString?.self).pointee as String?
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
    let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY)
    guard let getInfo = resolveSymbol(handle, "MRMediaRemoteGetNowPlayingInfo", as: InfoFunction.self) else {
        emitJSON(["error": "MediaRemote unavailable"])
        return
    }

    let queue = DispatchQueue(label: "com.ngochiendev.sensebar.nowplaying")
    let group = DispatchGroup()
    let lock = NSLock()
    var reply: [String: Any] = [:]
    var sample: (elapsed: Double, timestamp: Date?)?

    func set(_ key: String, _ value: Any?) {
        guard let value else { return }
        lock.lock()
        reply[key] = value
        lock.unlock()
    }

    group.enter()
    getInfo(queue) { rawInfo in
        let info = (rawInfo as? [String: Any]) ?? [:]
        let title = info["kMRMediaRemoteNowPlayingInfoTitle"] as? String
        let artist = info["kMRMediaRemoteNowPlayingInfoArtist"] as? String
        set("title", title)
        set("artist", artist)
        set("album", info["kMRMediaRemoteNowPlayingInfoAlbum"] as? String)
        set("duration", (info["kMRMediaRemoteNowPlayingInfoDuration"] as? NSNumber)?.doubleValue)
        set("rate", (info["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? NSNumber)?.doubleValue)

        if let elapsed = (info["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? NSNumber)?.doubleValue {
            lock.lock()
            sample = (elapsed, info["kMRMediaRemoteNowPlayingInfoTimestamp"] as? Date)
            lock.unlock()
        }

        let artwork = info["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data
        let trackChanged = (title != previousTitle) || (artist != previousArtist)
        if watching {
            if trackChanged {
                previousTitle = title
                previousArtist = artist
                previousArtwork = artwork
                if let artwork, !artwork.isEmpty, artwork.count <= maximumArtworkBytes {
                    set("artworkBase64", artwork.base64EncodedString())
                }
            } else {
                if let artwork, !artwork.isEmpty, artwork.count <= maximumArtworkBytes {
                    if artwork == previousArtwork {
                        set("artworkUnchanged", true)
                    } else {
                        previousArtwork = artwork
                        set("artworkBase64", artwork.base64EncodedString())
                    }
                } else if previousArtwork != nil {
                    set("artworkUnchanged", true)
                }
            }
        } else if let artwork, !artwork.isEmpty, artwork.count <= maximumArtworkBytes {
            set("artworkBase64", artwork.base64EncodedString())
        }
        group.leave()
    }

    if let getPID = resolveSymbol(handle, "MRMediaRemoteGetNowPlayingApplicationPID", as: PIDFunction.self) {
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

    if let getDisplayID = resolveSymbol(handle, "MRMediaRemoteGetNowPlayingApplicationDisplayID", as: DisplayIDFunction.self) {
        group.enter()
        getDisplayID(queue) { identifier in
            if let id = identifier as String?, !id.isEmpty {
                set("bundleID", id)
            }
            group.leave()
        }
    }

    if let getIsPlaying = resolveSymbol(handle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying", as: IsPlayingFunction.self) {
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
    lock.unlock()

    let isPlaying = (snapshot["isPlaying"] as? Bool) ?? (((snapshot["rate"] as? Double) ?? 0) > 0)
    snapshot["isPlaying"] = isPlaying

    if let currentSample {
        let rate = isPlaying ? max(0, (snapshot["rate"] as? Double) ?? 1.0) : 0.0
        let age = currentSample.timestamp.map { max(0, Date().timeIntervalSince($0)) } ?? 0
        snapshot["elapsed"] = currentSample.elapsed + age * rate
    }

    emitJSON(snapshot)
}

@_cdecl("sensebar_now_playing_watch")
public func sensebarNowPlayingWatch() {
    typealias RegisterFn = @convention(c) (DispatchQueue) -> Void
    let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY)
    guard let register = resolveSymbol(handle, "MRMediaRemoteRegisterForNowPlayingNotifications", as: RegisterFn.self) else {
        emitJSON(["error": "notifications unavailable"])
        return
    }

    watching = true
    register(.main)

    let worker = DispatchQueue(label: "com.ngochiendev.sensebar.nowplaying.watch")
    var pendingWork: DispatchWorkItem?
    var followUpWork: DispatchWorkItem?

    func scheduleRefresh(delay: TimeInterval = 0.08) {
        pendingWork?.cancel()
        followUpWork?.cancel()

        let item = DispatchWorkItem { sensebarNowPlayingGet() }
        pendingWork = item
        worker.asyncAfter(deadline: .now() + delay, execute: item)

        // Trình duyệt (Chrome/Safari) khi chuyển tab phát nhạc thường cập nhật thời gian trước
        // rồi mới cập nhật Title/Artist/Artwork sau 200ms-500ms. Đọc xác nhận lần 2 để luôn khớp 100%.
        let followUp = DispatchWorkItem { sensebarNowPlayingGet() }
        followUpWork = followUp
        worker.asyncAfter(deadline: .now() + delay + 0.5, execute: followUp)
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
    ].compactMap { stringConstant(handle, $0) }

    let notificationNames = Array(Set(baseNames + resolvedSymbols))

    let observers = notificationNames.map { name in
        NotificationCenter.default.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { _ in
            scheduleRefresh()
        }
    }

    // Bộ đồng bộ định kỳ nhẹ (2s) giúp tự động làm mới ngay cả khi trình duyệt chuyển tab âm thầm
    let pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
        worker.async { sensebarNowPlayingGet() }
    }
    pollTimer.tolerance = 0.4

    let appTerminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
        forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
    ) { _ in
        scheduleRefresh()
    }

    var inputBuffer = Data()
    FileHandle.standardInput.readabilityHandler = { input in
        let chunk = input.availableData
        if chunk.isEmpty { exit(0) }
        DispatchQueue.main.async {
            inputBuffer.append(chunk)
            while let newlineIndex = inputBuffer.firstIndex(of: 0x0A) {
                let lineData = inputBuffer.subdata(in: 0..<newlineIndex)
                inputBuffer.removeSubrange(0...newlineIndex)
                if let line = String(data: lineData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !line.isEmpty {
                    worker.async {
                        handleCommand(line, handle: handle)
                        scheduleRefresh(delay: 0.14)
                    }
                }
            }
        }
    }

    worker.async { sensebarNowPlayingGet() }
    withExtendedLifetime((observers, appTerminationObserver, pollTimer)) {
        RunLoop.main.run()
    }
}

private func handleCommand(_ commandLine: String, handle: UnsafeMutableRawPointer?) {
    guard let sendCommand = resolveSymbol(handle, "MRMediaRemoteSendCommand", as: SendCommandFunction.self) else { return }
    switch commandLine {
    case "play":
        _ = sendCommand(0, nil)
    case "pause":
        _ = sendCommand(1, nil)
    case "toggle":
        _ = sendCommand(2, nil)
    case "next":
        _ = sendCommand(4, nil)
    case "previous":
        _ = sendCommand(5, nil)
    default:
        if commandLine.hasPrefix("seek:"),
           let seconds = Double(commandLine.dropFirst(5)),
           seconds.isFinite {
            let key = stringConstant(handle, "kMRMediaRemoteOptionPlaybackPosition") ?? "kMRMediaRemoteOptionPlaybackPosition"
            let options = [key: seconds] as CFDictionary
            _ = sendCommand(24, options)
        }
    }
}

