import AppKit
import Foundation
import CoreAudio
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
        precondition(lowBattery.candidate(reading: DeviceBatteryReading(percent: 20), threshold: 20) == .main)
        precondition(lowBattery.candidate(reading: DeviceBatteryReading(percent: 21), threshold: 20) == nil)
        precondition(lowBattery.candidate(reading: DeviceBatteryReading(percent: 0), threshold: 20) == .main)
        precondition(lowBattery.candidate(reading: DeviceBatteryReading(percent: 8, charging: true), threshold: 20) == nil)
        precondition(lowBattery.candidate(reading: DeviceBatteryReading(left: 8, right: 90, casePercent: 5,
            leftCharging: true, caseCharging: false), threshold: 20) == .batteryCase,
            "A charging earbud must not suppress an empty case")
        precondition(lowBattery.candidate(reading: DeviceBatteryReading(percent: 5, left: 75, right: 80,
            charging: false), threshold: 20) == nil, "Aggregate levels must not override known component levels")
        let noticeTime = Date(timeIntervalSince1970: 1_700_000_000)
        precondition(lowBattery.canPresent(id: "mouse"))
        precondition(lowBattery.canPresent(id: "mouse"), "Queued notices must not consume the episode")
        lowBattery.recordPresentation(id: "mouse", reading: .init(percent: 20), now: noticeTime)
        var restoredBatteryPolicy = PeripheralLowBatteryPolicy(lastPresented: lowBattery.lastPresented,
            recoveryComponents: lowBattery.recoveryComponents)
        precondition(!restoredBatteryPolicy.canPresent(id: "mouse"), "Restart must preserve a low episode")
        precondition(restoredBatteryPolicy.canPresent(id: "keyboard"), "Episodes are per device")
        let savedBatteryHistory = try! PropertyListSerialization.data(fromPropertyList: lowBattery.lastPresented,
            format: .binary, options: 0)
        let restoredHistory = try! PropertyListSerialization.propertyList(from: savedBatteryHistory,
            options: [], format: nil) as! [String: Date]
        precondition(!PeripheralLowBatteryPolicy(lastPresented: restoredHistory).canPresent(id: "mouse"),
                     "The presentation history must survive property-list persistence")
        for reading in [DeviceBatteryReading(), .init(percent: 20), .init(percent: 19),
                        .init(percent: 20, charging: true), .init(percent: 29)] {
            precondition(!restoredBatteryPolicy.observeRecovery(id: "mouse", reading: reading, threshold: 20))
            precondition(!restoredBatteryPolicy.canPresent(id: "mouse"),
                         "Missing data, brief charging or near-threshold jitter must not re-arm an episode")
        }
        precondition(restoredBatteryPolicy.observeRecovery(id: "mouse", reading: .init(percent: 30), threshold: 20))
        precondition(restoredBatteryPolicy.canPresent(id: "mouse"), "Recovery must re-arm without waiting 24 hours")
        precondition(restoredBatteryPolicy.candidate(reading: .init(percent: 20), threshold: 20) == .main)
        restoredBatteryPolicy.recordPresentation(id: "airpods", reading: .init(left: 8, casePercent: 5))
        precondition(!restoredBatteryPolicy.observeRecovery(id: "airpods", reading: .init(left: 80), threshold: 20),
                     "An absent case reading cannot prove case recovery")
        precondition(!restoredBatteryPolicy.observeRecovery(id: "airpods", reading: .init(left: 80, casePercent: 5), threshold: 20))
        precondition(restoredBatteryPolicy.observeRecovery(id: "airpods", reading: .init(left: 80, casePercent: 30), threshold: 20))
        var earbudEpisode = PeripheralLowBatteryPolicy()
        earbudEpisode.recordPresentation(id: "buds", reading: .init(left: 10, right: 80, casePercent: 25))
        precondition(earbudEpisode.observeRecovery(id: "buds", reading: .init(left: 30, right: 80, casePercent: 25), threshold: 20),
                     "A healthy sibling battery must not prevent a low earbud's recovery")
        earbudEpisode.recordPresentation(id: "buds", reading: .init(left: 10, right: 80), threshold: 15)
        let episodeData = try! PropertyListEncoder().encode(earbudEpisode.persistentHistory)
        var decodedEpisode = try! PropertyListDecoder().decode(PeripheralLowBatteryPolicy.self, from: episodeData)
        precondition(!decodedEpisode.canPresent(id: "buds"))
        precondition(!decodedEpisode.observeRecovery(id: "buds", reading: .init(left: 24), threshold: 15))
        precondition(decodedEpisode.observeRecovery(id: "buds", reading: .init(left: 25), threshold: 15))
        precondition(AudioOutputKind.classify(name: "Renamed monitor", transport: kAudioDeviceTransportTypeHDMI,
            terminal: 0) == .display)
        precondition(AudioOutputKind.classify(name: "Renamed headset", transport: kAudioDeviceTransportTypeBuiltIn,
            terminal: kAudioStreamTerminalTypeHeadphones) == .headphones)
        precondition(AudioOutputKind.classify(name: "Interface", transport: kAudioDeviceTransportTypeUSB,
            terminal: 0) == .usb)
        precondition(AudioOutputKind.classify(name: "AirPods Pro", transport: kAudioDeviceTransportTypeVirtual,
            terminal: 0) == .virtual, "Native transport must beat a misleading display name")
        precondition(AudioOutputKind.classify(name: "AirPods Max", transport: kAudioDeviceTransportTypeBluetooth,
            terminal: 0) == .airPodsMax)
        precondition(Set(AudioOutputKind.allCases.map(\.symbol)).count == AudioOutputKind.allCases.count,
                     "Each output category must have its own icon")
        for kind in AudioOutputKind.allCases {
            precondition(NSImage(systemSymbolName: kind.symbol, accessibilityDescription: nil) != nil,
                         "Output symbols must exist on this macOS version")
        }
        let accessoryFixture: [[String: Any]] = [
            ["Type": "Accessory Source", "Group Identifier": "AA:BB:CC:DD:EE:FF", "Part Identifier": "Left",
             "Current Capacity": 8, "Max Capacity": 100, "Is Charging": true],
            ["Type": "Accessory Source", "Group Identifier": "AA:BB:CC:DD:EE:FF", "Part Identifier": "Case",
             "Current Capacity": 0, "Max Capacity": 100, "Is Charging": false]
        ]
        let accessoryBattery = AccessoryPowerSourceReader.battery(in: accessoryFixture, address: "aa-bb-cc-dd-ee-ff")
        precondition(accessoryBattery?.left == 8 && accessoryBattery?.leftCharging == true
            && accessoryBattery?.casePercent == 0 && accessoryBattery?.caseCharging == false)
        precondition(AccessoryPowerSourceReader.battery(in: accessoryFixture, address: "11-22-33-44-55-66") == nil)
        precondition(AccessoryPowerSourceReader.battery(in: [accessoryFixture[0], accessoryFixture[0]],
            address: "aa-bb-cc-dd-ee-ff") == nil, "Ambiguous parts must remain unknown")
        var missingIdentity = accessoryFixture[0]
        missingIdentity.removeValue(forKey: "Group Identifier")
        missingIdentity["Name"] = "AA:BB:CC:DD:EE:FF"
        precondition(AccessoryPowerSourceReader.battery(in: [missingIdentity], address: "aa-bb-cc-dd-ee-ff") == nil,
                     "Display names must never act as Bluetooth identities")
        let fixtureUUID = "8E9C0308-B63A-4212-BA4A-F053C46017DC"
        var uuidSource = accessoryFixture[0]
        uuidSource["Group Identifier"] = fixtureUUID
        precondition(AccessoryPowerSourceReader.battery(in: [uuidSource], address: "aa-bb-cc-dd-ee-ff") == nil)
        precondition(AccessoryPowerSourceReader.battery(in: [uuidSource], address: "aa-bb-cc-dd-ee-ff",
            identifier: fixtureUUID.lowercased())?.leftCharging == true,
            "Power-source UUIDs must match the exact native device UUID")
        precondition(DeviceBatteryReading.hid(["BatteryPercent": true]) == nil)
        precondition(DeviceBatteryReading.hid(["BatteryPercent": 10])?.charging == nil)
        precondition(DeviceBatteryReading.hid(["BatteryPercent": 10, "IsCharging": 2])?.charging == nil)
        precondition(DeviceBatteryReading(percent: 50).fillingMissing(from: DeviceBatteryReading(left: 12)).left == 12)
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
        let display = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let desktopWindow = FullscreenDetector.Surface(owner: 10, frame: display.insetBy(dx: 0, dy: 24), level: 0)
        let movieWindow = FullscreenDetector.Surface(owner: 20, frame: display, level: 0)
        precondition(!FullscreenDetector.isFullscreen(surfaces: [desktopWindow, movieWindow], display: display,
                                                       activePID: 10, axFullscreen: false),
                     "A background fullscreen window must not hide the island over a foreground desktop window")
        precondition(FullscreenDetector.isFullscreen(surfaces: [movieWindow], display: display,
                                                      activePID: 20, axFullscreen: false),
                     "Borderless video must be detected without relying on Accessibility")
        precondition(!FullscreenDetector.isFullscreen(surfaces: [movieWindow], display: display.offsetBy(dx: 1920, dy: 0),
                                                       activePID: 20, axFullscreen: true),
                     "Fullscreen on another monitor must not hide this monitor's island")
        precondition(CrossPetCharacter.presentationReaction(event: nil, mediaPlaying: true) == .groove,
                     "Playing media must select the listening pose")
        precondition(CrossPetCharacter.presentationReaction(event: nil, mediaPlaying: false) == nil,
                     "Pausing media must return to the normal idle pose")
        precondition(CrossPetCharacter.presentationReaction(event: .love, mediaPlaying: true) == .love,
                     "A charging or petting reaction must take priority over music")
        for character in CrossPetCharacter.allCases {
            precondition(character.pose(mood: .idle, reaction: nil, compact: true) == "roll_call",
                         "Compact CrossPet must greet while idle")
            precondition(character.pose(mood: .sleeping, reaction: nil, compact: true).hasPrefix("sleeping"),
                         "Sleep must take priority over the default greeting")
            for pose in character.bundledPoses {
                for head in [true, false] {
                    guard let image = CrossPetArtwork.image(character, pose: pose, head: head) else {
                        preconditionFailure("Bundled CrossPet artwork must decode: \(character.rawValue)/\(pose), head=\(head)")
                    }
                    if head {
                        for side in PetSide.allCases {
                            for floats in [true, false] {
                                var track = PetEngine.track(stripWidth: 240, stripHeight: 32, wing: 46,
                                                            cameraWidth: 148, floats: floats, bodyHeight: 26, side: side)
                                if floats { track.rest = side == .left ? 16 : 224 }
                                let frame = CrossPetLayout.compactFrame(image: CGSize(width: image.width, height: image.height),
                                                                        track: track, rests: true)
                                precondition(abs(frame.maxY - track.height) < 0.001,
                                             "Every CrossPet avatar must share the bottom baseline")
                                precondition(frame.minY >= track.ceiling && frame.minX >= 0 && frame.maxX <= track.width,
                                             "CrossPet must fit inside both compact display styles")
                                precondition(abs(frame.width / frame.height - CGFloat(image.width) / CGFloat(image.height)) < 0.001,
                                             "Compact artwork must preserve its aspect ratio without letterboxing")
                                if floats {
                                    let rounded = CGPath(roundedRect: CGRect(x: 0, y: 0, width: track.width, height: track.height),
                                                         cornerWidth: track.height / 2, cornerHeight: track.height / 2, transform: nil)
                                    precondition(rounded.contains(CGPoint(x: frame.minX, y: frame.maxY - 0.001)) &&
                                                 rounded.contains(CGPoint(x: frame.maxX, y: frame.maxY - 0.001)),
                                                 "Capsule corners must not cut off the avatar's bottom edge")
                                }
                                if let camera = track.hidden {
                                    precondition(frame.maxX <= camera.lowerBound || frame.minX >= camera.upperBound,
                                                 "Resting avatars must not cross the camera cutout")
                                }
                            }
                        }
                    }
                }
            }
        }
        for character in CrossPetCharacter.allCases {
            let track = PetEngine.track(stripWidth: 240, stripHeight: 32, wing: 46, cameraWidth: 148,
                                        floats: false, bodyHeight: 32)
            let host = CrossPetHostView(frame: CGRect(x: 0, y: 0, width: 240, height: 32))
            host.update(character: character, mood: .idle, reaction: nil, head: true,
                        track: track, rests: true)
            host.layoutSubtreeIfNeeded()
            guard let sprite = host.layer?.sublayers?.first else { preconditionFailure("Missing CrossPet image layer") }
            precondition(sprite.anchorPoint.y == 1 && abs(sprite.position.y - track.height) < 0.001,
                         "CrossPet must remain attached to the island bottom edge")
            precondition(sprite.animation(forKey: "bodyMotion") == nil,
                         "CrossPet artwork must not squash or rotate as a whole image")
            precondition(character.pose(mood: .happy, reaction: .groove) == "hum",
                         "Music reaction must select the dancing artwork")
            precondition(character.pose(mood: .downloadError, reaction: .confused) == "oops",
                         "A failed download must select its own error artwork")
        }
        for character in CrossPetCharacter.allCases {
            for head in [false, true] {
                let host = CrossPetHostView(frame: CGRect(x: 0, y: 0, width: 56, height: 68))
                var stableFrame: CGRect?
                let expressions: [(PetMood, PetReaction?)] = [(.idle, nil), (.idle, .groove), (.sleeping, nil),
                                                            (.idle, .wakeUp), (.idle, .love), (.idle, nil)]
                for (mood, reaction) in expressions {
                    host.update(character: character, mood: mood, reaction: reaction, head: head,
                                track: nil, rests: true)
                    host.layoutSubtreeIfNeeded()
                    guard let imageLayer = host.layer?.sublayers?.first else {
                        preconditionFailure("Missing registered character layer")
                    }
                    precondition(imageLayer.contents != nil && (imageLayer.sublayers ?? []).isEmpty,
                                 "Every expression must render as one complete image")
                    if let stableFrame { precondition(imageLayer.frame == stableFrame,
                                                      "All character expressions must share a fixed display frame") }
                    else { stableFrame = imageLayer.frame }
                    precondition((imageLayer.animationKeys() ?? []).isEmpty,
                                 "Static CrossPet artwork must not install animations")
                }
            }
            for pose in character.bundledPoses {
                for head in [true, false] {
                    let registered = CrossPetArtwork.image(character, pose: pose, head: head)!
                    precondition(registered.width == (head ? 256 : 320) && registered.height == registered.width,
                                 "Every source pose must register onto the same canvas")
                }
            }
        }
        if Bundle.main.bundleURL.pathExtension == "app", let resources = Bundle.main.resourceURL {
            let packagedPath = CrossPetArtwork.resourceBundle.bundleURL.resolvingSymlinksInPath().standardizedFileURL.path
            let expectedPath = resources.appendingPathComponent("SenseBar_SenseBar.bundle")
                .resolvingSymlinksInPath().standardizedFileURL.path
            precondition(packagedPath == expectedPath,
                         "A packaged app must load CrossPet from its own resources, not the developer build folder")
        }
        print("SELFTEST OK")
        exit(0)
    }

    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
