import AppKit
import Foundation

/// Nhóm nguồn phát YouTube / YouTube Music được SenseBar hỗ trợ đọc danh sách chờ.
enum YouTubeCandidateFamily: Equatable, Sendable {
    case chromium(bundleID: String)
    case safari(bundleID: String)
    case safariWebApp(bundleID: String)
    case gecko(bundleID: String, profileFolder: String)
    case kaset(bundleID: String)
    case pearDesktop(bundleID: String)

    var supportsAppleScriptNavigation: Bool {
        switch self {
        case .chromium, .safari: return true
        case .safariWebApp, .gecko, .kaset, .pearDesktop: return false
        }
    }

    var isBrowser: Bool {
        switch self {
        case .chromium, .safari, .safariWebApp, .gecko: return true
        case .kaset, .pearDesktop: return false
        }
    }

    static func classify(bundleID: String) -> YouTubeCandidateFamily? {
        let lower = bundleID.lowercased()
        let chromiumAllowlist: [String: String] = [
            "com.google.chrome": "com.google.Chrome",
            "com.google.chrome.canary": "com.google.Chrome.canary",
            "com.google.chrome.beta": "com.google.Chrome.beta",
            "com.brave.browser": "com.brave.Browser",
            "com.microsoft.edgemac": "com.microsoft.edgemac",
            "company.thebrowser.browser": "company.thebrowser.Browser",
            "com.vivaldi.vivaldi": "com.vivaldi.Vivaldi",
            "com.operasoftware.opera": "com.operasoftware.Opera",
            "org.chromium.chromium": "org.chromium.Chromium",
            "ai.perplexity.comet": "ai.perplexity.comet"
        ]
        if let canonical = chromiumAllowlist[lower] {
            return .chromium(bundleID: canonical)
        }
        if lower == "com.apple.safari" { return .safari(bundleID: "com.apple.Safari") }
        if lower == "com.apple.safaritechnologypreview" { return .safari(bundleID: "com.apple.SafariTechnologyPreview") }
        if lower.hasPrefix("com.apple.safari.webapp.") { return .safariWebApp(bundleID: bundleID) }

        let geckoMap: [String: (String, String)] = [
            "app.zen-browser.zen": ("app.zen-browser.zen", "zen/Profiles"),
            "org.mozilla.firefox": ("org.mozilla.firefox", "Firefox/Profiles"),
            "org.mozilla.firefoxdeveloperedition": ("org.mozilla.firefoxdeveloperedition", "Firefox/Profiles"),
            "net.waterfox.waterfox": ("net.waterfox.waterfox", "Waterfox/Profiles"),
            "io.gitlab.librewolf-community.librewolf": ("io.gitlab.librewolf-community.librewolf", "LibreWolf/Profiles")
        ]
        if let (canonical, folder) = geckoMap[lower] {
            return .gecko(bundleID: canonical, profileFolder: folder)
        }
        if lower == "com.sertacozercan.kaset" {
            return .kaset(bundleID: "com.sertacozercan.Kaset")
        }
        if ["com.github.th-ch.youtube-music", "app.pear-desktop", "com.pear-devs.pear-desktop"].contains(lower) {
            return .pearDesktop(bundleID: bundleID)
        }
        return nil
    }
}

/// Đại diện một tab YouTube / YouTube Music tìm thấy trong trình duyệt.
struct BrowserYouTubeTab: Equatable, Sendable {
    let browserBundleID: String
    let tabIdentifier: String
    let windowIndex: Int
    let tabIndex: Int
    let isActive: Bool
    let title: String
    let url: URL
    let context: YouTubeWatchContext
}

/// Kết quả định vị tab trình duyệt (không dùng extension, không chạy JavaScript trong trang).
enum BrowserTabLocateResult: Equatable, Sendable {
    case found(BrowserYouTubeTab)
    case notFound
    case automationDenied
}

/// Đọc URL/tiêu đề tab và điều hướng tab YouTube qua Apple Events tiêu chuẩn (không đụng `execute javascript`)
/// hoặc file session `recovery.jsonlz4` của Firefox/Zen.
enum BrowserTabLocator {
    private static let recordSeparator = "\u{1E}"
    private static let fieldSeparator = "\u{1F}"

