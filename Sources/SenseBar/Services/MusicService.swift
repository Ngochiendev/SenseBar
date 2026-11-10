import AppKit
import Combine
import SwiftUI

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

    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private var tickTimer: Timer?
    private var lastSampleDate = Date()
    private nonisolated(unsafe) var rawBuffer = Data()
    private let workerQueue = DispatchQueue(label: "com.ngochiendev.sensebar.music-service", qos: .utility)

    private init() {
        start()
    }

    private static var dylibPath: String? {
        if let dylibURL = Bundle.main.privateFrameworksURL?.appendingPathComponent("libSenseBarNowPlaying.dylib"),
           FileManager.default.fileExists(atPath: dylibURL.path) {
            _ = removexattr(dylibURL.path, "com.apple.quarantine", 0)
            return dylibURL.path
        }
        let candidates = [
            Bundle.main.bundleURL.deletingLastPathComponent(),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
            URL(fileURLWithPath: "/Volumes/Data/personal_project/SenseBar")
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
        guard process == nil, let dylib = Self.dylibPath else { return }
        let proc = Process()
        let outPipe = Pipe()
        let inPipe = Pipe()

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
                self?.appendOutput(data)
            }
        }

        proc.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                self?.process = nil
                self?.start()
            }
        }

        do {
            try proc.run()
            self.process = proc
            self.outputPipe = outPipe
            self.inputPipe = inPipe
        } catch {
            outPipe.fileHandleForReading.readabilityHandler = nil
        }
    }

    func stop() {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        process?.terminate()
        process = nil
        inputPipe = nil
        outputPipe = nil
    }

    // MARK: - Playback Controls

    /// Chuyển đổi trạng thái Phát / Tạm dừng (Play / Pause) của bài hát đang phát.
    func togglePlayPause() {
        if var current = track {
            current.isPlaying.toggle()
            track = current
            lastSampleDate = Date()
            if !current.isPlaying {
                NotificationCenter.default.post(name: NSNotification.Name("SenseBarMusicDidPause"), object: nil)
            }
        }
        sendCommand("toggle")
    }

    /// Chuyển sang bài hát tiếp theo.
    func nextTrack() {
        sendCommand("next")
    }

    /// Quay lại bài hát trước đó.
    func previousTrack() {
        sendCommand("previous")
    }

    /// Tua nhanh hoặc tua lùi bài hát đến thời điểm cụ thể.
    /// - Parameter seconds: Vị trí giây trong bài hát cần phát tới.
    func seek(to seconds: TimeInterval) {
        if var current = track {
            current.elapsed = max(0, min(current.duration, seconds))
            track = current
            lastSampleDate = Date()
        }
        sendCommand(String(format: "seek:%.2f", max(0, seconds)))
    }

    /// Kích hoạt và mở ứng dụng đang phát nhạc lên màn hình (Spotify, Apple Music, Chrome,...).
    func openPlayerApp() {
        guard let track else { return }
        if !track.bundleID.isEmpty,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: track.bundleID) {
            NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
        } else if track.pid > 0,
                  let running = NSRunningApplication(processIdentifier: pid_t(track.pid)) {
            running.activate()
        }
    }

    private func sendCommand(_ command: String) {
        guard let handle = inputPipe?.fileHandleForWriting,
              let data = (command + "\n").data(using: .utf8) else { return }
        workerQueue.async {
            try? handle.write(contentsOf: data)
        }
    }

    // MARK: - Output Parsing & Elapsed Ticker

    private func startElapsedTickerIfNeeded() {
        guard tickTimer == nil else { return }
        lastSampleDate = Date()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard var current = self.track, current.isPlaying else {
                    self.stopElapsedTicker()
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
        workerQueue.async { [weak self] in
            guard let self else { return }
            self.rawBuffer.append(data)
            while let newline = self.rawBuffer.firstIndex(of: 0x0A) {
                let lineData = self.rawBuffer.subdata(in: 0..<newline)
                self.rawBuffer.removeSubrange(0...newline)
                Task { @MainActor [weak self] in
                    self?.parseJSONLine(lineData)
                }
            }
        }
    }

    private func parseJSONLine(_ data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if json["error"] != nil { return }

        var rawTitle = (json["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // Xoá badge thông báo ở đầu tiêu đề do trình duyệt thêm vào ví dụ: "(1) ", "(12) "
        if let regex = try? NSRegularExpression(pattern: #"^\(\d+\+?\)\s*"#) {
            let range = NSRange(rawTitle.startIndex..., in: rawTitle)
            rawTitle = regex.stringByReplacingMatches(in: rawTitle, options: [], range: range, withTemplate: "")
        }
        if let range = rawTitle.range(of: " - YouTube") {
            rawTitle = String(rawTitle[..<range.lowerBound])
        }
        rawTitle = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
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

        guard !rawTitle.isEmpty, !isBrowserHomepage else {
            DispatchQueue.main.async {
                self.track = nil
                self.artwork = nil
                self.stopElapsedTicker()
            }
            return
        }

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

        let parsedTrack = NowPlayingTrack(
            title: rawTitle,
            artist: artist,
            album: album,
            duration: max(0, duration),
            elapsed: max(0, elapsed),
            isPlaying: isPlaying,
            appName: appName,
            bundleID: bundleID,
            pid: pid
        )

        DispatchQueue.main.async {
            self.lastSampleDate = Date()
            self.track = parsedTrack
            if parsedTrack.isPlaying {
                self.startElapsedTickerIfNeeded()
            } else {
                self.stopElapsedTicker()
            }
            if !unchanged {
                self.artwork = newArtwork
                if let newAccent {
                    self.accentColor = newAccent
                } else {
                    self.accentColor = Color(red: 0.38, green: 0.64, blue: 1.0)
                }
            }
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
