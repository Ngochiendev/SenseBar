import Combine
import Foundation

/// Ngôn ngữ hiển thị của SenseBar. Mặc định dùng Tiếng Việt (.vi),
/// sẵn sàng hỗ trợ Tiếng Anh (.en) trong tương lai.
enum AppLanguage: String, CaseIterable, Identifiable {
    case vi = "vi"
    case en = "en"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .vi: return "Tiếng Việt"
        case .en: return "English"
        }
    }

    static var systemDefault: AppLanguage { .vi }
}

struct SenseStrings {
    // Menu Bar & App
    var menuBarTooltip: String
    var menuShowWelcome: String
    var menuSettings: String
    var menuAbout: String
    var menuQuit: String

    // Onboarding Step 1: Welcome
    var welcomeWindowTitle: String
    var welcomeTitle: String
    var welcomeSubtitle: String

    // 3 Core Features
    var pillar1Title: String
    var pillar1Subtitle: String
    var pillar1Tags: [String]

    var pillar2Title: String
    var pillar2Subtitle: String
    var pillar2Tags: [String]

    var pillar3Title: String
    var pillar3Subtitle: String
    var pillar3Tags: [String]

    // Onboarding Step 2: Features Selection
    var purposeTitle: String
    var purposeSubtitle: String
    var purposeActiveCountFormat: String

    // Onboarding Step 3: Permissions
    var permissionsTitle: String
    var permissionsSubtitle: String
    var permAccessibilityTitle: String
    var permAccessibilityDesc: String
    var permAudioScreenTitle: String
    var permAudioScreenDesc: String
    var permGrantedBadge: String
    var permRequiredBadge: String
    var permGrantButton: String
    var permOpenSettingsButton: String
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

    static let vi = SenseStrings(
        menuBarTooltip: "SenseBar — Đang hoạt động",
        menuShowWelcome: "Mở màn hình Chào mừng…",
        menuSettings: "Cài đặt SenseBar…",
        menuAbout: "Giới thiệu SenseBar",
        menuQuit: "Thoát SenseBar",

        welcomeWindowTitle: "SenseBar",
        welcomeTitle: "SenseBar",
        welcomeSubtitle: "Tiện ích thanh Menu Bar gọn nhẹ cho macOS — Tích hợp Dynamic Island, điều chỉnh âm lượng từng ứng dụng và theo dõi nhiệt độ, quạt tản nhiệt.",

        pillar1Title: "Tai thỏ & Dynamic Island",
        pillar1Subtitle: "Biến phần tai thỏ MacBook thành khu vực điều khiển nhanh: trình phát nhạc, sóng nhạc, thông báo hệ thống và lăn chuột chỉnh âm lượng, độ sáng.",
        pillar1Tags: ["Trình phát nhạc", "Sóng nhạc", "Cuộn chỉnh âm lượng", "Thông báo"],

        pillar2Title: "Bộ trộn âm thanh (Audio Studio)",
        pillar2Subtitle: "Chỉnh âm lượng riêng cho từng ứng dụng (0% – 200%), đổi nhanh loa/micro và tự động tắt tiếng khi rút tai nghe.",
        pillar2Tags: ["Âm lượng từng App", "Khuếch đại 200%", "Tự ngắt khi rút tai nghe", "Tắt nhanh Micro"],

        pillar3Title: "Theo dõi phần cứng & Quạt tản nhiệt",
        pillar3Subtitle: "Xem trực tiếp nhiệt độ CPU/GPU, mức dùng RAM, tốc độ mạng và chủ động điều chỉnh tốc độ quạt trên máy Mac.",
        pillar3Tags: ["Điều khiển quạt", "Nhiệt độ CPU & GPU", "Mức dùng RAM", "Mạng & Pin"],

        purposeTitle: "Chọn tính năng bạn muốn dùng",
        purposeSubtitle: "Bật những bộ công cụ phù hợp với nhu cầu của bạn. Bạn có thể thay đổi bất cứ lúc nào trong phần Cài đặt.",
        purposeActiveCountFormat: "Đang bật %d / 3 tính năng",

        permissionsTitle: "Cấp quyền truy cập cần thiết",
        permissionsSubtitle: "SenseBar chỉ yêu cầu những quyền cần thiết cho các tính năng bạn đang bật. Mọi dữ liệu luôn nằm an toàn trên máy Mac của bạn.",
        permAccessibilityTitle: "Trợ năng (Accessibility)",
        permAccessibilityDesc: "Giúp Dynamic Island hiển thị chuẩn xác trên thanh Menu Bar và nhận thao tác lăn chuột chỉnh âm lượng, độ sáng.",
        permAudioScreenTitle: "Âm thanh hệ thống & Ghi màn hình",
        permAudioScreenDesc: "Cho phép tách luồng âm thanh để chỉnh âm lượng riêng cho từng ứng dụng và hiển thị sóng nhạc theo thời gian thực.",
        permGrantedBadge: "Đã cấp quyền",
        permRequiredBadge: "Cần cấp quyền",
        permGrantButton: "Cấp quyền ngay",
        permOpenSettingsButton: "Mở Cài đặt Hệ thống",
        permNote: "Bạn có thể cấp quyền ngay bây giờ hoặc bật sau trong phần Cài đặt.",

        doneTitle: "SenseBar",
        doneSubtitle: "Thiết lập hoàn tất. Bắt đầu sử dụng ngay trên thanh Menu Bar của bạn.",
        doneMenuBarHint: "Nhấn vào biểu tượng SenseBar trên thanh Menu Bar ở góc trên màn hình để mở nhanh bảng điều khiển bất cứ lúc nào.",
        doneActivePillarsTitle: "Tính năng đang bật:",

        btnBack: "Quay lại",
        btnContinue: "Tiếp tục",
        btnStart: "Bắt đầu sử dụng"
    )

