import Foundation

enum AppInfo {
    static let name = "SenseBar"
    static let author = "ngochiendev"
    static let brandSignature = "SenseBar by ngochiendev"
    static let studioBadge = "STUDIO"
    static let copyright = "© 2026 SenseBar by ngochiendev"
    static let repositoryURL = URL(string: "https://github.com/Ngochiendev/SenseBar")!

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }
}
