import AppKit
import Combine
import SwiftUI

struct MediaSourceItem: Equatable, Identifiable {
    var id: String { bundleID }
    let bundleID: String
    let appName: String
    let isPlaying: Bool
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
    var sourceDisplayName: String {
        if let track { return track.appName }
        guard preferredSource != "auto" else { return L10n.shared.string(vi: "Nhạc", en: "Now Playing") }
        if let source = availableSources.first(where: { $0.bundleID == preferredSource }) { return source.appName }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: preferredSource) {
            return url.deletingPathExtension().lastPathComponent
        }
        return preferredSource
    }
    var hasMediaPresentation: Bool { track?.isPlaying == true }

    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private var tickTimer: Timer?
    private var lastSampleDate = Date()
    private var shouldRun = false
    private var cachedRemoteArtwork: NSImage?
    private var cachedRemoteAccent: Color?
    private var rawBuffer = Data()
    private var bridgeGeneration = UUID()
    private let workerQueue = DispatchQueue(label: "com.ngochiendev.sensebar.music-service", qos: .utility)

    private init(autostart: Bool = true) {
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
        bridgeGeneration = UUID()
        rawBuffer.removeAll(keepingCapacity: false)
        stopElapsedTicker()
        shouldRun = false
        process?.terminationHandler = nil
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        process?.terminate()
        process = nil
        inputPipe = nil
        outputPipe = nil
        cachedRemoteArtwork = nil
        cachedRemoteAccent = nil
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
        let service = MusicService(autostart: false)
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
        guard service.track?.isPlaying == false, !service.hasMediaPresentation,
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
        let pausedChrome: [String: Any] = ["title": "YouTube video", "bundleID": "com.google.Chrome", "pid": 200,
            "isPlaying": false, "preferredSource": "com.google.Chrome", "supportsTransportControls": true,
            "controlPID": 200, "playbackRevision": UUID().uuidString,
            "runningOutputBrowsers": [["bundleID": "com.google.Chrome", "appName": "Google Chrome", "pid": 200]]]
        guard let pausedData = try? JSONSerialization.data(withJSONObject: pausedChrome) else { return false }
        service.parseJSONLine(pausedData)
        guard service.track?.title == "YouTube video", service.track?.isPlaying == false,
              service.track?.supportsTransportControls == true else { return false }
        service.stop()
        return service.track == nil && service.artwork == nil
    }

    func refreshNowPlaying() {
        guard let handle = inputPipe?.fileHandleForWriting else { return }
        workerQueue.async { try? handle.write(contentsOf: Data("refresh\n".utf8)) }
    }

    /// Chọn nguồn phát cụ thể (hoặc "auto" để tự động nhận diện)
    func selectSource(_ bundleID: String) {
        guard preferredSource != bundleID else { return }
        preferredSource = bundleID
        track = nil
        artwork = nil
        cachedRemoteArtwork = nil
        cachedRemoteAccent = nil
        stopElapsedTicker()
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
        guard let pipe = inputPipe, let track, track.supportsTransportControls,
              let revision = track.playbackRevision, let controlPID = track.controlPID else { return }
        var dict: [String: Any] = ["command": command, "playbackRevision": revision, "controlPID": controlPID]
        if let position { dict["position"] = position }
        guard let json = try? JSONSerialization.data(withJSONObject: dict),
              let line = String(data: json, encoding: .utf8) else { return }
        workerQueue.async {
            try? pipe.fileHandleForWriting.write(contentsOf: Data((line + "\n").utf8))
        }
    }

    // MARK: - Internal Engine

    private func startElapsedTickerIfNeeded() {
        guard tickTimer == nil else { return }
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, var current = self.track, current.isPlaying else {
                    self?.stopElapsedTicker()
                    return
                }
                let now = Date()
                let delta = now.timeIntervalSince(self.lastSampleDate)
                self.lastSampleDate = now
                if current.duration > 0 {
                    current.elapsed = min(current.duration, current.elapsed + delta)
                } else {
                    current.elapsed += delta
                }
                self.track = current
            }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    private func stopElapsedTicker() {
        tickTimer?.invalidate()
        tickTimer = nil
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
            if parsedSources != self.availableSources {
                self.availableSources = parsedSources
            }
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
        guard let resolution = MediaPlaybackPolicy.resolve(title: isBrowserHomepage ? "" : rawTitle,
            bundleID: bundleID, appName: appName, pid: pid, isPlaying: isPlaying, browsers: browsers, preferredSource: preferredSource) else {
            self.track = nil
            self.artwork = nil
            self.stopElapsedTicker()
            return
        }

        let revision = (json["playbackRevision"] as? String).flatMap(UUID.init(uuidString:))
        let controlPID = json["controlPID"] as? Int
        let canControl = resolution.usesRemoteMetadata && json["supportsTransportControls"] as? Bool == true
            && revision != nil && (controlPID ?? 0) > 0
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
            supportsNext: canControl && json["supportsNext"] as? Bool == true,
            supportsPrevious: canControl && json["supportsPrevious"] as? Bool == true,
            supportsSeeking: canControl && json["supportsSeeking"] as? Bool == true,
            playbackRevision: revision?.uuidString,
            controlPID: controlPID
        )
        self.lastSampleDate = Date()
        self.track = parsedTrack
        if parsedTrack.isPlaying && parsedTrack.duration > 0 {
            self.startElapsedTickerIfNeeded()
        } else {
            self.stopElapsedTicker()
        }
        if !resolution.usesRemoteMetadata {
            self.artwork = NSRunningApplication(processIdentifier: pid_t(resolution.pid))?.icon
            self.accentColor = Color(red: 0.38, green: 0.64, blue: 1.0)
        } else {
            self.artwork = cachedRemoteArtwork
            self.accentColor = cachedRemoteAccent ?? Color(red: 0.38, green: 0.64, blue: 1.0)
        }
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
