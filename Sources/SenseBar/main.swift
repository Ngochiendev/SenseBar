import AppKit
import Foundation

if CommandLine.arguments.contains("--selftest") {
    let menuIcon = BrandIconResources.menuBarTemplateImage()
    assert(menuIcon.isTemplate, "MenuBarIcon must be a template image")
    assert(menuIcon.size == NSSize(width: 26, height: 20), "MenuBarIcon size must be 26x20")
    assert(L10n.shared.language == .vi || L10n.shared.language == .en, "Supported language check")
    assert(SensePillar.allCases.count == 3, "SenseBar must have exactly 3 core pillars")
    print("SELFTEST OK")
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()

