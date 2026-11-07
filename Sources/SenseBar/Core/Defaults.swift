import Foundation

enum DefaultsKey {
    static let language = "sensebar.language"
    static let hasOnboarded = "sensebar.hasOnboarded"
    static let onboardingStep = "sensebar.onboardingStep"

    // 3 Trụ cột cốt lõi của SenseBar
    static let pillarDynamicIslandEnabled = "sensebar.pillar.dynamicIsland"
    static let pillarAudioStudioEnabled = "sensebar.pillar.audioStudio"
    static let pillarHardwareTelemetryEnabled = "sensebar.pillar.hardwareTelemetry"
}

enum SensePillar: String, CaseIterable, Identifiable {
    case dynamicIsland
    case audioStudio
    case hardwareTelemetry

    var id: String { rawValue }

    var defaultsKey: String {
        switch self {
        case .dynamicIsland: return DefaultsKey.pillarDynamicIslandEnabled
        case .audioStudio: return DefaultsKey.pillarAudioStudioEnabled
        case .hardwareTelemetry: return DefaultsKey.pillarHardwareTelemetryEnabled
        }
    }

    var icon: String {
        switch self {
        case .dynamicIsland: return "macbook"
        case .audioStudio: return "speaker.wave.2.fill"
        case .hardwareTelemetry: return "fanblades.fill"
        }
    }

    func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        if defaults.object(forKey: defaultsKey) == nil {
            return true
        }
        return defaults.bool(forKey: defaultsKey)
    }

    func setEnabled(_ enabled: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: defaultsKey)
    }
}

