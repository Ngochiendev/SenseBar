import AppKit
import Combine
import SwiftUI

struct MediaSourceItem: Equatable, Identifiable {
    var id: String { bundleID }
    let bundleID: String
    let appName: String
    let isPlaying: Bool
    var isAudioOnly = false
}

struct NowPlayingTrack: Equatable {
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval
    var elapsed: TimeInterval
    var isPlaying: Bool
    var appName: String
    var bundleID: String
    var pid: Int
    var supportsTransportControls = false
    var supportsNext = false
    var supportsPrevious = false
    var supportsSeeking = false
    var playbackRevision: String?
    var controlPID: Int?
    var selectedPlayerCommands: Set<String> = []
    var playerSupportsNext = false
    var playerSupportsPrevious = false

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, elapsed / duration))
    }

    static func formattedTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        let hours = total / 3600
        let mins = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, mins, secs)
        }
        return String(format: "%d:%02d", mins, secs)
    }
}

@MainActor
final class MusicService: ObservableObject {
    static let shared = MusicService()

    @Published private(set) var track: NowPlayingTrack?
    @Published private(set) var artwork: NSImage?
    @Published private(set) var accentColor: Color = Color(red: 0.98, green: 0.58, blue: 0.12)
    @Published private(set) var availableSources: [MediaSourceItem] = []
    @Published private(set) var preferredSource: String = "auto"
    @Published private(set) var isControlPending = false
    @Published private(set) var controlError: String?
    var sourceDisplayName: String {
        if let track { return track.appName }
        guard preferredSource != "auto" else { return L10n.shared.string(vi: "Nhạc", en: "Now Playing") }
        if let source = availableSources.first(where: { $0.bundleID == preferredSource }) { return source.appName }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: preferredSource) {
            return url.deletingPathExtension().lastPathComponent
        }
        return preferredSource
    }
    var hasMediaPresentation: Bool { track != nil }

    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private var lastSampleDate = Date()
    private var shouldRun = false
    private var cachedRemoteArtwork: NSImage?
    private var cachedRemoteAccent: Color?
    private let browserArtwork = BrowserArtworkService()
    private let selectedPlayerControl = SelectedPlayerControl()
    private var selectedControlTarget: SelectedPlayerTarget?
    private var selectedControlCapabilities = SelectedPlayerCapabilities()
    private var nativeControlCapabilities = SelectedPlayerCapabilities()
    private var selectedControlScan: Task<Void, Never>?
    private var selectedControlAction: Task<Void, Never>?
    private var controlGeneration = UUID()
    private var rawBuffer = Data()
    private var bridgeGeneration = UUID()
    private var terminationObserver: NSObjectProtocol?
    private let isApplicationRunning: (String) -> Bool
    private let workerQueue = DispatchQueue(label: "com.ngochiendev.sensebar.music-service", qos: .utility)

    private init(autostart: Bool = true, isApplicationRunning: @escaping (String) -> Bool = { bundle in
        NSRunningApplication.runningApplications(withBundleIdentifier: bundle).contains { !$0.isTerminated }
    }) {
        self.isApplicationRunning = isApplicationRunning
        preferredSource = UserDefaults.standard.string(forKey: "SenseBarMediaPreferredSource") ?? "auto"
        if autostart { start() }
    }

    private static var dylibPath: String? {
        if let dylibURL = Bundle.main.privateFrameworksURL?.appendingPathComponent("libSenseBarNowPlaying.dylib"),
           FileManager.default.fileExists(atPath: dylibURL.path) {
            _ = removexattr(dylibURL.path, "com.apple.quarantine", 0)
            return dylibURL.path
        }
        if let executable = Bundle.main.executableURL {
            let adjacent = executable.deletingLastPathComponent().appendingPathComponent("libSenseBarNowPlaying.dylib")
            if FileManager.default.fileExists(atPath: adjacent.path) { return adjacent.path }
        }
        let candidates = [
            Bundle.main.bundleURL.deletingLastPathComponent(),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        ]
        for root in candidates {
            let dylib = root.appendingPathComponent("build/libSenseBarNowPlaying.dylib").path
            if FileManager.default.fileExists(atPath: dylib) {
                _ = removexattr(dylib, "com.apple.quarantine", 0)
                return dylib
            }
        }
        return nil
    }

    private static let inlinePerlLoader = """
    use strict; use warnings; use DynaLoader; $| = 1;
    my ($lib, $mode) = @ARGV; $mode //= 'watch';
    my $h = DynaLoader::dl_load_file($lib, 0) or die;
    my $s = DynaLoader::dl_find_symbol($h, "sensebar_now_playing_$mode") or die;
    DynaLoader::dl_install_xsub('main::run', $s); run();
    """

    func start() {
        shouldRun = true
        if terminationObserver == nil {
            terminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
            ) { [weak self] notification in
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      let bundle = app.bundleIdentifier else { return }
                let pid = Int(app.processIdentifier)
                Task { @MainActor [weak self] in
                    self?.applicationTerminated(bundleID: bundle, pid: pid)
                }
            }
        }
        guard process == nil, let dylib = Self.dylibPath else { return }
        let proc = Process()
        let outPipe = Pipe()
        let inPipe = Pipe()
        let generation = UUID()
        bridgeGeneration = generation
        rawBuffer.removeAll(keepingCapacity: true)

        _ = fcntl(inPipe.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        proc.arguments = ["-e", Self.inlinePerlLoader, dylib, "watch"]
        proc.standardOutput = outPipe
        proc.standardError = FileHandle.nullDevice
        proc.standardInput = inPipe

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            Task { @MainActor [weak self] in
                guard let self, self.bridgeGeneration == generation else { return }
                self.appendOutput(data)
            }
        }

        proc.terminationHandler = { [weak self] ended in
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard let self, self.shouldRun, self.process === ended else { return }
                self.process = nil
                self.start()
            }
        }

        do {
            try proc.run()
            self.process = proc
            self.outputPipe = outPipe
            self.inputPipe = inPipe
            self.sendPreferredSourceCommand(self.preferredSource)
        } catch {
            outPipe.fileHandleForReading.readabilityHandler = nil
        }
    }

    func stop() {
        if let terminationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(terminationObserver)
            self.terminationObserver = nil
        }
        resetSelectedPlayerControl()
        bridgeGeneration = UUID()
        rawBuffer.removeAll(keepingCapacity: false)
        shouldRun = false
        process?.terminationHandler = nil
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        process?.terminate()
        process = nil
        inputPipe = nil
        outputPipe = nil
        cachedRemoteArtwork = nil
        cachedRemoteAccent = nil
        browserArtwork.cancel()
        track = nil
        artwork = nil
        availableSources = []
    }

    // MARK: - Playback Controls

    static func cleanMediaTitle(_ title: String) -> String {
        var cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let regex = try? NSRegularExpression(pattern: #"^\(\d+\+?\)\s*"#) {
            let range = NSRange(cleaned.startIndex..., in: cleaned)
            cleaned = regex.stringByReplacingMatches(in: cleaned, options: [], range: range, withTemplate: "")
        }
        for suffix in [" - YouTube", " – YouTube"] {
            if cleaned.hasSuffix(suffix) { cleaned.removeLast(suffix.count) }
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func validatePlaybackParser() -> Bool {
        let service = MusicService(autostart: false, isApplicationRunning: { _ in true })
        defer { service.stop() }
        func apply(title: String, artist: String, playing: Bool) {
            let fields: [String: Any] = ["title": title, "artist": artist, "duration": 180,
                "pid": 100, "bundleID": "com.spotify.client", "appName": "Spotify",
                "isPlaying": playing, "supportsTransportControls": true]
            if let data = try? JSONSerialization.data(withJSONObject: fields) { service.parseJSONLine(data) }
        }
        apply(title: "Song A", artist: "Artist A", playing: true)
        guard service.track?.title == "Song A", service.track?.artist == "Artist A", service.hasMediaPresentation else { return false }
        apply(title: "Song A", artist: "Artist A", playing: false)
        guard service.track?.isPlaying == false, service.hasMediaPresentation,
              service.track?.supportsTransportControls == false else { return false }
        let revision = UUID().uuidString
        let valid: [String: Any] = ["title": "Song A", "bundleID": "com.spotify.client", "pid": 100,
            "isPlaying": true, "supportsTransportControls": true, "controlPID": 100, "playbackRevision": revision]
        guard let data = try? JSONSerialization.data(withJSONObject: valid) else { return false }
        // Exercise real pipe framing, including a split line and multiple records per chunk.
        let split = data.count / 2
        service.appendOutput(data.prefix(split))
        guard service.track?.isPlaying == false else { return false }
        service.appendOutput(data.suffix(from: split) + Data("\n{}\n".utf8))
        guard service.track == nil else { return false }
        service.parseJSONLine(data)
        guard service.track?.supportsTransportControls == true else { return false }
        service.parseJSONLine(Data("{\"commandAccepted\":false}".utf8))
        guard service.track?.title == "Song A", service.track?.isPlaying == true else { return false }
        service.preferredSource = "com.google.Chrome"
        service.track = nil
        var stale = valid
        stale["preferredSource"] = "auto"
        guard let staleData = try? JSONSerialization.data(withJSONObject: stale) else { return false }
        service.parseJSONLine(staleData)
        guard service.track == nil else { return false }
        // Transport and paused presentation depend on the session, not an app allowlist.
        for bundle in ["com.google.Chrome", "org.mozilla.firefox", "app.zen-browser.zen",
                       "com.apple.Safari", "com.brave.Browser", "com.spotify.client",
                       "com.apple.Music", "test.other-player"] {
            for selection in ["auto", bundle] {
                service.preferredSource = selection
                let ticket = UUID().uuidString
                for playing in [true, false, true] {
                    let fields: [String: Any] = ["title": "Test recording", "artist": "Test artist",
                        "bundleID": bundle, "pid": 200, "duration": 180, "elapsed": 60,
                        "isPlaying": playing, "preferredSource": selection,
                        "supportsTransportControls": true, "supportsNext": true,
                        "supportsPrevious": false, "supportsSeeking": true,
                        "controlPID": 200, "playbackRevision": ticket]
                    guard let payload = try? JSONSerialization.data(withJSONObject: fields) else { return false }
                    service.parseJSONLine(payload)
                    guard let track = service.track, service.hasMediaPresentation,
                          track.bundleID == bundle, track.isPlaying == playing,
                          track.supportsTransportControls, track.supportsNext,
                          !track.supportsPrevious, track.supportsSeeking,
                          track.playbackRevision == ticket, track.elapsed == 60 else { return false }
                }
            }
        }
        service.preferredSource = "auto"
        var skipOnly = valid
        skipOnly["supportsTransportControls"] = false
        skipOnly["supportsNext"] = true
        skipOnly["supportsPrevious"] = true
        skipOnly["supportsSeeking"] = true
        guard let skipData = try? JSONSerialization.data(withJSONObject: skipOnly) else { return false }
        service.parseJSONLine(skipData)
        guard service.track?.supportsTransportControls == false, service.track?.supportsNext == true,
              service.track?.supportsPrevious == true, service.track?.supportsSeeking == true else { return false }
        service.applicationTerminated(bundleID: "com.spotify.client", pid: 100)
        guard service.track == nil, service.artwork == nil else { return false }
        service.parseJSONLine(skipData)
        guard service.track?.title == "Song A" else { return false }
        let exitedBrowser = MusicService(autostart: false, isApplicationRunning: { _ in false })
        exitedBrowser.preferredSource = "auto"
        var staleBrowser = valid
        staleBrowser["bundleID"] = "com.apple.Safari"
        guard let staleBrowserData = try? JSONSerialization.data(withJSONObject: staleBrowser) else { return false }
        exitedBrowser.parseJSONLine(staleBrowserData)
        guard exitedBrowser.track == nil else { return false }
        service.parseJSONLine(staleBrowserData)
        guard service.track?.bundleID == "com.apple.Safari" else { return false }
        staleBrowser["closedBrowserBundles"] = ["com.apple.Safari"]
        guard let closedWindowData = try? JSONSerialization.data(withJSONObject: staleBrowser) else { return false }
        service.parseJSONLine(closedWindowData)
        guard service.track == nil, service.artwork == nil else { return false }
        staleBrowser["bundleID"] = "com.google.Chrome"
        guard let otherBrowserData = try? JSONSerialization.data(withJSONObject: staleBrowser) else { return false }
        service.parseJSONLine(otherBrowserData)
        guard service.track?.bundleID == "com.google.Chrome", service.track?.isPlaying == true else { return false }
        service.stop()
        return service.track == nil && service.artwork == nil
    }

    func refreshNowPlaying() {
        guard let handle = inputPipe?.fileHandleForWriting else { return }
        workerQueue.async { try? handle.write(contentsOf: Data("refresh\n".utf8)) }
    }

    /// Bỏ phiên của ứng dụng đã thoát và trở về tự động nếu nguồn ghim không còn chạy.
    private func applicationTerminated(bundleID: String, pid: Int) {
        availableSources.removeAll { $0.bundleID.caseInsensitiveCompare(bundleID) == .orderedSame }
        if preferredSource.caseInsensitiveCompare(bundleID) == .orderedSame {
            selectSource("auto")
            return
        }
        if track?.pid == pid || track?.bundleID.caseInsensitiveCompare(bundleID) == .orderedSame {
            resetSelectedPlayerControl()
            track = nil
            artwork = nil
            cachedRemoteArtwork = nil
            cachedRemoteAccent = nil
            browserArtwork.cancel()
        }
        refreshNowPlaying()
    }

    /// Chọn nguồn phát cụ thể (hoặc "auto" để tự động nhận diện)
    func selectSource(_ bundleID: String) {
        guard preferredSource != bundleID else { return }
        resetSelectedPlayerControl()
        preferredSource = bundleID
        track = nil
        artwork = nil
        cachedRemoteArtwork = nil
        cachedRemoteAccent = nil
        browserArtwork.cancel()
        UserDefaults.standard.set(bundleID, forKey: "SenseBarMediaPreferredSource")
        sendPreferredSourceCommand(bundleID)
        refreshNowPlaying()
    }

    private func sendPreferredSourceCommand(_ bundleID: String) {
        guard let pipe = inputPipe else { return }
        let dict: [String: Any] = ["command": "set_preferred_source", "bundleID": bundleID]
        guard let json = try? JSONSerialization.data(withJSONObject: dict),
              let line = String(data: json, encoding: .utf8) else { return }
        workerQueue.async {
            try? pipe.fileHandleForWriting.write(contentsOf: Data((line + "\n").utf8))
        }
    }

    /// Chuyển đổi trạng thái Phát / Tạm dừng (Play / Pause) của bài hát đang phát.
    func togglePlayPause() {
        guard track?.supportsTransportControls == true else { return }
        sendCommand(track?.isPlaying == true ? "pause" : "play")
    }

    /// Chuyển sang bài hát tiếp theo.
    func nextTrack() {
        guard track?.supportsNext == true else { return }
        sendCommand("next")
    }

    /// Quay lại bài hát trước đó.
    func previousTrack() {
        guard track?.supportsPrevious == true else { return }
        sendCommand("previous")
    }

    /// Tua nhanh hoặc tua lùi bài hát đến thời điểm cụ thể.
    /// - Parameter seconds: Vị trí giây trong bài hát cần phát tới.
    func seek(to seconds: TimeInterval) {
        guard let track, track.supportsSeeking, track.duration > 0, seconds.isFinite else { return }
        sendCommand("seek", position: max(0, min(track.duration, seconds)))
    }

    /// Kích hoạt và mở ứng dụng đang phát nhạc lên màn hình (Spotify, Apple Music, Chrome,...).
    func openPlayerApp() {
        let bundleID = track?.bundleID ?? (preferredSource == "auto" ? "" : preferredSource)
        guard !bundleID.isEmpty else { return }
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            app.activate()
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    private func sendCommand(_ command: String, position: Double? = nil) {
        guard !isControlPending else { return }
        if let track, track.selectedPlayerCommands.contains(command), command != "seek",
           let target = selectedControlTarget, SelectedPlayerTarget(track) == target {
            let generation = controlGeneration
            isControlPending = true
            controlError = nil
            selectedControlAction = Task { [weak self, selectedPlayerControl] in
                let accepted = await selectedPlayerControl.perform(command, target: target)
                guard !Task.isCancelled, let self, self.controlGeneration == generation else { return }
                self.selectedControlAction = nil
                self.isControlPending = false
                if !accepted {
                    self.controlError = L10n.shared.string(vi: "Không điều khiển được nguồn đã chọn. Mở ứng dụng và thử lại.",
                        en: "Couldn't control the selected source. Open the app and try again.")
                }
                self.refreshNowPlaying()
            }
            return
        }
        guard let pipe = inputPipe, let track,
              let revision = track.playbackRevision, let controlPID = track.controlPID else { return }
        let supported: Bool
        switch command {
        case "play", "pause": supported = track.supportsTransportControls
        case "next": supported = track.supportsNext
        case "previous": supported = track.supportsPrevious
        case "seek": supported = track.supportsSeeking
        default: supported = false
        }
        guard supported else { return }
        var dict: [String: Any] = ["command": command, "playbackRevision": revision, "controlPID": controlPID]
        if let position { dict["position"] = position }
        guard let json = try? JSONSerialization.data(withJSONObject: dict),
              let line = String(data: json, encoding: .utf8) else { return }
        workerQueue.async {
            try? pipe.fileHandleForWriting.write(contentsOf: Data((line + "\n").utf8))
        }
    }

    // MARK: - Internal Engine

    private func resetSelectedPlayerControl() {
        controlGeneration = UUID()
        selectedControlScan?.cancel()
        selectedControlAction?.cancel()
        selectedControlScan = nil
        selectedControlAction = nil
        selectedControlTarget = nil
        selectedControlCapabilities = SelectedPlayerCapabilities()
        isControlPending = false
        controlError = nil
    }

    private func applySelectedCapabilities() {
        guard var current = track, let target = selectedControlTarget,
              SelectedPlayerTarget(current) == target else { return }
        let capabilities = selectedControlCapabilities
        current.supportsTransportControls = nativeControlCapabilities.play || nativeControlCapabilities.pause
            || (current.isPlaying ? capabilities.pause : capabilities.play)
        current.supportsNext = nativeControlCapabilities.next || capabilities.next
        current.supportsPrevious = nativeControlCapabilities.previous || capabilities.previous
        current.selectedPlayerCommands = Set([
            capabilities.play ? "play" : nil, capabilities.pause ? "pause" : nil,
            capabilities.next ? "next" : nil, capabilities.previous ? "previous" : nil
        ].compactMap { $0 })
        track = current
    }

    private func discoverSelectedPlayerControl(remoteMetadata: Bool) {
        guard shouldRun, remoteMetadata, let current = track,
              !(current.supportsTransportControls && current.supportsNext && current.supportsPrevious),
              let target = SelectedPlayerTarget(current) else {
            resetSelectedPlayerControl()
            return
        }
        if target != selectedControlTarget {
            resetSelectedPlayerControl()
            selectedControlTarget = target
        }
        applySelectedCapabilities()
        guard selectedControlScan == nil else { return }
        let generation = controlGeneration
        selectedControlScan = Task { [weak self, selectedPlayerControl] in
            let capabilities = await selectedPlayerControl.capabilities(for: target)
            guard !Task.isCancelled, let self, self.controlGeneration == generation,
                  self.selectedControlTarget == target else { return }
            self.selectedControlScan = nil
            self.selectedControlCapabilities = capabilities
            self.applySelectedCapabilities()
        }
    }

    func displayTrack(at date: Date) -> NowPlayingTrack? {
        guard var current = track else { return nil }
        if current.isPlaying {
            current.elapsed += max(0, date.timeIntervalSince(lastSampleDate))
            if current.duration > 0 { current.elapsed = min(current.elapsed, current.duration) }
        }
        return current
    }

    private func appendOutput(_ data: Data) {
        rawBuffer.append(data)
        while let newline = rawBuffer.firstIndex(of: 0x0A) {
            let line = rawBuffer.subdata(in: rawBuffer.startIndex..<newline)
            rawBuffer.removeSubrange(rawBuffer.startIndex...newline)
            parseJSONLine(line)
        }
    }

    private func parseJSONLine(_ data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if json["error"] != nil || json["commandAccepted"] != nil { return }
        if let selection = json["preferredSource"] as? String, selection != preferredSource { return }

        if let sourcesList = json["availableSources"] as? [[String: Any]] {
            let parsedSources = sourcesList.compactMap { item -> MediaSourceItem? in
                guard let bundle = item["bundleID"] as? String,
                      let name = item["appName"] as? String else { return nil }
                return MediaSourceItem(bundleID: bundle, appName: name, isPlaying: item["isPlaying"] as? Bool == true)
            }
            var merged = parsedSources
            for item in json["runningOutputApplications"] as? [[String: Any]] ?? [] {
                guard let bundle = item["bundleID"] as? String, let name = item["appName"] as? String,
                      !Self.isBrowserBundle(bundle),
                      !merged.contains(where: { $0.bundleID.caseInsensitiveCompare(bundle) == .orderedSame }) else { continue }
                merged.append(MediaSourceItem(bundleID: bundle, appName: name, isPlaying: true, isAudioOnly: true))
            }
            merged.sort { $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending }
            if merged != self.availableSources { self.availableSources = merged }
        }

        let rawTitle = Self.cleanMediaTitle(json["title"] as? String ?? "")
        let artist = (json["artist"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let album = (json["album"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let duration = (json["duration"] as? Double) ?? 0
        let elapsed = (json["elapsed"] as? Double) ?? 0
        let isPlaying = (json["isPlaying"] as? Bool) ?? false
        let bundleID = (json["bundleID"] as? String) ?? ""
        let pid = (json["pid"] as? Int) ?? 0
        let appName = (json["appName"] as? String) ?? Self.friendlyAppName(for: bundleID)
        let closedBrowsers = Set(json["closedBrowserBundles"] as? [String] ?? [])
        if closedBrowsers.contains(preferredSource) {
            selectSource("auto")
            return
        }
        if closedBrowsers.contains(bundleID) {
            resetSelectedPlayerControl()
            track = nil
            artwork = nil
            cachedRemoteArtwork = nil
            cachedRemoteAccent = nil
            browserArtwork.cancel()
            return
        }
        if YouTubeCandidateFamily.classify(bundleID: bundleID)?.isBrowser == true,
           !isApplicationRunning(bundleID) {
            if track?.bundleID == bundleID || preferredSource == bundleID {
                applicationTerminated(bundleID: bundleID, pid: pid)
            }
            return
        }

        let isBrowser = bundleID.lowercased().contains("chrome")
            || bundleID.lowercased().contains("brave")
            || bundleID.lowercased().contains("arc")
            || bundleID.lowercased().contains("edge")

        let isBrowserHomepage = isBrowser && (rawTitle.lowercased() == "youtube" || rawTitle.lowercased() == "new tab" || rawTitle.lowercased() == "tab mới") && (!isPlaying || duration <= 0)

        var newArtwork: NSImage?
        var newAccent: Color?
        let unchanged = (json["artworkUnchanged"] as? Bool) == true
        if !unchanged,
           let base64 = json["artworkBase64"] as? String,
           let imageData = Data(base64Encoded: base64),
           let image = NSImage(data: imageData) {
            newArtwork = image
            newAccent = Self.extractAccentColor(from: image)
        }
        if !unchanged {
            cachedRemoteArtwork = newArtwork
            cachedRemoteAccent = newAccent
        }

        let browsers = (json["runningOutputBrowsers"] as? [[String: Any]] ?? []).compactMap { item -> BrowserPlaybackActivity? in
            guard let bundle = item["bundleID"] as? String, let name = item["appName"] as? String,
                  let pid = item["pid"] as? Int else { return nil }
            return BrowserPlaybackActivity(bundleID: bundle, appName: name, pid: pid)
        }
        let audioOutputs = (json["runningOutputApplications"] as? [[String: Any]] ?? []).compactMap { item -> AudioOutputActivity? in
            guard let bundle = item["bundleID"] as? String, let name = item["appName"] as? String,
                  let pid = item["pid"] as? Int, !Self.isBrowserBundle(bundle) else { return nil }
            return AudioOutputActivity(bundleID: bundle, appName: name, pid: pid)
        }
        guard let resolution = MediaPlaybackPolicy.resolve(title: isBrowserHomepage ? "" : rawTitle,
            bundleID: bundleID, appName: appName, pid: pid, isPlaying: isPlaying, browsers: browsers,
            audioOutputs: audioOutputs, preferredSource: preferredSource) else {
            self.track = nil
            resetSelectedPlayerControl()
            browserArtwork.cancel()
            self.artwork = nil
            return
        }

        let revision = (json["playbackRevision"] as? String).flatMap(UUID.init(uuidString:))
        let controlPID = json["controlPID"] as? Int
        let hasTicket = resolution.usesRemoteMetadata && revision != nil && (controlPID ?? 0) > 0
        let canControl = hasTicket && json["supportsTransportControls"] as? Bool == true
        let parsedTrack = NowPlayingTrack(
            title: resolution.title,
            artist: resolution.usesRemoteMetadata ? artist : "",
            album: resolution.usesRemoteMetadata ? album : "",
            duration: resolution.usesRemoteMetadata ? max(0, duration) : 0,
            elapsed: resolution.usesRemoteMetadata ? max(0, elapsed) : 0,
            isPlaying: resolution.isPlaying,
            appName: resolution.appName,
            bundleID: resolution.bundleID,
            pid: resolution.pid,
            supportsTransportControls: canControl,
            supportsNext: hasTicket && json["supportsNext"] as? Bool == true,
            supportsPrevious: hasTicket && json["supportsPrevious"] as? Bool == true,
            supportsSeeking: hasTicket && json["supportsSeeking"] as? Bool == true,
            playbackRevision: revision?.uuidString,
            controlPID: controlPID,
            playerSupportsNext: json["playerSupportsNext"] as? Bool == true,
            playerSupportsPrevious: json["playerSupportsPrevious"] as? Bool == true
        )
        nativeControlCapabilities = SelectedPlayerCapabilities(play: parsedTrack.supportsTransportControls,
            pause: parsedTrack.supportsTransportControls, next: parsedTrack.supportsNext, previous: parsedTrack.supportsPrevious)
        self.lastSampleDate = Date()
        self.track = parsedTrack
        discoverSelectedPlayerControl(remoteMetadata: resolution.usesRemoteMetadata)
        if !resolution.usesRemoteMetadata {
            browserArtwork.cancel()
            self.artwork = Self.applicationIcon(bundleID: resolution.bundleID, pid: resolution.pid)
            self.accentColor = Color(red: 0.38, green: 0.64, blue: 1.0)
        } else {
            let icon = Self.applicationIcon(bundleID: resolution.bundleID, pid: resolution.pid)
            let fallbackEnabled = BrowserArtworkService.supports(parsedTrack.bundleID)
            self.artwork = (fallbackEnabled && BrowserArtworkService.needsCover(cachedRemoteArtwork)
                ? browserArtwork.cached(title: parsedTrack.title, artist: parsedTrack.artist, bundleID: parsedTrack.bundleID) : nil)
                ?? cachedRemoteArtwork ?? icon
            self.accentColor = cachedRemoteAccent ?? Color(red: 0.38, green: 0.64, blue: 1.0)
            if BrowserArtworkService.needsCover(cachedRemoteArtwork), fallbackEnabled {
                browserArtwork.load(title: parsedTrack.title, artist: parsedTrack.artist, bundleID: parsedTrack.bundleID) { [weak self] image in
                    guard let self, self.track?.bundleID == parsedTrack.bundleID,
                          self.track?.title == parsedTrack.title, self.track?.artist == parsedTrack.artist,
                          BrowserArtworkService.needsCover(self.cachedRemoteArtwork) else { return }
                    self.artwork = image ?? self.cachedRemoteArtwork ?? icon
                    if let image { self.accentColor = Self.extractAccentColor(from: image) }
                }
            } else {
                browserArtwork.cancel()
            }
        }
    }

    private static func applicationIcon(bundleID: String, pid: Int) -> NSImage? {
        if pid > 0, let icon = NSRunningApplication(processIdentifier: pid_t(pid))?.icon { return icon }
        guard !bundleID.isEmpty,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    private static func isBrowserBundle(_ bundleID: String) -> Bool {
        let id = bundleID.lowercased()
        return id.contains("chrome") || id.contains("safari") || id.contains("firefox")
            || id.contains("zen-browser") || id.contains("brave") || id.contains("edgemac")
            || id.contains("vivaldi") || id.contains("operasoftware") || id.contains("thebrowser")
    }

    private static func friendlyAppName(for bundleID: String) -> String {
        let lower = bundleID.lowercased()
        if lower.contains("spotify") { return "Spotify" }
        if lower.contains("com.apple.music") { return "Apple Music" }
        if lower.contains("chrome") { return "Google Chrome" }
        if lower.contains("safari") { return "Safari" }
        if lower.contains("firefox") { return "Firefox" }
        if lower.contains("arc") { return "Arc" }
        return "Trình phát nhạc"
    }

    private static func extractAccentColor(from image: NSImage) -> Color {
        let fallback = Color(red: 0.98, green: 0.58, blue: 0.12)
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return fallback
        }
        let width = 8, height = 8
        var pixelData = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return fallback
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var rTotal: Double = 0, gTotal: Double = 0, bTotal: Double = 0, weightTotal: Double = 0
        for i in stride(from: 0, to: pixelData.count, by: 4) {
            let r = Double(pixelData[i]) / 255.0
            let g = Double(pixelData[i + 1]) / 255.0
            let b = Double(pixelData[i + 2]) / 255.0
            let maxC = max(r, g, b), minC = min(r, g, b)
            let saturation = maxC > 0 ? (maxC - minC) / maxC : 0
            let weight = 0.2 + saturation * 2.5
            rTotal += r * weight
            gTotal += g * weight
            bTotal += b * weight
            weightTotal += weight
        }
        guard weightTotal > 0 else { return Color(red: 0.38, green: 0.64, blue: 1.0) }
        let r = min(1.0, max(0.35, rTotal / weightTotal * 1.25))
        let g = min(1.0, max(0.35, gTotal / weightTotal * 1.25))
        let b = min(1.0, max(0.35, bTotal / weightTotal * 1.25))
        return Color(red: r, green: g, blue: b)
    }
}
