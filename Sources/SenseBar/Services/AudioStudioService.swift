import AppKit
import Combine
import CoreAudio

struct AudioAppEntry: Identifiable, Equatable {
    let id: String
    let name: String
    let bundleID: String
    let icon: NSImage
    var volume: Double // 0.0 ... 2.0 (0% - 200%)
    var isMuted: Bool
}

@MainActor
final class AudioStudioService: ObservableObject {
    static let shared = AudioStudioService()

    @Published var masterVolume: Double = 0.75
    @Published var isMasterMuted: Bool = false
    @Published private(set) var outputDeviceName: String = "Loa MacBook"
    @Published var apps: [AudioAppEntry] = []

    private var savedAppVolumes: [String: Double] = [:]
    private var savedAppMutes: [String: Bool] = [:]
    private var workspaceObservers: [NSObjectProtocol] = []
    private let appleScriptQueue = DispatchQueue(label: "com.ngochiendev.sensebar.audio-script", qos: .userInitiated)

    private static let knownAudioBundles: Set<String> = [
        "com.apple.Music",
        "com.spotify.client",
        "com.google.Chrome",
        "com.apple.Safari",
        "company.thebrowser.Browser",
        "org.mozilla.firefox",
        "com.microsoft.edgemac",
        "com.brave.Browser",
        "com.hnc.Discord",
        "org.videolan.vlc",
        "com.colliderli.iina",
        "tv.twitch.studio",
        "us.zoom.xos",
        "com.apple.podcasts",
        "com.apple.TV"
    ]

