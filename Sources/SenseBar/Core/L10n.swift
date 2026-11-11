import Combine
import Foundation

/// Ngôn ngữ hiển thị của SenseBar, mặc định là Tiếng Việt.
enum AppLanguage: String, CaseIterable, Identifiable {
    case vi = "vi"
    case en = "en"

    var id: String { rawValue }
}

struct SenseStrings {
    // Menu Bar & App
    var menuBarTooltip: String
    var menuOpenPanel: String
    var menuSettings: String
    var menuAbout: String
    var menuQuit: String

    // 2 Core Features
    var pillar1Title: String
    var pillar1Subtitle: String

    var pillar2Title: String
    var pillar2Subtitle: String

    // Cài đặt (Settings)
    var settingsLaunchAtLogin: String
    var settingsLaunchAtLoginDesc: String

    static let vi = SenseStrings(
        menuBarTooltip: "SenseBar — Đang hoạt động",
        menuOpenPanel: "Mở bảng điều khiển SenseBar",
        menuSettings: "Cài đặt SenseBar…",
        menuAbout: "Giới thiệu SenseBar",
        menuQuit: "Thoát SenseBar",

        pillar1Title: "Tai thỏ & Dynamic Island",
        pillar1Subtitle: "Biến phần tai thỏ MacBook thành khu vực điều khiển nhạc trực quan: hiển thị ảnh bìa, sóng nhạc theo màu đĩa và điều khiển phát nhạc mượt mà.",

        pillar2Title: "Bộ trộn âm thanh (Audio Studio)",
        pillar2Subtitle: "Chỉnh âm lượng loa tổng và điều chỉnh âm lượng độc lập cho từng ứng dụng đang chạy (0% – 200%).",

        settingsLaunchAtLogin: "Khởi động cùng macOS",
        settingsLaunchAtLoginDesc: "Tự động chạy SenseBar trên thanh Menu Bar khi bạn đăng nhập vào máy Mac."
    )

    static let en = SenseStrings(
        menuBarTooltip: "SenseBar — Active",
        menuOpenPanel: "Open SenseBar Panel",
        menuSettings: "SenseBar Settings…",
        menuAbout: "About SenseBar",
        menuQuit: "Quit SenseBar",

        pillar1Title: "Dynamic Island & Notch",
        pillar1Subtitle: "Turn your MacBook notch into an interactive music studio with album artwork, colored audio visualizer, and smooth playback controls.",

        pillar2Title: "Audio Studio & Volume Mixer",
        pillar2Subtitle: "Control master speaker volume and adjust individual app volumes (0% – 200%) independently.",

        settingsLaunchAtLogin: "Launch at Login",
        settingsLaunchAtLoginDesc: "Automatically start SenseBar in the Menu Bar when you log into your Mac."
    )
}

@MainActor
final class L10n: ObservableObject {
    static let shared = L10n()

    @Published var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: DefaultsKey.language)
        }
    }

    var s: SenseStrings {
        switch language {
        case .vi: return .vi
        case .en: return .en
        }
    }

    func string(vi: String, en: String) -> String {
        switch language {
        case .vi: return vi
        case .en: return en
        }
    }

    private init() {
        UserDefaults.standard.register(defaults: [DefaultsKey.language: AppLanguage.vi.rawValue])
        if let raw = UserDefaults.standard.string(forKey: DefaultsKey.language),
           let saved = AppLanguage(rawValue: raw) {
            language = saved
        } else {
            language = .vi
        }
    }
}
