import AppKit
import Foundation
import Sparkle

MainActor.assumeIsolated {
    if CommandLine.arguments.contains("--selftest") {
        precondition(MusicService.cleanMediaTitle("TỔNG HỢP NHẠC DRILL - YouTube") == "TỔNG HỢP NHẠC DRILL")
        precondition(MusicService.cleanMediaTitle("(1) Bài hát mới – YouTube") == "Bài hát mới")
        precondition(MusicService.cleanMediaTitle("Song - YouTube remix") == "Song - YouTube remix")
        precondition(BrowserArtworkService.videoID(from: URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")!) == "dQw4w9WgXcQ")
        precondition(BrowserArtworkService.videoID(from: URL(string: "https://example.com/watch?v=dQw4w9WgXcQ")!) == nil)
        let sessionBlock = Data([0x6d, 0x6f, 0x7a, 0x4c, 0x7a, 0x34, 0x30, 0, 2, 0, 0, 0, 0x20, 0x7b, 0x7d])
        precondition(BrowserArtworkService.decodeSession(sessionBlock) == Data("{}".utf8),
                     "Mozilla session must decode the size-prefixed raw LZ4 block")
        precondition(BrowserArtworkService.decodeSession(sessionBlock.dropLast()) == nil,
                     "Truncated sessions must not produce partial metadata")
        precondition(MusicService.validatePlaybackParser(), "MusicService parser must cleanly parse playback sessions")
        let menuIcon = BrandIconResources.menuBarTemplateImage()
        assert(menuIcon.isTemplate, "MenuBarIcon must be a template image")
        assert(menuIcon.size == NSSize(width: 26, height: 20), "MenuBarIcon size must be 26x20")
        assert(L10n.shared.language == .vi || L10n.shared.language == .en, "Supported language check")
        assert(SensePillar.allCases.count == 2, "SenseBar must have exactly 2 core pillars")
        assert(PopoverMode.allCases.count == 2, "Menu Bar Popover must have Dynamic Island & Audio tabs")
        assert(UpdateService.isNewerVersion("v1.10.0", than: "1.9.2"), "Semantic version check failed")
        assert(!UpdateService.isNewerVersion("v1.1.2", than: "1.1.2"), "Equal version should not be newer")
        let noUpdate = NSError(domain: SUSparkleErrorDomain, code: Int(SUError.noUpdateError.rawValue))
        precondition(UpdateService.statusAfterUpdateError(noUpdate) == .upToDate,
                     "A successful no-update check must not become a connection failure")
        let networkFailure = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        precondition(UpdateService.statusAfterUpdateError(networkFailure) == .failed,
                     "Network failures must remain failures")
        let canceledUpdate = NSError(domain: SUSparkleErrorDomain, code: Int(SUError.installationCanceledError.rawValue))
        precondition(UpdateService.statusAfterUpdateError(canceledUpdate) == .idle,
                     "Canceling an update must not become a connection failure")
#if DEBUG
        let fixtureNotes = "<html><head><meta name=\"sensebar-version\" content=\"1.3.1\"></head><body><h2>Sửa lỗi</h2><ul><li>Nội dung kiểm thử.</li></ul></body></html>"
        let fixtureData = try! JSONEncoder().encode(["1.3.1": fixtureNotes, "1.3.0": "# SenseBar 1.3.0\n"])
        let decodedNotes = try! SenseBarUpdateUserDriver.previewNotes(version: "1.3.1", data: fixtureData)
        let updatePreview = try! SenseBarUpdateUserDriver.previewFixture(version: "1.3.1", releaseNotes: decodedNotes)
        precondition(updatePreview.0.itemDescription == fixtureNotes && updatePreview.0.itemDescriptionFormat == "html",
                     "Sparkle preview must display exactly the styled HTML generated for production")
        do {
            _ = try SenseBarUpdateUserDriver.previewNotes(version: "9.9.9", data: fixtureData)
            preconditionFailure("Missing preview notes must fail instead of showing sample content")
        } catch {}
        precondition(updatePreview.0.displayVersionString == "1.3.1")
        precondition(updatePreview.0.fileURL?.host == "preview.invalid")
        precondition(updatePreview.1.stage == .notDownloaded && updatePreview.1.userInitiated,
                     "Preview must show the pre-download update prompt")
#endif
        precondition(AudioTapEngine.validateRender(), "Audio render: boost ceiling, stereo, mute or unity failed")
        let batteryFixture = Data(#"{"SPBluetoothDataType":[{"device_connected":[{"My AirPods":{"device_address":"AA-BB-CC-DD-EE-FF","device_batteryLevelLeft":"73%","device_batteryLevelRight":64,"device_batteryLevelCase":"101%"}},{"Other mouse":{"device_address":"11-22-33-44-55-66","device_batteryLevelMain":"40%"}}]}]}"#.utf8)
        let battery = DeviceConnectionMonitor.battery(in: batteryFixture, address: "aa:bb:cc:dd:ee:ff")
        precondition(battery?.left == 73 && battery?.right == 64 && battery?.casePercent == nil
            && battery?.percent == nil, "Component batteries must stay separate and reject invalid levels")
        precondition(DeviceConnectionMonitor.battery(in: batteryFixture, address: "00:00:00:00:00:00") == nil,
                     "Never attribute a different device's battery by its display name")
        precondition(DeviceConnectionMonitor.battery(in: Data(), address: "aa:bb:cc:dd:ee:ff") == nil,
                     "Missing telemetry must remain unknown")
        var lowBattery = PeripheralLowBatteryPolicy()
        precondition(lowBattery.consume(id: "mouse", reading: DeviceBatteryReading(percent: 45)) == nil)
        precondition(lowBattery.consume(id: "mouse", reading: DeviceBatteryReading(percent: 20)) == 20)
        precondition(lowBattery.consume(id: "mouse", reading: DeviceBatteryReading(percent: 19)) == nil,
                     "A low battery must not repeat on every sample or reconnect")
        precondition(lowBattery.consume(id: "mouse", reading: DeviceBatteryReading()) == nil)
        precondition(lowBattery.consume(id: "mouse", reading: DeviceBatteryReading(percent: 10)) == 10)
        precondition(lowBattery.consume(id: "mouse", reading: DeviceBatteryReading(percent: 22)) == nil)
        precondition(lowBattery.consume(id: "mouse", reading: DeviceBatteryReading(percent: 19)) == nil,
                     "Readings near the threshold must not re-arm a low episode")
        precondition(lowBattery.consume(id: "mouse", reading: DeviceBatteryReading(percent: 25)) == nil)
        precondition(lowBattery.consume(id: "mouse", reading: DeviceBatteryReading(percent: 20)) == 20)
        precondition(lowBattery.consume(id: "airpods", reading: DeviceBatteryReading(left: 75, right: 8)) == 8)
        precondition(HIDPeripheralMonitor.address("AA:BB:CC:DD:EE:FF") == "aa-bb-cc-dd-ee-ff")
        precondition(HIDPeripheralMonitor.address("keyboard-serial") == nil)
        var routes = AudioAccessoryTransitions()
        precondition(routes.consume(available: ["airpods"], selected: nil).isEmpty,
                     "Already-connected devices must not announce at startup")
        precondition(routes.consume(available: ["airpods"], selected: "airpods") == ["airpods"],
                     "AirPods activation must announce even when the Bluetooth link stayed alive")
        precondition(routes.consume(available: ["airpods"], selected: "airpods").isEmpty,
                     "Repeated output snapshots must not repeat the notification")
        precondition(routes.consume(available: [], selected: nil).isEmpty)
        precondition(routes.consume(available: ["airpods"], selected: "airpods") == ["airpods"],
                     "Reconnect must re-arm after the output disappears")
        let chrome = BrowserPlaybackActivity(bundleID: "com.google.Chrome", appName: "Google Chrome", pid: 123)
        let autoplay = MediaPlaybackPolicy.resolve(title: "", bundleID: "", appName: "", pid: 0,
            isPlaying: false, browsers: [chrome])
        precondition(autoplay?.isPlaying == true && autoplay?.title == "Google Chrome"
                     && autoplay?.usesRemoteMetadata == false,
                     "Autoplay with no Media Session must still show browser output")
        let matchingAutoplay = MediaPlaybackPolicy.resolve(title: "", bundleID: chrome.bundleID,
            appName: chrome.appName, pid: chrome.pid, isPlaying: false, browsers: [chrome])
        precondition(matchingAutoplay?.isPlaying == true && matchingAutoplay?.usesRemoteMetadata == false,
                     "Browser output with an empty media session must remain visible")
        let reels = MediaPlaybackPolicy.resolve(title: "Facebook", bundleID: chrome.bundleID,
            appName: chrome.appName, pid: chrome.pid, isPlaying: false, browsers: [chrome])
        precondition(reels?.isPlaying == false && reels?.usesRemoteMetadata == true && reels?.title == "Facebook",
                     "A lingering Chrome output stream must preserve the paused recording")
        let youtube = MediaPlaybackPolicy.resolve(title: "Video A", bundleID: chrome.bundleID,
            appName: chrome.appName, pid: chrome.pid, isPlaying: true, browsers: [chrome])
        precondition(youtube?.title == "Video A" && youtube?.usesRemoteMetadata == true && youtube?.isPlaying == true,
                     "YouTube must preserve valid metadata and transport controls")
        let paused = MediaPlaybackPolicy.resolve(title: "Video A", bundleID: chrome.bundleID,
            appName: chrome.appName, pid: chrome.pid, isPlaying: false, browsers: [])
        precondition(paused?.isPlaying == false, "Paused media with no browser output must stay paused")
        let pinnedMissing = MediaPlaybackPolicy.resolve(title: "", bundleID: "", appName: "", pid: 0,
            isPlaying: false, browsers: [chrome], preferredSource: "com.spotify.client")
        precondition(pinnedMissing == nil, "An unavailable pinned player must not show another app")
        let pinnedSpotify = MediaPlaybackPolicy.resolve(title: "Song B", bundleID: "com.spotify.client",
            appName: "Spotify", pid: 456, isPlaying: false, browsers: [chrome], preferredSource: "com.spotify.client")
        precondition(pinnedSpotify?.bundleID == "com.spotify.client" && pinnedSpotify?.isPlaying == false
                     && pinnedSpotify?.usesRemoteMetadata == true, "A pinned paused song must retain its metadata")
        let qobuz = AudioOutputActivity(bundleID: "com.qobuz.desktop", appName: "Qobuz", pid: 789)
        let pinnedAudioOnly = MediaPlaybackPolicy.resolve(title: "", bundleID: "", appName: "", pid: 0,
            isPlaying: false, browsers: [], audioOutputs: [qobuz], preferredSource: qobuz.bundleID)
        precondition(pinnedAudioOnly?.title == "Qobuz" && pinnedAudioOnly?.usesRemoteMetadata == false,
                     "A pinned audio-only app must expose only its application identity")
        let ambiguousAudio = MediaPlaybackPolicy.resolve(title: "", bundleID: "", appName: "", pid: 0,
            isPlaying: false, browsers: [], audioOutputs: [qobuz,
                AudioOutputActivity(bundleID: "io.mpv", appName: "mpv", pid: 790)])
        precondition(ambiguousAudio == nil, "Automatic selection must not guess between audio-only apps")
        precondition(MediaPlaybackPolicy.resolve(title: "", bundleID: "", appName: "", pid: 0,
            isPlaying: false, browsers: []) == nil, "Closed players must not leave a phantom track")
        let spotify = MediaPlaybackPolicy.resolve(title: "Song B", bundleID: "com.spotify.client",
            appName: "Spotify", pid: 456, isPlaying: true, browsers: [chrome])
        precondition(spotify?.title == "Song B" && spotify?.bundleID == "com.spotify.client",
                     "Browser fallback must not replace a valid playing music app")
        precondition(PetEngine.idleMood(systemIdle: 900, sinceReset: 900, isMediaPlaying: true) == .idle,
                     "Watching a long video must never trigger the idle timer's sleeping pet")
        precondition(PetEngine.idleMood(systemIdle: 900, sinceReset: 0, isMediaPlaying: false) == .idle,
                     "Pausing media must start a fresh idle period, not sleep immediately")
        precondition(PetEngine.idleMood(systemIdle: 300, sinceReset: 300, isMediaPlaying: false) == .sleeping)
        precondition(PetEngine.idleMood(systemIdle: 1, sinceReset: 900, isMediaPlaying: false) == .idle,
                     "Mouse or keyboard activity must wake the idle policy")
        print("SELFTEST OK")
        exit(0)
    }

    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