    private init() {
        refreshAudioDevices()
        refreshSystemVolume()
        refreshRunningAudioApps()

        let nc = NSWorkspace.shared.notificationCenter
        let launchObs = nc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshRunningAudioApps()
            }
        }
        let termObs = nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshRunningAudioApps()
            }
        }
        workspaceObservers = [launchObs, termObs]
    }

    func refreshAll() {
        refreshAudioDevices()
        refreshSystemVolume()
        refreshRunningAudioApps()
    }

    // MARK: - Master Volume & CoreAudio Device Name

    /// Điều chỉnh âm lượng tổng (Master Volume) của hệ thống macOS.
    /// - Parameter value: Mức âm lượng từ 0.0 (tắt tiếng) đến 1.0 (100%).
    func setMasterVolume(_ value: Double) {
        let clamped = min(1.0, max(0.0, value))
        masterVolume = clamped
        if clamped > 0 && isMasterMuted {
            isMasterMuted = false
        }
        let percent = Int((clamped * 100).rounded())
        runAppleScript("set volume output volume \(percent) without output muted")
    }

    /// Bật hoặc tắt trạng thái ngắt âm thanh (Mute) toàn hệ thống.
    func toggleMasterMute() {
        isMasterMuted.toggle()
        let muteStr = isMasterMuted ? "with output muted" : "without output muted"
        runAppleScript("set volume \(muteStr)")
    }

    /// Đọc mức âm lượng và trạng thái tắt tiếng hiện tại từ macOS.
    func refreshSystemVolume() {
        appleScriptQueue.async { [weak self] in
            let script = NSAppleScript(source: "return (output volume of (get volume settings) as string) & \",\" & (output muted of (get volume settings) as string)")
            var error: NSDictionary?
            guard let result = script?.executeAndReturnError(&error).stringValue else { return }
            let parts = result.split(separator: ",")
            guard parts.count == 2, let vol = Double(parts[0]) else { return }
            let muted = parts[1].trimmingCharacters(in: .whitespaces).lowercased() == "true"
            DispatchQueue.main.async {
                self?.masterVolume = min(1.0, max(0.0, vol / 100.0))
                self?.isMasterMuted = muted
            }
        }
    }

    func refreshAudioDevices() {
        if let outName = Self.defaultOutputDeviceName() {
            outputDeviceName = outName
        }
    }

    private static func defaultOutputDeviceName() -> String? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID) == noErr,
              deviceID != kAudioObjectUnknown else {
            return nil
        }

        var nameAddress = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var cfName: CFString = "" as CFString
        var nameSize = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &cfName) { ptr in
            AudioObjectGetPropertyData(deviceID, &nameAddress, 0, nil, &nameSize, ptr)
        }
        guard status == noErr else { return nil }
        let str = cfName as String
        return str.isEmpty ? nil : str
    }

    // MARK: - Per-App Volume Controls (0% - 200%)

    /// Quét danh sách các ứng dụng đa phương tiện đang chạy có hỗ trợ điều chỉnh âm lượng riêng.
    func refreshRunningAudioApps() {
        let running = NSWorkspace.shared.runningApplications.filter { app in
            guard app.activationPolicy == .regular, !app.isTerminated,
                  let bundleID = app.bundleIdentifier,
                  bundleID != Bundle.main.bundleIdentifier else { return false }
            return Self.knownAudioBundles.contains(bundleID)
                || bundleID == MusicService.shared.track?.bundleID
        }

        var result: [AudioAppEntry] = []
        var seenBundles = Set<String>()

        for app in running {
            guard let bundleID = app.bundleIdentifier, !seenBundles.contains(bundleID) else { continue }
            seenBundles.insert(bundleID)
            let name = app.localizedName ?? bundleID
            let icon = app.icon ?? NSWorkspace.shared.icon(forFile: app.bundleURL?.path ?? "")
            let vol = savedAppVolumes[bundleID] ?? 1.0
            let muted = savedAppMutes[bundleID] ?? false
            result.append(
                AudioAppEntry(
                    id: bundleID,
                    name: name,
                    bundleID: bundleID,
                    icon: icon,
                    volume: vol,
                    isMuted: muted
                )
            )
        }

        // Nếu chưa có ứng dụng media nào đang mở, hiển thị các ứng dụng tiêu biểu trên máy để người dùng điều chỉnh ngay
        if result.count < 3 {
            let fallbackBundles = [
                ("com.apple.Music", "Apple Music", "/System/Applications/Music.app"),
                ("com.apple.Safari", "Safari", "/Applications/Safari.app"),
                ("com.google.Chrome", "Google Chrome", "/Applications/Google Chrome.app")
            ]
            for (bundleID, name, path) in fallbackBundles where !seenBundles.contains(bundleID) {
                seenBundles.insert(bundleID)
                let icon = FileManager.default.fileExists(atPath: path)
                    ? NSWorkspace.shared.icon(forFile: path)
                    : (NSImage(systemSymbolName: "music.note.house.fill", accessibilityDescription: name) ?? NSImage())
                let vol = savedAppVolumes[bundleID] ?? 1.0
                let muted = savedAppMutes[bundleID] ?? false
                result.append(
                    AudioAppEntry(
                        id: bundleID,
                        name: name,
                        bundleID: bundleID,
                        icon: icon,
                        volume: vol,
                        isMuted: muted
                    )
                )
                if result.count >= 3 { break }
            }
        }

        apps = result
    }

    /// Điều chỉnh âm lượng độc lập cho một ứng dụng cụ thể.
    /// - Parameters:
    ///   - id: Bundle Identifier của ứng dụng (vd: `com.apple.Music`).
    ///   - volume: Mức âm lượng từ 0.0 đến 2.0 (hỗ trợ khuếch đại 200%).
    func setAppVolume(id: String, volume: Double) {
        let clamped = min(2.0, max(0.0, volume))
        savedAppVolumes[id] = clamped
        if clamped > 0 { savedAppMutes[id] = false }
        if let idx = apps.firstIndex(where: { $0.id == id }) {
            apps[idx].volume = clamped
            if clamped > 0 { apps[idx].isMuted = false }
            applyAppVolumeIfSupported(bundleID: apps[idx].bundleID, volume: clamped)
        }
    }

    /// Bật hoặc tắt trạng thái ngắt âm lượng riêng của ứng dụng.
    /// - Parameter id: Bundle Identifier của ứng dụng.
    func toggleAppMute(id: String) {
        guard let idx = apps.firstIndex(where: { $0.id == id }) else { return }
        let newMuted = !apps[idx].isMuted
        savedAppMutes[id] = newMuted
        apps[idx].isMuted = newMuted
        applyAppVolumeIfSupported(bundleID: apps[idx].bundleID, volume: newMuted ? 0 : apps[idx].volume)
    }

    private func applyAppVolumeIfSupported(bundleID: String, volume: Double) {
        let level = min(100, max(0, Int((volume * 100).rounded())))
        if bundleID == "com.apple.Music" {
            runAppleScript("if application \"Music\" is running then tell application \"Music\" to set sound volume to \(level)")
        } else if bundleID == "com.spotify.client" {
            runAppleScript("if application \"Spotify\" is running then tell application \"Spotify\" to set sound volume to \(level)")
        }
    }

    private func runAppleScript(_ source: String) {
        appleScriptQueue.async {
            var error: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&error)
        }
    }
}
