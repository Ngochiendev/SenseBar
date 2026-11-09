import AppKit
import Foundation

@MainActor
final class UpdateService: ObservableObject {
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

    private var timer: Timer?
    private let checkInterval: TimeInterval = 24 * 60 * 60

    private init() {
        UserDefaults.standard.register(defaults: [
            DefaultsKey.autoCheckUpdates: true
        ])
    }

    /// Khởi động kiểm tra cập nhật tự động khi mở ứng dụng và định kỳ mỗi 24 giờ.
    func start() {
        schedulePeriodicCheck()

        guard UserDefaults.standard.bool(forKey: DefaultsKey.autoCheckUpdates) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            self?.checkForUpdates(manual: false)
        }
    }

    private func schedulePeriodicCheck() {
        timer?.invalidate()
        let newTimer = Timer(timeInterval: checkInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard UserDefaults.standard.bool(forKey: DefaultsKey.autoCheckUpdates) else { return }
                self?.checkForUpdates(manual: false)
            }
        }
        newTimer.tolerance = 300
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    /// Kiểm tra phiên bản mới nhất từ GitHub Releases API.
    /// - Parameter manual: `true` nếu người dùng chủ động bấm nút kiểm tra.
    func checkForUpdates(manual: Bool = false) {
        if status == .checking { return }
        if manual {
            status = .checking
        }

        var request = URLRequest(url: AppInfo.latestReleaseAPIURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("\(AppInfo.name)/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        Task {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    if manual { self.status = .failed }
                    return
                }
                if http.statusCode == 404 {
                    // Repo đang để Private hoặc chưa có bản Release công khai nào
                    self.status = .upToDate
                    return
                }
                guard (200...299).contains(http.statusCode) else {
                    if manual { self.status = .failed }
                    return
                }

                let payload = try JSONDecoder().decode(GitHubReleasePayload.self, from: data)
                guard !payload.draft, !payload.prerelease else {
                    if manual { self.status = .upToDate }
                    return
                }

                let cleanVersion = Self.normalizeVersion(payload.tagName)
                let currentVersion = Self.normalizeVersion(AppInfo.version)

                if Self.isNewerVersion(cleanVersion, than: currentVersion),
                   let htmlURL = URL(string: payload.htmlURL) {
                    let dmgURL = payload.assets
                        .first { $0.name.lowercased().hasSuffix(".dmg") }
                        .flatMap { URL(string: $0.browserDownloadURL) }

                    self.status = .updateAvailable(
                        ReleaseInfo(
                            version: cleanVersion,
                            htmlURL: htmlURL,
                            dmgDownloadURL: dmgURL
                        )
                    )
                } else {
                    self.status = .upToDate
                }
            } catch {
                if manual {
                    self.status = .failed
                }
            }
        }
    }

    func openDownloadPage() {
        if let release = availableRelease {
            NSWorkspace.shared.open(release.preferredDownloadURL)
        } else {
            NSWorkspace.shared.open(AppInfo.releasesURL)
        }
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

private struct GitHubReleasePayload: Decodable {
    let tagName: String
    let htmlURL: String
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]

    struct Asset: Decodable {
        let name: String
        let browserDownloadURL: String

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case draft
        case prerelease
        case assets
    }
}

