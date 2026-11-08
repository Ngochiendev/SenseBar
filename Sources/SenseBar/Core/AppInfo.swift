import Foundation

enum AppInfo {
    static let name = "SenseBar"
    static let brandSignature = "SenseBar by ngochiendev"
    static let copyright = "© 2026 SenseBar by ngochiendev"
    static let repositoryURL = URL(string: "https://github.com/Ngochiendev/SenseBar")!

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.1"
    }

    static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "2"
    }
}
