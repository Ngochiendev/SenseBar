import Foundation
import ApplicationServices
import ServiceManagement

enum DefaultsKey {
    static let language = "sensebar.language"
    static let hasOnboarded = "sensebar.hasOnboarded"
    static let onboardingStep = "sensebar.onboardingStep"
    static let selectedPopoverTab = "sensebar.popoverTab"

    // 2 tính năng chính của SenseBar
    static let pillarDynamicIslandEnabled = "sensebar.pillar.dynamicIsland"
    static let pillarAudioStudioEnabled = "sensebar.pillar.audioStudio"

    // Tùy chỉnh Dynamic Island
    static let notchStyle = "sensebar.notch.style" // "notch" hoặc "pill"
    static let notchDeviceNotices = "sensebar.notch.deviceNotices"
    static let notchLowPeripheralBattery = "sensebar.notch.lowPeripheralBattery"
    static let peripheralBatteryThreshold = "sensebar.notch.peripheralBatteryThreshold"
    static let peripheralBatteryLastPresented = "sensebar.notch.peripheralBatteryLastPresented"
    static let peripheralBatteryRecoveryComponents = "sensebar.notch.peripheralBatteryRecoveryComponents"
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

    // Thú cưng (Pet) — giữ nguyên chuỗi key để không mất cài đặt cũ của người dùng
    static let petEnabled = "sensebar.notch.mascotEnabled"
    static let petStyle = "sensebar.notch.mascotStyle" // "minimal" hoặc "robot"
    static let petShape = "sensebar.notch.mascotShape" // "ball", "squircle"
    static let petPalette = "sensebar.notch.mascotPalette" // "pearl", "lemon", "peach", "rose", "lilac", "sky", "mint"
    static let petSide = "sensebar.notch.mascotSide" // "left" hoặc "right"
    static let petVisits = "sensebar.notch.mascotVisits"
    static let petVisitFrequency = "sensebar.notch.mascotVisitFrequency" // "rare", "normal", "frequent"

    // Cập nhật phiên bản
    static let autoCheckUpdates = "sensebar.updates.autoCheck"
}

enum LaunchAtLoginManager {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Bản debug ngoài app bundle có thể chưa đăng ký được login item.
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
        guard AXIsProcessTrusted(), defaults.bool(forKey: DefaultsKey.hasOnboarded) else { return false }
        if defaults.object(forKey: defaultsKey) == nil { return true }
        return defaults.bool(forKey: defaultsKey)
    }

    func setEnabled(_ enabled: Bool, defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: defaultsKey)
    }
}