    /// Định vị đúng tab YouTube / YouTube Music tương ứng với bài đang phát.
    static func locateTab(
        family: YouTubeCandidateFamily,
        trackTitle: String,
        trackArtist: String
    ) -> BrowserTabLocateResult {
        switch family {
        case .chromium(let bundleID):
            return locateViaAppleScript(bundleID: bundleID, isSafari: false, trackTitle: trackTitle, trackArtist: trackArtist)
        case .safari(let bundleID):
            return locateViaAppleScript(bundleID: bundleID, isSafari: true, trackTitle: trackTitle, trackArtist: trackArtist)
        case .gecko(let bundleID, let profileFolder):
            let tabs = readGeckoSessionTabs(bundleID: bundleID, profileFolder: profileFolder)
            if let match = selectBestTab(from: tabs, trackTitle: trackTitle, trackArtist: trackArtist) {
                return .found(match)
            }
            return .notFound
        case .safariWebApp, .kaset, .pearDesktop:
            return .notFound
        }
    }

    /// Chọn tab khớp duy nhất; không đoán theo tab đang được chọn khi nhiều tab trùng tiêu đề.
    static func selectBestTab(
        from tabs: [BrowserYouTubeTab],
        trackTitle: String,
        trackArtist: String
    ) -> BrowserYouTubeTab? {
        guard !tabs.isEmpty else { return nil }
        let matched = tabs.filter { YouTubeQueueParser.matchesTabTitle($0.title, trackTitle: trackTitle, trackArtist: trackArtist) }
        if !matched.isEmpty {
            return matched.count == 1 ? matched.first : nil
        }
        // Trường hợp đặc thù YouTube Music: người dùng chuyển về Trang chủ/Thư viện trong cùng tab
        // trong khi thanh mini-player vẫn phát. Chỉ chọn khi duy nhất 1 tab music.youtube.com đang mở.
        let ytmTabs = tabs.filter { $0.context.site == .youtubeMusic }
        if ytmTabs.count == 1, tabs.count == 1 {
            return ytmTabs.first
        }
        return nil
    }

    /// Điều hướng đúng tab đã xác minh sang URL bài hát mới (không cần extension hay JavaScript).
    static func navigateTab(
        bundleID: String,
        tabIdentifier: String,
        windowIndex: Int,
        tabIndex: Int,
        expectedURL: URL,
        destinationURL: URL
    ) -> Bool {
        guard let family = YouTubeCandidateFamily.classify(bundleID: bundleID),
              YouTubeWatchContext.parse(url: destinationURL) != nil,
              YouTubeWatchContext.parse(url: expectedURL) != nil else { return false }
        let safeURL = destinationURL.absoluteString
        let sourceURL = expectedURL.absoluteString
        guard [safeURL, sourceURL].allSatisfy({ value in
            !value.contains("\"") && !value.contains("\\") && !value.contains("\n") && !value.contains("\r")
        }) else { return false }

        let script: String
        switch family {
        case .chromium(let canonical):
            let escapedID = tabIdentifier.replacingOccurrences(of: "\\", with: "").replacingOccurrences(of: "\"", with: "")
            script = """
            with timeout of 2 seconds
                if application id "\(canonical)" is not running then return "MISS"
                tell application id "\(canonical)"
                    if (count of windows) is 0 then return "ERR"
                    repeat with w in windows
                        try
                            repeat with t in tabs of w
                                try
                                    set tid to (id of t as text)
                                    if tid is "\(escapedID)" then
                                        set u to (URL of t as text)
                                        if u is "\(sourceURL)" then
                                            set URL of t to "\(safeURL)"
                                            return "OK"
                                        end if
                                    end if
                                end try
                            end repeat
                        end try
                    end repeat
                end tell
            end timeout
            return "MISS"
            """
        case .safari(let canonical):
            guard windowIndex >= 1, tabIndex >= 1 else { return false }
            script = """
            with timeout of 2 seconds
                if application id "\(canonical)" is not running then return "MISS"
                tell application id "\(canonical)"
                    if (count of windows) < \(windowIndex) then return "ERR"
                    set w to window \(windowIndex)
                    if (count of tabs of w) < \(tabIndex) then return "ERR"
                    set t to tab \(tabIndex) of w
                    set u to (URL of t as text)
                    if u is "\(sourceURL)" then
                        set matchCount to 0
                        repeat with candidateWindow in windows
                            repeat with candidateTab in tabs of candidateWindow
                                if (URL of candidateTab as text) is "\(sourceURL)" then set matchCount to matchCount + 1
                            end repeat
                        end repeat
                        if matchCount is not 1 then return "MISS"
                        set URL of t to "\(safeURL)"
                        return "OK"
                    end if
                end tell
            end timeout
            return "MISS"
            """
        default:
            return false
        }

        let output = runAppleScript(script, timeout: 2.5)
        return output.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "OK"
    }

