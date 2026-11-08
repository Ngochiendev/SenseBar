import Combine
import Foundation

/// Ngôn ngữ hiển thị của SenseBar. Mặc định dùng Tiếng Việt (.vi),
/// sẵn sàng hỗ trợ Tiếng Anh (.en) trong tương lai.
enum AppLanguage: String, CaseIterable, Identifiable {
    case vi = "vi"
    case en = "en"

    var id: String { rawValue }
}

struct SenseStrings {
    // Menu Bar & App
    var menuBarTooltip: String
    var menuOpenPanel: String
    var menuShowWelcome: String
    var menuSettings: String
    var menuAbout: String
    var menuQuit: String

    // Onboarding Step 1: Welcome
    var welcomeTitle: String
    var welcomeSubtitle: String

    // 2 Core Features
    var pillar1Title: String
    var pillar1Subtitle: String
    var pillar1Tags: [String]

    var pillar2Title: String
    var pillar2Subtitle: String
    var pillar2Tags: [String]

    // Onboarding Step 2: Features Selection
    var purposeTitle: String
    var purposeSubtitle: String
    var purposeActiveCountFormat: String

    // Onboarding Step 3: Permissions
    var permissionsTitle: String
    var permissionsSubtitle: String
    var permNote: String

    // Onboarding Step 4: Done
    var doneTitle: String
    var doneSubtitle: String
    var doneMenuBarHint: String
    var doneActivePillarsTitle: String

    // Navigation Buttons
    var btnBack: String
    var btnContinue: String
    var btnStart: String

    // Cửa sổ Cài đặt (Settings Window)
    var settingsWindowTitle: String
    var settingsTabGeneral: String
    var settingsTabPermissions: String
    var settingsTabAbout: String
    var settingsStartupSection: String
    var settingsLaunchAtLogin: String
    var settingsLaunchAtLoginDesc: String
    var settingsFeaturesSection: String
    var settingsOnboardingSection: String
    var settingsReopenWelcomeDesc: String
    var aboutSubtitle: String
    var aboutVersionFormat: String
    var aboutLicenseBadge: String
    var aboutOpenGitHub: String

    static let vi = SenseStrings(
        menuBarTooltip: "SenseBar — Đang hoạt động",
        menuOpenPanel: "Mở bảng điều khiển SenseBar",
        menuShowWelcome: "Mở màn hình Chào mừng…",
        menuSettings: "Cài đặt SenseBar…",
        menuAbout: "Giới thiệu SenseBar",
        menuQuit: "Thoát SenseBar",

        welcomeTitle: "SenseBar",
        welcomeSubtitle: "Tiện ích thanh Menu Bar gọn nhẹ cho macOS — Tích hợp Tai thỏ & Dynamic Island trình phát nhạc cùng Bộ trộn âm lượng riêng cho từng ứng dụng.",

        pillar1Title: "Tai thỏ & Dynamic Island",
        pillar1Subtitle: "Biến phần tai thỏ MacBook thành khu vực điều khiển nhạc trực quan: hiển thị ảnh bìa, sóng nhạc theo màu đĩa và điều khiển phát nhạc mượt mà.",
        pillar1Tags: ["Trình phát nhạc", "Sóng nhạc", "Ôm sát tai thỏ", "Viên nang nổi"],

        pillar2Title: "Bộ trộn âm thanh (Audio Studio)",
        pillar2Subtitle: "Chỉnh âm lượng loa tổng và điều chỉnh âm lượng độc lập cho từng ứng dụng đang chạy (0% – 200%).",
        pillar2Tags: ["Âm lượng từng App", "Khuếch đại 200%", "Đổi nhanh Loa", "Tắt tiếng nhanh"],

        purposeTitle: "Chọn tính năng bạn muốn dùng",
        purposeSubtitle: "Bật những bộ công cụ phù hợp với nhu cầu của bạn. Bạn có thể thay đổi bất cứ lúc nào trong phần Cài đặt.",
        purposeActiveCountFormat: "Đang bật %d / 2 tính năng",

        permissionsTitle: "Cấp quyền truy cập cần thiết",
        permissionsSubtitle: "SenseBar chỉ yêu cầu những quyền cần thiết cho các tính năng bạn đang bật. Mọi dữ liệu luôn nằm an toàn trên máy Mac của bạn.",
        permNote: "Bạn có thể cấp quyền ngay bây giờ hoặc bật sau trong phần Cài đặt.",

        doneTitle: "SenseBar",
        doneSubtitle: "Thiết lập hoàn tất. Bắt đầu sử dụng ngay trên thanh Menu Bar của bạn.",
        doneMenuBarHint: "Nhấn vào biểu tượng SenseBar trên thanh Menu Bar ở góc trên màn hình để mở nhanh bảng điều khiển bất cứ lúc nào.",
        doneActivePillarsTitle: "Tính năng đang bật:",

        btnBack: "Quay lại",
        btnContinue: "Tiếp tục",
        btnStart: "Bắt đầu sử dụng",

        settingsWindowTitle: "Cài đặt SenseBar",
        settingsTabGeneral: "Cài đặt chung",
        settingsTabPermissions: "Quyền truy cập",
        settingsTabAbout: "Giới thiệu",
        settingsStartupSection: "Khởi động & Hệ thống",
        settingsLaunchAtLogin: "Khởi động cùng macOS",
        settingsLaunchAtLoginDesc: "Tự động chạy SenseBar trên thanh Menu Bar khi bạn đăng nhập vào máy Mac.",
        settingsFeaturesSection: "Các tính năng của SenseBar",
        settingsOnboardingSection: "Hướng dẫn ban đầu",
        settingsReopenWelcomeDesc: "Xem lại màn hình giới thiệu và thiết lập ban đầu của SenseBar.",
        aboutSubtitle: "Tiện ích thanh Menu Bar gọn nhẹ cho macOS — Tích hợp Tai thỏ & Dynamic Island trình phát nhạc và Bộ trộn âm thanh từng ứng dụng.",
        aboutVersionFormat: "Phiên bản %@ (Build %@)",
        aboutLicenseBadge: "Giấy phép mã nguồn mở GNU GPL v3.0",
        aboutOpenGitHub: "Xem mã nguồn trên GitHub"
    )

