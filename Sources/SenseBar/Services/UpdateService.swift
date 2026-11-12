import AppKit
import Foundation
import Sparkle

@MainActor
final class UpdateService: NSObject, ObservableObject, SPUUpdaterDelegate {
    static let shared = UpdateService()

    struct ReleaseInfo: Equatable {
        let version: String
        let htmlURL: URL
        let dmgDownloadURL: URL?

        var preferredDownloadURL: URL {
            dmgDownloadURL ?? htmlURL
        }
    }

    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case updateAvailable(ReleaseInfo)
        case failed
    }

    @Published private(set) var status: Status = .idle

    var availableRelease: ReleaseInfo? {
        if case .updateAvailable(let info) = status {
            return info
        }
        return nil
    }

    private var controller: SPUStandardUpdaterController?

    private override init() {
        super.init()
        UserDefaults.standard.register(defaults: [
            DefaultsKey.autoCheckUpdates: true
        ])
    }

    /// Khởi động kiểm tra cập nhật tự động khi mở ứng dụng và định kỳ mỗi 24 giờ.
    func start() {
        if applySimulatedUpdateIfRequested() { return }

        guard controller == nil else { return }
        guard let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              Data(base64Encoded: key)?.count == 32 else {
            status = .failed
            return
        }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        self.controller = controller
        controller.updater.automaticallyChecksForUpdates = UserDefaults.standard.bool(forKey: DefaultsKey.autoCheckUpdates)
        controller.startUpdater()
    }

    func setAutomaticChecks(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: DefaultsKey.autoCheckUpdates)
        controller?.updater.automaticallyChecksForUpdates = enabled
    }

    /// Kiểm tra và cài cập nhật qua Sparkle từ appcast HTTPS.
    /// - Parameter manual: `true` nếu người dùng chủ động bấm nút kiểm tra.
    func checkForUpdates(manual: Bool = false) {
        if applySimulatedUpdateIfRequested() { return }
        if controller == nil { start() }
        guard let controller, controller.updater.canCheckForUpdates else { return }
        if manual {
            status = .checking
            controller.checkForUpdates(nil)
        } else {
            controller.updater.checkForUpdatesInBackground()
        }
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        status = .updateAvailable(ReleaseInfo(version: item.displayVersionString,
            htmlURL: item.releaseNotesURL ?? URL(string: "https://sensebar.site")!, dmgDownloadURL: nil))
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        status = .upToDate
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        status = .failed
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        if status == .checking { status = error == nil ? .idle : .failed }
    }

    /// Hiển thị trạng thái có bản cập nhật trong debug build mà không truy cập GitHub.
    /// Dùng `--simulate-update 1.3.0`; nếu bỏ version, mặc định hiển thị `9.9.9`.
    private func applySimulatedUpdateIfRequested() -> Bool {
#if DEBUG
        let arguments = CommandLine.arguments
        guard let flagIndex = arguments.firstIndex(of: "--simulate-update") else { return false }

        let valueIndex = arguments.index(after: flagIndex)
        let requestedVersion = arguments.indices.contains(valueIndex) && !arguments[valueIndex].hasPrefix("--")
            ? Self.normalizeVersion(arguments[valueIndex])
            : "9.9.9"

        status = .updateAvailable(
            ReleaseInfo(
                version: requestedVersion.isEmpty ? "9.9.9" : requestedVersion,
                htmlURL: AppInfo.releasesURL,
                dmgDownloadURL: nil
            )
        )
        return true
#else
        return false
#endif
    }

    func openDownloadPage() {
        checkForUpdates(manual: true)
    }

    func openReleaseNotes() {
        if let release = availableRelease {
            NSWorkspace.shared.open(release.htmlURL)
        } else {
            NSWorkspace.shared.open(AppInfo.releasesURL)
        }
    }

    // MARK: - So sánh Semantic Version

    nonisolated static func normalizeVersion(_ raw: String) -> String {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("v") {
            trimmed.removeFirst()
        }
        if let dashIndex = trimmed.firstIndex(of: "-") {
            trimmed = String(trimmed[..<dashIndex])
        }
        return trimmed
    }

    nonisolated static func isNewerVersion(_ candidate: String, than current: String) -> Bool {
        let lhs = normalizeVersion(candidate).split(separator: ".").map { Int($0) ?? 0 }
        let rhs = normalizeVersion(current).split(separator: ".").map { Int($0) ?? 0 }
        let count = max(lhs.count, rhs.count)

        for index in 0..<count {
            let lVal = index < lhs.count ? lhs[index] : 0
            let rVal = index < rhs.count ? rhs[index] : 0
            if lVal != rVal {
                return lVal > rVal
            }
        }
        return false
    }
}
