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
        print("SELFTEST OK")
        exit(0)
    }

    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
