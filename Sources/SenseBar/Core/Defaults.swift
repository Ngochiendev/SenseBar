import Foundation
import ServiceManagement

enum DefaultsKey {
    static let language = "sensebar.language"
    static let hasOnboarded = "sensebar.hasOnboarded"
    static let onboardingStep = "sensebar.onboardingStep"
    static let launchAtLogin = "sensebar.launchAtLogin"
    static let selectedPopoverTab = "sensebar.popoverTab"

    // 2 tính năng chính của SenseBar
    static let pillarDynamicIslandEnabled = "sensebar.pillar.dynamicIsland"
    static let pillarAudioStudioEnabled = "sensebar.pillar.audioStudio"

    // Tùy chỉnh Dynamic Island
    static let notchStyle = "sensebar.notch.style" // "notch" hoặc "pill"
    static let notchExpandOnHover = "sensebar.notch.expandOnHover"
    static let notchShowVisualizer = "sensebar.notch.showVisualizer"
    static let notchHideInFullscreen = "sensebar.notch.hideInFullscreen"
    static let notchDisplayTarget = "sensebar.notch.displayTarget" // automatic, builtIn, main, pointer, all
    static let notchExpandAllDisplays = "sensebar.notch.expandAllDisplays"
    static let notchCapsuleFitWidth = "sensebar.notch.capsuleFitWidth"
    static let notchCapsuleFitHeight = "sensebar.notch.capsuleFitHeight"
    static let notchCapsuleFitDrop = "sensebar.notch.capsuleFitDrop"

    // Liquid Glass (macOS 26+)
    static let liquidGlassEnabled = "sensebar.liquidGlassEnabled"
    static let liquidGlassIslandEnabled = "sensebar.liquidGlassIslandEnabled"
}

enum LaunchAtLoginManager {
    static var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return UserDefaults.standard.bool(forKey: DefaultsKey.launchAtLogin)
    }

    static func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: DefaultsKey.launchAtLogin)
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                // Khi chạy bản debug ngoài /Applications, vẫn lưu trạng thái vào UserDefaults
            }
        }
    }
}

enum SensePillar: String, CaseIterable, Identifiable {
    case dynamicIsland
    case audioStudio

    var id: String { rawValue }

    var defaultsKey: String {
        switch self {
        case .dynamicIsland: return DefaultsKey.pillarDynamicIslandEnabled
        case .audioStudio:   return DefaultsKey.pillarAudioStudioEnabled
        }
    }

    func isEnabled(_ defaults: UserDefaults = .standard) -> Bool {
        if defaults.object(forKey: defaultsKey) == nil { return true }
        return defaults.bool(forKey: defaultsKey)
    }

    func setEnabled(_ enabled: Bool, defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: defaultsKey)
    }
}