    // MARK: - AppleScript Tab Enumeration (URL & Title only, zero JS)

    private static func locateViaAppleScript(
        bundleID: String,
        isSafari: Bool,
        trackTitle: String,
        trackArtist: String
    ) -> BrowserTabLocateResult {
        guard NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .contains(where: { !$0.isTerminated }) else { return .notFound }
        let script: String
        if isSafari {
            script = """
            with timeout of 2 seconds
                set recSep to character id 30
                set fldSep to character id 31
                set outText to ""
                if application id "\(bundleID)" is not running then return ""
                tell application id "\(bundleID)"
                    set wCount to count of windows
                    repeat with wi from 1 to wCount
                        try
                            set w to window wi
                            set activeIdx to -1
                            try
                                set activeIdx to index of current tab of w
                            end try
                            set tCount to count of tabs of w
                            repeat with ti from 1 to tCount
                                try
                                    set t to tab ti of w
                                    set u to URL of t
                                    if u is not missing value then
                                        set uText to u as text
                                        if uText contains "youtube.com" or uText contains "youtu.be" then
                                            set nText to ""
                                            try
                                                set nText to (name of t as text)
                                            end try
                                            set isAct to "0"
                                            if ti = activeIdx then set isAct to "1"
                                            set lineStr to (wi as text) & fldSep & (ti as text) & fldSep & isAct & fldSep & (wi as text) & ":" & (ti as text) & fldSep & nText & fldSep & uText
                                            if outText is "" then
                                                set outText to lineStr
                                            else
                                                set outText to outText & recSep & lineStr
                                            end if
                                        end if
                                    end if
                                end try
                            end repeat
                        end try
                    end repeat
                end tell
                return outText
            end timeout
            """
        } else {
            script = """
            with timeout of 2 seconds
                set recSep to character id 30
                set fldSep to character id 31
                set outText to ""
                if application id "\(bundleID)" is not running then return ""
                tell application id "\(bundleID)"
                    set wCount to count of windows
                    repeat with wi from 1 to wCount
                        try
                            set w to window wi
                            set activeID to ""
                            try
                                set activeID to (id of active tab of w as text)
                            end try
                            set tCount to count of tabs of w
                            repeat with ti from 1 to tCount
                                try
                                    set t to tab ti of w
                                    set u to URL of t
                                    if u is not missing value then
                                        set uText to u as text
                                        if uText contains "youtube.com" or uText contains "youtu.be" then
                                            set tid to ""
                                            try
                                                set tid to (id of t as text)
                                            end try
                                            set nText to ""
                                            try
                                                set nText to (title of t as text)
                                            end try
                                            set isAct to "0"
                                            if tid is not "" and tid = activeID then set isAct to "1"
                                            set lineStr to (wi as text) & fldSep & (ti as text) & fldSep & isAct & fldSep & tid & fldSep & nText & fldSep & uText
                                            if outText is "" then
                                                set outText to lineStr
                                            else
                                                set outText to outText & recSep & lineStr
                                            end if
                                        end if
                                    end if
                                end try
                            end repeat
                        end try
                    end repeat
                end tell
                return outText
            end timeout
            """
        }

        let result = runAppleScript(script, timeout: 2.5)
        if result.exitCode != 0 {
            if result.stderr.contains("-1743") || result.stderr.localizedCaseInsensitiveContains("Not authorized to send Apple events") {
                return .automationDenied
            }
            return .notFound
        }

        let tabs = parseAppleScriptTabListing(result.stdout, bundleID: bundleID)
        if let best = selectBestTab(from: tabs, trackTitle: trackTitle, trackArtist: trackArtist) {
            return .found(best)
        }
        return .notFound
    }

    static func parseAppleScriptTabListing(_ raw: String, bundleID: String) -> [BrowserYouTubeTab] {
        let trimmed = raw.trimmingCharacters(in: .newlines)
        guard !trimmed.isEmpty else { return [] }
        var tabs: [BrowserYouTubeTab] = []
        for record in trimmed.components(separatedBy: recordSeparator) {
            let fields = record.components(separatedBy: fieldSeparator)
            guard fields.count >= 6,
                  let wi = Int(fields[0]), let ti = Int(fields[1]),
                  let url = URL(string: fields[5].trimmingCharacters(in: .whitespacesAndNewlines)),
                  let context = YouTubeWatchContext.parse(url: url) else { continue }
            let isActive = fields[2] == "1"
            let tabID = fields[3]
            let title = fields[4]
            tabs.append(BrowserYouTubeTab(
                browserBundleID: bundleID,
                tabIdentifier: tabID,
                windowIndex: wi,
                tabIndex: ti,
                isActive: isActive,
                title: title,
                url: url,
                context: context
            ))
        }
        return tabs
    }