    static let en = SenseStrings(
        menuBarTooltip: "SenseBar — Active",
        menuOpenPanel: "Open SenseBar Panel",
        menuShowWelcome: "Show Welcome Screen…",
        menuSettings: "SenseBar Settings…",
        menuAbout: "About SenseBar",
        menuQuit: "Quit SenseBar",

        welcomeTitle: "SenseBar",
        welcomeSubtitle: "A lightweight macOS Menu Bar companion — Uniting Notch Dynamic Island Music Player and Per-App Volume Mixer.",

        pillar1Title: "Dynamic Island & Notch",
        pillar1Subtitle: "Turn your MacBook notch into an interactive music studio with album artwork, colored audio visualizer, and smooth playback controls.",
        pillar1Tags: ["Music Player", "Visualizer", "Notch Cutout", "Floating Pill"],

        pillar2Title: "Audio Studio & Volume Mixer",
        pillar2Subtitle: "Control master speaker volume and adjust individual app volumes (0% – 200%) independently.",
        pillar2Tags: ["Per-App Volume", "200% Boost", "Speaker Control", "Quick Mute"],

        purposeTitle: "Choose what you want to use",
        purposeSubtitle: "Enable the tools that fit your workflow. You can change these anytime in Settings.",
        purposeActiveCountFormat: "%d of 2 features enabled",

        permissionsTitle: "Required Permissions",
        permissionsSubtitle: "SenseBar only asks for permissions needed by the features you enabled. All data stays on your Mac.",
        permNote: "You can grant permissions now or enable them later in Settings.",

        doneTitle: "SenseBar is Ready!",
        doneSubtitle: "Setup is complete. Access SenseBar anytime from your Menu Bar.",
        doneMenuBarHint: "Click the SenseBar icon in your macOS Menu Bar anytime to open the control panel.",
        doneActivePillarsTitle: "Enabled features:",

        btnBack: "Back",
        btnContinue: "Continue",
        btnStart: "Start Using",

        settingsWindowTitle: "SenseBar Settings",
        settingsTabGeneral: "General",
        settingsTabPermissions: "Permissions",
        settingsTabAbout: "About",
        settingsStartupSection: "Startup & System",
        settingsLaunchAtLogin: "Launch at Login",
        settingsLaunchAtLoginDesc: "Automatically start SenseBar in the Menu Bar when you log into your Mac.",
        settingsFeaturesSection: "SenseBar Features",
        settingsOnboardingSection: "Welcome Guide",
        settingsReopenWelcomeDesc: "Reopen the initial welcome and setup guide.",
        aboutSubtitle: "A lightweight macOS Menu Bar companion — Uniting Dynamic Island and Per-App Audio Studio.",
        aboutVersionFormat: "Version %@ (Build %@)",
        aboutLicenseBadge: "GNU GPL v3.0 Open Source License",
        aboutOpenGitHub: "View Source on GitHub"
    )
}

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
        if let raw = UserDefaults.standard.string(forKey: DefaultsKey.language),
           let saved = AppLanguage(rawValue: raw) {
            language = saved
        } else {
            language = .vi
            UserDefaults.standard.set(AppLanguage.vi.rawValue, forKey: DefaultsKey.language)
        }
    }
}
