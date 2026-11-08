import Foundation

enum AppInfo {
    static let name = "SenseBar"
    static let author = "Ngochiendev"
    static let repositoryURL = URL(string: "https://github.com/Ngochiendev/SenseBar")!

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String
    }
}