    // MARK: - Firefox / Zen Session Reader (`recovery.jsonlz4`)

    private static func readGeckoSessionTabs(bundleID: String, profileFolder: String) -> [BrowserYouTubeTab] {
        let support = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let root = support.appendingPathComponent(profileFolder)
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        let files = enumerator.compactMap { $0 as? URL }.filter {
            $0.lastPathComponent == "recovery.jsonlz4" || $0.lastPathComponent == "sessionstore.jsonlz4"
        }.sorted { modifiedDate($0) > modifiedDate($1) }.prefix(4)

        var tabs: [BrowserYouTubeTab] = []
        for file in files {
            guard let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize,
                  size <= 32_000_000,
                  let compressed = try? Data(contentsOf: file, options: [.mappedIfSafe]),
                  let json = BrowserArtworkService.decodeSession(compressed),
                  let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
                  let windows = object["windows"] as? [[String: Any]] else { continue }

            for (wi, window) in windows.enumerated() {
                let selectedTab = (window["selected"] as? Int) ?? -1
                let rawTabs = window["tabs"] as? [[String: Any]] ?? []
                for (ti, tab) in rawTabs.enumerated() {
                    let entries = tab["entries"] as? [[String: Any]] ?? []
                    let entryIndex = (tab["index"] as? Int ?? entries.count) - 1
                    guard entries.indices.contains(entryIndex) else { continue }
                    let entry = entries[entryIndex]
                    guard let rawURL = entry["url"] as? String,
                          let url = URL(string: rawURL),
                          let context = YouTubeWatchContext.parse(url: url) else { continue }
                    let title = entry["title"] as? String ?? ""
                    tabs.append(BrowserYouTubeTab(
                        browserBundleID: bundleID,
                        tabIdentifier: "gecko-\(wi + 1)-\(ti + 1)",
                        windowIndex: wi + 1,
                        tabIndex: ti + 1,
                        isActive: (ti + 1) == selectedTab,
                        title: title,
                        url: url,
                        context: context
                    ))
                }
            }
            if !tabs.isEmpty { break }
        }
        return tabs
    }

    private static func modifiedDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    // MARK: - Subprocess Runner (`osascript`)

    struct ScriptOutput: Sendable {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    /// Thực thi AppleScript qua stdin với giới hạn thời gian cứng, không dùng shell trung gian.
    static func runAppleScript(_ script: String, timeout: TimeInterval = 2.5) -> ScriptOutput {
        let process = Process()
        let inPipe = Pipe()
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.standardInput = inPipe
        process.standardOutput = outPipe
        process.standardError = errPipe
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }

        do {
            try process.run()
        } catch {
            return ScriptOutput(exitCode: -1, stdout: "", stderr: error.localizedDescription)
        }

        if let data = script.data(using: .utf8) {
            try? inPipe.fileHandleForWriting.write(contentsOf: data)
        }
        try? inPipe.fileHandleForWriting.close()

        let readGroup = DispatchGroup()
        let outBox = LockedDataBox()
        let errBox = LockedDataBox()

        readGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            outBox.set((try? outPipe.fileHandleForReading.readToEnd()) ?? Data())
            readGroup.leave()
        }
        readGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            errBox.set((try? errPipe.fileHandleForReading.readToEnd()) ?? Data())
            readGroup.leave()
        }

        let waitResult = finished.wait(timeout: .now() + timeout)
        if waitResult == .timedOut {
            process.terminate()
            _ = finished.wait(timeout: .now() + 0.3)
            return ScriptOutput(exitCode: -2, stdout: "", stderr: "Timed out")
        }

        _ = readGroup.wait(timeout: .now() + 0.5)
        return ScriptOutput(
            exitCode: process.terminationStatus,
            stdout: String(data: outBox.get(), encoding: .utf8) ?? "",
            stderr: String(data: errBox.get(), encoding: .utf8) ?? ""
        )
    }
}

private final class LockedDataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func set(_ value: Data) {
        lock.lock()
        data = value
        lock.unlock()
    }

    func get() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}