    static let en = SenseStrings(
        menuBarTooltip: "SenseBar — Active",
        menuShowWelcome: "Show Welcome Screen…",
        menuSettings: "SenseBar Settings…",
        menuAbout: "About SenseBar",
        menuQuit: "Quit SenseBar",

        welcomeWindowTitle: "SenseBar",
        welcomeTitle: "SenseBar",
        welcomeSubtitle: "A lightweight macOS Menu Bar companion — Uniting Dynamic Island, Per-App Volume Mixer, and Hardware & Fan Monitor.",

        pillar1Title: "Dynamic Island & Notch",
        pillar1Subtitle: "Turn your MacBook notch into an interactive control center with music playback, audio visualizer, notifications, and scroll-to-adjust volume/brightness.",
        pillar1Tags: ["Music Player", "Visualizer", "Scroll Volume", "Notifications"],

        pillar2Title: "Audio Studio & Volume Mixer",
        pillar2Subtitle: "Adjust individual app volumes (0% – 200%), switch output/input devices quickly, and auto-mute speakers when headphones disconnect.",
        pillar2Tags: ["Per-App Volume", "200% Boost", "Headphone Safety", "Quick Mic Mute"],

        pillar3Title: "Hardware Monitor & Fan Control",
        pillar3Subtitle: "Monitor live CPU/GPU temperatures, memory usage, network speed, and control Mac fan speeds.",
        pillar3Tags: ["Fan Control", "CPU & GPU Temp", "Memory Usage", "Network & Battery"],

        purposeTitle: "Choose what you want to use",
        purposeSubtitle: "Enable the tools that fit your workflow. You can change these anytime in Settings.",
        purposeActiveCountFormat: "%d of 3 features enabled",

        permissionsTitle: "Required Permissions",
        permissionsSubtitle: "SenseBar only asks for permissions needed by the features you enabled. All data stays on your Mac.",
        permAccessibilityTitle: "Accessibility",
        permAccessibilityDesc: "Needed to position Dynamic Island around the menu bar and support scroll gestures.",
        permAudioScreenTitle: "System Audio & Screen Recording",
        permAudioScreenDesc: "Allows adjusting per-app volume streams and rendering real-time audio waves.",
        permGrantedBadge: "Granted",
        permRequiredBadge: "Required",
        permGrantButton: "Grant Access",
        permOpenSettingsButton: "Open System Settings",
        permNote: "You can grant permissions now or enable them later in Settings.",

        doneTitle: "SenseBar is Ready!",
        doneSubtitle: "Setup is complete. Access SenseBar anytime from your Menu Bar.",
        doneMenuBarHint: "Click the SenseBar icon in your macOS Menu Bar anytime to open the control panel.",
        doneActivePillarsTitle: "Enabled features:",

        btnBack: "Back",
        btnContinue: "Continue",
        btnStart: "Start Using"
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
