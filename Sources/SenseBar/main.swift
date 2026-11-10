import AppKit
import Foundation

MainActor.assumeIsolated {
    if CommandLine.arguments.contains("--selftest") {
        let menuIcon = BrandIconResources.menuBarTemplateImage()
        assert(menuIcon.isTemplate, "MenuBarIcon must be a template image")
        assert(menuIcon.size == NSSize(width: 26, height: 20), "MenuBarIcon size must be 26x20")
        assert(L10n.shared.language == .vi || L10n.shared.language == .en, "Supported language check")
        assert(SensePillar.allCases.count == 2, "SenseBar must have exactly 2 core pillars")
        assert(PopoverMode.allCases.count == 2, "Menu Bar Popover must have Dynamic Island & Audio tabs")
        assert(UpdateService.isNewerVersion("v1.10.0", than: "1.9.2"), "Semantic version check failed")
        assert(!UpdateService.isNewerVersion("v1.1.2", than: "1.1.2"), "Equal version should not be newer")
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
        print("SELFTEST OK")
        exit(0)
    }

    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
