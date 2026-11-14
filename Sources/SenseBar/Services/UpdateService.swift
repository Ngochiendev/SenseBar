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
    @Published private(set) var dismissedBannerVersion: String?

    var availableRelease: ReleaseInfo? {
        if case .updateAvailable(let info) = status {
            return info
        }
        return nil
    }

    var bannerRelease: ReleaseInfo? {
        guard let release = availableRelease,
              dismissedBannerVersion != release.version else {
            return nil
        }
        return release
    }

    private var updater: SPUUpdater?
    private var wakeObserver: NSObjectProtocol?
    private var lastProbeDate: Date?
    private var isManualCheckInFlight = false
    private let probeCooldown: TimeInterval = 15 * 60
#if DEBUG
    private var previewDriver: SenseBarUpdateUserDriver?
#endif

    private override init() {
        super.init()
        UserDefaults.standard.register(defaults: [
            DefaultsKey.autoCheckUpdates: true
        ])
    }

    /// Khởi động kiểm tra cập nhật tự động khi mở ứng dụng, khi thức dậy từ Sleep và định kỳ mỗi 1 giờ.
    func start() {
        if showUpdatePreviewIfRequested() { return }
        if applySimulatedUpdateIfRequested() { return }

        guard updater == nil else { return }
        guard let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              Data(base64Encoded: key)?.count == 32 else {
            status = .failed
            return
        }
        let driver = SenseBarUpdateUserDriver(hostBundle: .main, delegate: nil)
        let updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: driver, delegate: self)
        self.updater = updater
        let autoEnabled = UserDefaults.standard.bool(forKey: DefaultsKey.autoCheckUpdates)
        updater.automaticallyChecksForUpdates = autoEnabled
        do {
            try updater.start()
            registerWakeObserverIfNeeded()
            if autoEnabled {
                lastProbeDate = Date()
                updater.checkForUpdatesInBackground()
            }
        } catch {
            self.updater = nil
            status = .failed
        }
    }

    private func registerWakeObserverIfNeeded() {
        guard wakeObserver == nil else { return }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                Task { @MainActor in
                    self?.probeForUpdateIfNeeded()
                }
            }
        }
    }

    func setAutomaticChecks(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: DefaultsKey.autoCheckUpdates)
        updater?.automaticallyChecksForUpdates = enabled
        if enabled {
            probeForUpdateIfNeeded(force: true)
        }
    }

    /// Thăm dò nhẹ `appcast.xml` ở nền (không bật popup làm phiền) với cooldown 15 phút.
    func probeForUpdateIfNeeded(force: Bool = false) {
        if showUpdatePreviewIfRequested() { return }
        if applySimulatedUpdateIfRequested() { return }
        guard UserDefaults.standard.bool(forKey: DefaultsKey.autoCheckUpdates) else { return }
        if updater == nil {
            start()
            return
        }
        guard let updater, !updater.sessionInProgress, updater.canCheckForUpdates else { return }
        if !force, let lastProbeDate, Date().timeIntervalSince(lastProbeDate) < probeCooldown {
            return
        }
        lastProbeDate = Date()
        isManualCheckInFlight = false
        updater.checkForUpdateInformation()
    }

    func dismissBanner(for version: String) {
        dismissedBannerVersion = version
    }

    /// Kiểm tra và cài cập nhật qua Sparkle từ appcast HTTPS.
    /// - Parameter manual: `true` nếu người dùng chủ động bấm nút kiểm tra.
    func checkForUpdates(manual: Bool = false) {
        if showUpdatePreviewIfRequested() { return }
        if applySimulatedUpdateIfRequested() { return }
        if updater == nil { start() }
        guard let updater, updater.canCheckForUpdates else { return }
        lastProbeDate = Date()
        if manual {
            isManualCheckInFlight = true
            status = .checking
            updater.checkForUpdates()
        } else {
            isManualCheckInFlight = false
            updater.checkForUpdatesInBackground()
        }
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let newVersion = Self.normalizeVersion(item.displayVersionString)
        if dismissedBannerVersion != nil && dismissedBannerVersion != newVersion {
            dismissedBannerVersion = nil
        }
        status = .updateAvailable(ReleaseInfo(version: newVersion.isEmpty ? item.displayVersionString : newVersion,
            htmlURL: item.releaseNotesURL ?? URL(string: "https://sensebar.site")!, dmgDownloadURL: nil))
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        status = .upToDate
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        applyErrorStatus(error)
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        defer { isManualCheckInFlight = false }
        if let error {
            applyErrorStatus(error)
        } else if status == .checking {
            status = .idle
        }
    }

    private func applyErrorStatus(_ error: Error) {
        let nextStatus = Self.statusAfterUpdateError(error)
        if nextStatus == .failed && !isManualCheckInFlight {
            if case .updateAvailable = status { return }
            status = .idle
            return
        }
        status = nextStatus
    }

    /// Sparkle kết thúc cả trường hợp không có bản mới bằng một NSError.
    static func statusAfterUpdateError(_ error: Error) -> Status {
        let error = error as NSError
        if error.domain == SUSparkleErrorDomain {
            switch error.code {
            case Int(SUError.noUpdateError.rawValue):
                return .upToDate
            case Int(SUError.installationCanceledError.rawValue),
                 Int(SUError.installationAuthorizeLaterError.rawValue):
                return .idle
            default:
                break
            }
        }
        return .failed
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

    /// Mở UI thật bằng release notes sinh từ changelog, không khởi tạo tải/cài.
    private func showUpdatePreviewIfRequested() -> Bool {
#if DEBUG
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--preview-update") else { return false }
        guard previewDriver == nil else { return true }
        let next = arguments.index(after: index)
        let version = arguments.indices.contains(next) && !arguments[next].hasPrefix("--")
            ? Self.normalizeVersion(arguments[next]) : "9.9.9"
        let driver = SenseBarUpdateUserDriver(hostBundle: .main, delegate: nil)
        previewDriver = driver
        status = .updateAvailable(ReleaseInfo(version: version, htmlURL: URL(string: "https://sensebar.site")!, dmgDownloadURL: nil))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            driver.showUpdatePreview(version: version) {
                self?.previewDriver = nil
            }
        }
        return true
#else
        return false
#endif
    }

    func openDownloadPage() {
        NSApp.activate(ignoringOtherApps: true)
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
