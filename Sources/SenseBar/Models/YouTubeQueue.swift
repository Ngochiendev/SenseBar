import Foundation

/// Trang nguồn thuộc hệ sinh thái YouTube được hỗ trợ đọc danh sách chờ.
enum YouTubeSite: String, Equatable, Sendable {
    case youtube
    case youtubeMusic

    var host: String {
        switch self {
        case .youtube: return "www.youtube.com"
        case .youtubeMusic: return "music.youtube.com"
        }
    }

    var innerTubeClientName: String {
        switch self {
        case .youtube: return "WEB"
        case .youtubeMusic: return "WEB_REMIX"
        }
    }

    func innerTubeClientVersion(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd"
        let prefix = self == .youtube ? "2" : "1"
        return "\(prefix).\(formatter.string(from: date)).01.00"
    }
}

/// Phân loại độ chính xác và nguồn gốc dữ liệu danh sách chờ.
enum YouTubeQueueSourceKind: String, Equatable, Sendable {
    /// Đọc trực tiếp DOM thật từ tab đang hiển thị qua Accessibility.
    case liveAccessibility
    /// Thứ tự playlist/album công khai lấy từ YouTube InnerTube `/next`.
    case publicPlaylist
    /// Mix/Radio (`RD...`) hoặc gợi ý tự động phát tiếp theo (không cookie).
    case suggestedRadio
    case desktopApp
}

/// Hành động phát bài khi người dùng chọn một mục trong danh sách chờ.
enum YouTubeQueueAction: Equatable, Sendable {
    /// Bấm trực tiếp phần tử Accessibility trong tab đang hiển thị (không tải lại trang).
    case accessibility(ref: Int)
    /// Điều hướng đúng tab trình duyệt sang URL bài đã chọn qua Apple Events (không cần JS).
    case navigateTab(browserBundleID: String, tabIdentifier: String, windowIndex: Int, tabIndex: Int, expectedURL: URL, destinationURL: URL)
    case kaset(index: Int)
    case pear(index: Int)
    /// Chỉ xem trước (ví dụ tab nền Firefox/Zen không hỗ trợ đổi URL qua AppleScript).
    case none
}

/// Một mục bài hát/video sắp phát trong danh sách chờ YouTube / YouTube Music.
struct YouTubeQueueItem: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let artist: String
    let duration: TimeInterval
    let artworkURL: URL?
    let videoID: String?
    let playlistIndex: Int?
    let action: YouTubeQueueAction

    var canPlay: Bool { action != .none }
}

/// Lý do không có mục hiển thị trong danh sách chờ, giúp UI phản hồi trung thực.
enum YouTubeQueueEmptyReason: Equatable, Sendable {
    case notYouTubeSource
    case accessibilityRequired
    case automationDenied
    case privatePlaylistInBackground
    case queueNotVisible
    case empty
    case networkFailed
}

/// Ảnh chụp danh sách chờ tại một thời điểm cho đúng phiên phát hiện hành.
struct YouTubeQueueSnapshot: Equatable, Sendable {
    let sourceKind: YouTubeQueueSourceKind
    let site: YouTubeSite
    let playlistTitle: String?
    let items: [YouTubeQueueItem]
    let emptyReason: YouTubeQueueEmptyReason?

    var isSuggested: Bool { sourceKind == .suggestedRadio }
}

/// Thông tin ngữ cảnh phát trích xuất từ URL tab YouTube / YouTube Music.
struct YouTubeWatchContext: Equatable, Sendable {
    let site: YouTubeSite
    let videoID: String?
    let playlistID: String?
    /// Vị trí 1-based trong tham số `index=` của URL (nếu có).
    let index: Int?

    static func parse(url: URL) -> YouTubeWatchContext? {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let rawHost = url.host?.lowercased() else { return nil }
        let site: YouTubeSite
        if rawHost == "music.youtube.com" {
            site = .youtubeMusic
        } else if rawHost == "youtube.com" || rawHost == "www.youtube.com" || rawHost == "m.youtube.com" || rawHost == "youtu.be" {
            site = .youtube
        } else {
            return nil
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []
        func query(_ name: String) -> String? {
            queryItems.first { $0.name == name }?.value
        }

        var candidateVideoID: String?
        if rawHost == "youtu.be" {
            candidateVideoID = url.pathComponents.dropFirst().first
        } else if url.path == "/watch" {
            candidateVideoID = query("v")
        } else if let first = url.pathComponents.dropFirst().first, ["shorts", "live", "embed"].contains(first) {
            candidateVideoID = url.pathComponents.dropFirst(2).first
        }

        let validVideoID = candidateVideoID.flatMap { Self.isValidVideoID($0) ? $0 : nil }
        let validPlaylistID = query("list").flatMap { Self.isValidPlaylistID($0) ? $0 : nil }
        let parsedIndex = query("index").flatMap(Int.init).flatMap { $0 >= 1 ? $0 : nil }

        return YouTubeWatchContext(site: site, videoID: validVideoID, playlistID: validPlaylistID, index: parsedIndex)
    }

    var isPrivateListID: Bool {
        guard let list = playlistID else { return false }
        return list == "LM" || list == "WL" || list == "LL"
    }

    var isRadioOrMix: Bool {
        guard let list = playlistID else { return false }
        return list.hasPrefix("RD")
    }

    var isFixedPublicPlaylist: Bool {
        guard let list = playlistID, !isPrivateListID, !isRadioOrMix else { return false }
        return list.hasPrefix("PL") || list.hasPrefix("OLAK5uy_") || list.hasPrefix("UU")
            || list.hasPrefix("FL") || list.hasPrefix("EL") || list.count >= 12
    }

    /// Tạo URL điều hướng an toàn từ video ID và playlist ID đã kiểm tra định dạng.
    func destinationURL(videoID: String, index: Int?) -> URL? {
        guard Self.isValidVideoID(videoID) else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = site.host
        components.path = "/watch"
        var items = [URLQueryItem(name: "v", value: videoID)]
        if let playlistID, Self.isValidPlaylistID(playlistID) {
            items.append(URLQueryItem(name: "list", value: playlistID))
            if let index, index >= 1, !isRadioOrMix {
                items.append(URLQueryItem(name: "index", value: String(index)))
            }
        }
        components.queryItems = items
        return components.url
    }

    static func isValidVideoID(_ value: String) -> Bool {
        value.count == 11 && value.unicodeScalars.allSatisfy {
            ($0.value >= 48 && $0.value <= 57) || ($0.value >= 65 && $0.value <= 90)
                || ($0.value >= 97 && $0.value <= 122) || $0.value == 45 || $0.value == 95
        }
    }

    static func isValidPlaylistID(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 128 else { return false }
        return value.unicodeScalars.allSatisfy {
            ($0.value >= 48 && $0.value <= 57) || ($0.value >= 65 && $0.value <= 90)
                || ($0.value >= 97 && $0.value <= 122) || $0.value == 45 || $0.value == 95
        }
    }

    static func isTrustedArtworkURL(_ url: URL?) -> Bool {
        guard let url, url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
        return ["ytimg.com", "googleusercontent.com", "ggpht.com"].contains {
            host == $0 || host.hasSuffix("." + $0)
        }
    }

    static func thumbnailURL(forVideoID videoID: String) -> URL? {
        guard isValidVideoID(videoID) else { return nil }
        return URL(string: "https://i.ytimg.com/vi/\(videoID)/mqdefault.jpg")
    }
}

/// Dữ liệu phẳng của một node Accessibility để bộ phân tích chạy thuần túy và kiểm thử được offline.
struct YouTubeAXNodeEntry: Equatable, Sendable {
    let role: String
    let domID: String
    let classes: Set<String>
    let text: String
    let label: String
    let url: URL?
    let isSelected: Bool
    let ref: Int

    func hasClass(_ name: String) -> Bool { classes.contains(name) }
}

enum YouTubeQueueParser {
    static let maximumItems = 25

    static func fold(_ text: String) -> String {
        let stripped = text
            .replacingOccurrences(of: #"^\(\d+\+?\)\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: " - YouTube Music", with: "", options: [.caseInsensitive, .anchored, .backwards])
            .replacingOccurrences(of: " – YouTube Music", with: "", options: [.caseInsensitive, .anchored, .backwards])
            .replacingOccurrences(of: " - YouTube", with: "", options: [.caseInsensitive, .anchored, .backwards])
            .replacingOccurrences(of: " – YouTube", with: "", options: [.caseInsensitive, .anchored, .backwards])
        return stripped
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Chuyển chuỗi thời lượng `"3:45"` hoặc `"1:02:03"` sang giây; trả về `0` nếu không hợp lệ.
    static func parseDuration(_ raw: String) -> TimeInterval {
        let parts = raw.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":")
        guard (2...3).contains(parts.count) else { return 0 }
        var total = 0.0
        for (idx, part) in parts.enumerated() {
            guard let value = Int(part), value >= 0, (idx == 0 || (value < 60 && part.count <= 2)) else { return 0 }
            total = total * 60 + Double(value)
        }
        return total
    }

    /// Kiểm tra tiêu đề tab trình duyệt có khớp bài đang phát hay không.
    static func matchesTabTitle(_ tabTitle: String, trackTitle: String, trackArtist: String = "") -> Bool {
        let expected = fold(trackTitle)
        let actual = fold(tabTitle)
        guard !expected.isEmpty, !actual.isEmpty else { return false }
        if actual == expected { return true }
        if expected.count >= 8 {
            return actual.hasPrefix(expected + " ") || expected.hasPrefix(actual + " ")
        }
        let artist = fold(trackArtist)
        if !artist.isEmpty, actual.hasPrefix(expected + " "), actual.contains(artist) {
            return true
        }
        return false
    }

    // MARK: - InnerTube `/youtubei/v1/next`

    struct InnerTubeParsed: Equatable, Sendable {
        let sourceKind: YouTubeQueueSourceKind
        let playlistTitle: String?
        let items: [YouTubeQueueItem]
        let emptyReason: YouTubeQueueEmptyReason?
    }

    /// Phân tích phản hồi JSON từ `youtubei/v1/next` cho cả YouTube (`WEB`) và YouTube Music (`WEB_REMIX`).
    static func parseInnerTubeNext(
        data: Data,
        context: YouTubeWatchContext,
        currentTitle: String,
        actionBuilder: (String, Int?) -> YouTubeQueueAction
    ) -> InnerTubeParsed {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let contents = root["contents"] as? [String: Any] else {
            return InnerTubeParsed(sourceKind: .publicPlaylist, playlistTitle: nil, items: [], emptyReason: .networkFailed)
        }

        switch context.site {
        case .youtubeMusic:
            return parseYouTubeMusicNext(contents: contents, context: context, currentTitle: currentTitle, actionBuilder: actionBuilder)
        case .youtube:
            return parseYouTubeWebNext(contents: contents, context: context, currentTitle: currentTitle, actionBuilder: actionBuilder)
        }
    }

    private static func parseYouTubeWebNext(
        contents: [String: Any],
        context: YouTubeWatchContext,
        currentTitle: String,
        actionBuilder: (String, Int?) -> YouTubeQueueAction
    ) -> InnerTubeParsed {
        guard let twoCol = contents["twoColumnWatchNextResults"] as? [String: Any] else {
            return InnerTubeParsed(sourceKind: .publicPlaylist, playlistTitle: nil, items: [], emptyReason: .queueNotVisible)
        }

        // Trường hợp 1: Đang phát trong Playlist hoặc Mix (`playlist.playlist.contents`)
        if let playlistWrapper = twoCol["playlist"] as? [String: Any],
           let playlist = playlistWrapper["playlist"] as? [String: Any],
           let rawContents = playlist["contents"] as? [[String: Any]], !rawContents.isEmpty {
            let playlistTitle = extractText(playlist["title"])
            let kind: YouTubeQueueSourceKind = context.isFixedPublicPlaylist ? .publicPlaylist : .suggestedRadio
            let rows = parsePlaylistPanelContents(
                rawContents,
                currentVideoID: context.videoID,
                currentIndex1Based: context.index,
                currentTitle: currentTitle,
                actionBuilder: actionBuilder
            )
            return InnerTubeParsed(
                sourceKind: kind,
                playlistTitle: playlistTitle.isEmpty ? nil : playlistTitle,
                items: rows,
                emptyReason: rows.isEmpty ? .empty : nil
            )
        }

        // Nếu URL có `list=` nhưng server không trả `playlist` -> playlist riêng tư / không truy cập được không cookie.
        if context.playlistID != nil {
            return InnerTubeParsed(sourceKind: .publicPlaylist, playlistTitle: nil, items: [], emptyReason: .privatePlaylistInBackground)
        }

        // Trường hợp 2: Video đơn không có playlist -> Autoplay + Secondary Results (`lockupViewModel` / `compactVideoRenderer`)
        let autoplayVideoID: String? = {
            guard let apWrapper = twoCol["autoplay"] as? [String: Any],
                  let ap = apWrapper["autoplay"] as? [String: Any],
                  let sets = ap["sets"] as? [[String: Any]],
                  let first = sets.first,
                  let ep = (first["autoplayVideo"] as? [String: Any])?["watchEndpoint"] as? [String: Any],
                  let vid = ep["videoId"] as? String,
                  YouTubeWatchContext.isValidVideoID(vid) else { return nil }
            return vid
        }()

        let secondaryResults = ((twoCol["secondaryResults"] as? [String: Any])?["secondaryResults"] as? [String: Any])?["results"] as? [[String: Any]] ?? []
        var items: [YouTubeQueueItem] = []
        var seen = Set<String>()
        if let cur = context.videoID { seen.insert(cur) }

        for entry in secondaryResults {
            guard items.count < 16 else { break }
            if let item = parseSecondaryEntry(entry, seen: &seen, actionBuilder: actionBuilder) {
                items.append(item)
            }
        }

        // Đưa bài Autoplay chính thức lên đầu danh sách gợi ý nếu có trong danh sách.
        if let autoplayVideoID, let idx = items.firstIndex(where: { $0.videoID == autoplayVideoID }), idx > 0 {
            let nextUp = items.remove(at: idx)
            items.insert(nextUp, at: 0)
        }

        return InnerTubeParsed(
            sourceKind: .suggestedRadio,
            playlistTitle: nil,
            items: items,
            emptyReason: items.isEmpty ? .empty : nil
        )
    }

    private static func parseYouTubeMusicNext(
        contents: [String: Any],
        context: YouTubeWatchContext,
        currentTitle: String,
        actionBuilder: (String, Int?) -> YouTubeQueueAction
    ) -> InnerTubeParsed {
        let tabs = (((contents["singleColumnMusicWatchNextResultsRenderer"] as? [String: Any])?["tabbedRenderer"] as? [String: Any])?["watchNextTabbedResultsRenderer"] as? [String: Any])?["tabs"] as? [[String: Any]] ?? []
        let firstTabContent = (tabs.first?["tabRenderer"] as? [String: Any])?["content"] as? [String: Any]
        let musicQueue = firstTabContent?["musicQueueRenderer"] as? [String: Any]
        let panel = (musicQueue?["content"] as? [String: Any])?["playlistPanelRenderer"] as? [String: Any]
        let rawContents = panel?["contents"] as? [[String: Any]] ?? []

        guard !rawContents.isEmpty else {
            let reason: YouTubeQueueEmptyReason = (context.isPrivateListID || context.playlistID != nil)
                ? .privatePlaylistInBackground
                : .queueNotVisible
            return InnerTubeParsed(sourceKind: .publicPlaylist, playlistTitle: nil, items: [], emptyReason: reason)
        }

        let headerTitle = extractText((musicQueue?["header"] as? [String: Any])?["musicQueueHeaderRenderer"].flatMap { ($0 as? [String: Any])?["subtitle"] })
        let kind: YouTubeQueueSourceKind = context.isFixedPublicPlaylist ? .publicPlaylist : .suggestedRadio
        let rows = parsePlaylistPanelContents(
            rawContents,
            currentVideoID: context.videoID,
            currentIndex1Based: context.index,
            currentTitle: currentTitle,
            actionBuilder: actionBuilder
        )
        return InnerTubeParsed(
            sourceKind: kind,
            playlistTitle: headerTitle.isEmpty ? nil : headerTitle,
            items: rows,
            emptyReason: rows.isEmpty ? .empty : nil
        )
    }

    private struct RawPanelRow {
        let videoID: String?
        let title: String
        let artist: String
        let duration: TimeInterval
        let artworkURL: URL?
        let selected: Bool
        let index1Based: Int
    }

    private static func parsePlaylistPanelContents(
        _ rawContents: [[String: Any]],
        currentVideoID: String?,
        currentIndex1Based: Int?,
        currentTitle: String,
        actionBuilder: (String, Int?) -> YouTubeQueueAction
    ) -> [YouTubeQueueItem] {
        var parsed: [RawPanelRow] = []
        for (offset, entry) in rawContents.enumerated() {
            let renderer: [String: Any]?
            if let direct = entry["playlistPanelVideoRenderer"] as? [String: Any] {
                renderer = direct
            } else if let wrapper = entry["playlistPanelVideoWrapperRenderer"] as? [String: Any],
                      let primary = (wrapper["primaryRenderer"] as? [String: Any])?["playlistPanelVideoRenderer"] as? [String: Any] {
                renderer = primary
            } else {
                renderer = nil
            }
            guard let r = renderer else { continue }
            let title = extractText(r["title"]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            let rawVideoID = r["videoId"] as? String
            let videoID = rawVideoID.flatMap { YouTubeWatchContext.isValidVideoID($0) ? $0 : nil }
            let rawArtist = extractText(r["shortBylineText"]).isEmpty
                ? extractText(r["longBylineText"])
                : extractText(r["shortBylineText"])
            let artist = cleanByline(rawArtist)
            let duration = parseDuration(extractText(r["lengthText"]))
            let thumb = extractThumbnailURL(from: r["thumbnail"]) ?? videoID.flatMap(YouTubeWatchContext.thumbnailURL(forVideoID:))
            let selected = r["selected"] as? Bool == true
            parsed.append(RawPanelRow(
                videoID: videoID,
                title: title,
                artist: artist,
                duration: duration,
                artworkURL: thumb,
                selected: selected,
                index1Based: offset + 1
            ))
        }

        guard !parsed.isEmpty else { return [] }

        // Ưu tiên xác định bài hiện tại: selected == true -> videoID (+ index nếu trùng) -> tiêu đề chuẩn hóa.
        var currentPos: Int? = parsed.firstIndex(where: \.selected)
        if currentPos == nil, let currentVideoID {
            let matches = parsed.indices.filter { parsed[$0].videoID == currentVideoID }
            if matches.count == 1 {
                currentPos = matches.first
            } else if matches.count > 1, let targetIdx = currentIndex1Based {
                currentPos = matches.min { abs(parsed[$0].index1Based - targetIdx) < abs(parsed[$1].index1Based - targetIdx) }
            } else {
                currentPos = matches.first
            }
        }
        if currentPos == nil {
            let foldedCurrent = fold(currentTitle)
            if !foldedCurrent.isEmpty {
                currentPos = parsed.firstIndex { fold($0.title) == foldedCurrent }
            }
        }

        let startOffset = currentPos.map { $0 + 1 } ?? 0
        guard startOffset < parsed.count else { return [] }

        return parsed[startOffset...].prefix(maximumItems).enumerated().map { idx, row in
            let action = row.videoID.map { actionBuilder($0, row.index1Based) } ?? .none
            let stableID = "\(row.videoID ?? "row")-\(row.index1Based)-\(idx)"
            return YouTubeQueueItem(
                id: stableID,
                title: row.title,
                artist: row.artist,
                duration: row.duration,
                artworkURL: row.artworkURL,
                videoID: row.videoID,
                playlistIndex: row.index1Based,
                action: action
            )
        }
    }

    private static func parseSecondaryEntry(
        _ entry: [String: Any],
        seen: inout Set<String>,
        actionBuilder: (String, Int?) -> YouTubeQueueAction
    ) -> YouTubeQueueItem? {
        if let lockup = entry["lockupViewModel"] as? [String: Any] {
            guard let contentID = lockup["contentId"] as? String,
                  YouTubeWatchContext.isValidVideoID(contentID),
                  seen.insert(contentID).inserted else { return nil }
            let meta = (lockup["metadata"] as? [String: Any])?["lockupMetadataViewModel"] as? [String: Any]
            let title = ((meta?["title"] as? [String: Any])?["content"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }

            let rows = ((meta?["metadata"] as? [String: Any])?["contentMetadataViewModel"] as? [String: Any])?["metadataRows"] as? [[String: Any]] ?? []
            var artist = ""
            if let firstRow = rows.first,
               let parts = firstRow["metadataParts"] as? [[String: Any]],
               let firstText = (parts.first?["text"] as? [String: Any])?["content"] as? String {
                artist = firstText.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let thumb = YouTubeWatchContext.thumbnailURL(forVideoID: contentID)
            return YouTubeQueueItem(
                id: "next-\(contentID)",
                title: title,
                artist: artist,
                duration: 0,
                artworkURL: thumb,
                videoID: contentID,
                playlistIndex: nil,
                action: actionBuilder(contentID, nil)
            )
        }

        if let compact = entry["compactVideoRenderer"] as? [String: Any] {
            guard let videoID = compact["videoId"] as? String,
                  YouTubeWatchContext.isValidVideoID(videoID),
                  seen.insert(videoID).inserted else { return nil }
            let title = extractText(compact["title"]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            let artist = cleanByline(extractText(compact["shortBylineText"]).isEmpty
                ? extractText(compact["longBylineText"])
                : extractText(compact["shortBylineText"]))
            let duration = parseDuration(extractText(compact["lengthText"]))
            let thumb = extractThumbnailURL(from: compact["thumbnail"]) ?? YouTubeWatchContext.thumbnailURL(forVideoID: videoID)
            return YouTubeQueueItem(
                id: "next-\(videoID)",
                title: title,
                artist: artist,
                duration: duration,
                artworkURL: thumb,
                videoID: videoID,
                playlistIndex: nil,
                action: actionBuilder(videoID, nil)
            )
        }
        return nil
    }

    // MARK: - Accessibility DOM Parsers (Tier 1)

    /// Phân tích cây AX đã đọc từ `music.youtube.com` (`ytmusic-player-queue-item`).
    /// Trả về `nil` nếu trang không chứa hàng đợi khớp bài đang phát (tránh nhầm tab/drawer ẩn).
    static func parseAXYouTubeMusicQueue(
        entries: [YouTubeAXNodeEntry],
        currentTitle: String,
        currentArtist: String
    ) -> [YouTubeQueueItem]? {
        struct RawRow {
            var title: String
            var artist: String
            var duration: TimeInterval
            var imageURL: URL?
            var actionRef: Int
            var isSelected: Bool
        }

        let lookBehind = 10
        var rows: [RawRow] = []
        var lastImage: (index: Int, url: URL)?
        var buttons: [(index: Int, ref: Int, text: String)] = []
        var itemSelectedHint = false

        for (index, entry) in entries.enumerated() {
            if entry.role == "AXImage", YouTubeWatchContext.isTrustedArtworkURL(entry.url), let url = entry.url {
                lastImage = (index, url)
                continue
            }
            if entry.role == "AXButton" {
                let text = entry.label.isEmpty ? entry.text : entry.label
                buttons = buttons.suffix(lookBehind) + [(index, entry.ref, text)]
                continue
            }
            guard entry.hasClass("ytmusic-player-queue-item") else { continue }
            if entry.isSelected || entry.hasClass("selected") {
                itemSelectedHint = true
            }
            if entry.hasClass("song-title") {
                let title = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else { continue }
                let image = lastImage.flatMap { index - $0.index <= lookBehind ? $0.url : nil }
                let matchedButton = matchAXPlayButton(for: title, in: buttons, at: index, lookBehind: lookBehind)
                let selectedByButton = matchedButton.map { isPauseButtonLabel($0.text) } ?? false
                rows.append(RawRow(
                    title: title,
                    artist: "",
                    duration: 0,
                    imageURL: image,
                    actionRef: matchedButton?.ref ?? entry.ref,
                    isSelected: itemSelectedHint || entry.isSelected || entry.hasClass("selected") || selectedByButton
                ))
                itemSelectedHint = false
                lastImage = nil
                buttons = []
            } else if entry.hasClass("byline"), let last = rows.indices.last, rows[last].artist.isEmpty {
                rows[last].artist = cleanByline(entry.text)
            } else if entry.hasClass("duration"), let last = rows.indices.last, rows[last].duration == 0 {
                rows[last].duration = parseDuration(entry.text)
            }
        }

        guard !rows.isEmpty else { return nil }
        let foldedTitle = fold(currentTitle)
        let foldedArtist = fold(currentArtist)
        guard !foldedTitle.isEmpty else { return nil }

        // Khắc phục lỗi trùng tên bài: ưu tiên hàng đang được đánh dấu selected/playing,
        // tiếp theo mới tới khớp (title + artist), cuối cùng mới khớp title đơn lẻ.
        let playingIndex: Int? = rows.firstIndex(where: { $0.isSelected && fold($0.title) == foldedTitle })
            ?? rows.firstIndex(where: { $0.isSelected })
            ?? (!foldedArtist.isEmpty ? rows.firstIndex(where: { fold($0.title) == foldedTitle && fold($0.artist).contains(foldedArtist) }) : nil)
            ?? rows.firstIndex(where: { fold($0.title) == foldedTitle })

        guard let playingIndex else { return nil }
        guard playingIndex + 1 < rows.count else { return [] }

        return rows[(playingIndex + 1)...].prefix(maximumItems).enumerated().map { offset, row in
            YouTubeQueueItem(
                id: "ax-ytm-\(offset + 1)-\(row.actionRef)",
                title: row.title,
                artist: row.artist,
                duration: row.duration,
                artworkURL: row.imageURL,
                videoID: nil,
                playlistIndex: nil,
                action: .accessibility(ref: row.actionRef)
            )
        }
    }

    /// Phân tích cây AX từ `www.youtube.com` (ưu tiên playlist panel thật; fallback gợi ý `ytLockupMetadataViewModelTitle` cho video đơn).
    static func parseAXYouTubeWebQueue(
        entries: [YouTubeAXNodeEntry],
        pageContext: YouTubeWatchContext,
        currentTitle: String
    ) -> (sourceKind: YouTubeQueueSourceKind, items: [YouTubeQueueItem])? {
        struct PlaylistLinkRow {
            let videoID: String
            let title: String
            var artist: String
            var duration: TimeInterval
            let ref: Int
            let isSelected: Bool
            let index1Based: Int?
        }

        var playlistRows: [PlaylistLinkRow] = []
        var seenPlaylistRefs = Set<Int>()
        var pendingSelectedMarker = false

        for entry in entries {
            let trimmedText = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedText == "▶" || trimmedText == "►" {
                pendingSelectedMarker = true
            }
            if entry.role == "AXLink",
               let url = entry.url,
               let linkCtx = YouTubeWatchContext.parse(url: url),
               let videoID = linkCtx.videoID,
               let linkList = linkCtx.playlistID,
               (entry.domID == "wc-endpoint" || entry.hasClass("ytd-playlist-panel-video-renderer")
                || (pageContext.playlistID != nil && linkList == pageContext.playlistID)) {
                let rawTitle = (entry.text.isEmpty ? entry.label : entry.text).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !rawTitle.isEmpty, seenPlaylistRefs.insert(entry.ref).inserted else { continue }
                playlistRows.append(PlaylistLinkRow(
                    videoID: videoID,
                    title: rawTitle,
                    artist: "",
                    duration: 0,
                    ref: entry.ref,
                    isSelected: entry.isSelected || entry.hasClass("selected") || pendingSelectedMarker,
                    index1Based: linkCtx.index
                ))
                pendingSelectedMarker = false
            } else if let last = playlistRows.indices.last {
                if (entry.domID == "byline" || entry.hasClass("byline")) && playlistRows[last].artist.isEmpty && !trimmedText.isEmpty {
                    playlistRows[last].artist = cleanByline(trimmedText)
                } else if playlistRows[last].duration == 0 {
                    let parsedDur = parseDuration(trimmedText)
                    if parsedDur > 0 { playlistRows[last].duration = parsedDur }
                }
            }
        }

        if !playlistRows.isEmpty {
            let foldedCurrent = fold(currentTitle)
            let playingIdx = playlistRows.firstIndex(where: \.isSelected)
                ?? pageContext.videoID.flatMap { vid in
                    let matches = playlistRows.indices.filter { playlistRows[$0].videoID == vid }
                    if matches.count > 1, let idx = pageContext.index {
                        return matches.min { abs((playlistRows[$0].index1Based ?? 0) - idx) < abs((playlistRows[$1].index1Based ?? 0) - idx) }
                    }
                    return matches.first
                }
                ?? (!foldedCurrent.isEmpty ? playlistRows.firstIndex(where: { fold($0.title) == foldedCurrent }) : nil)

            if let playingIdx {
                guard playingIdx + 1 < playlistRows.count else { return (.liveAccessibility, []) }
                let items = playlistRows[(playingIdx + 1)...].prefix(maximumItems).enumerated().map { offset, row in
                    YouTubeQueueItem(
                        id: "ax-yt-\(row.videoID)-\(offset + 1)",
                        title: row.title,
                        artist: row.artist,
                        duration: row.duration,
                        artworkURL: YouTubeWatchContext.thumbnailURL(forVideoID: row.videoID),
                        videoID: row.videoID,
                        playlistIndex: row.index1Based,
                        action: .accessibility(ref: row.ref)
                    )
                }
                return (.liveAccessibility, items)
            }
        }

        // Nếu là video đơn (không có `list=`) và tab đang mở: đọc các thẻ gợi ý Up Next (`ytLockupMetadataViewModelTitle`).
        guard pageContext.playlistID == nil else { return nil }
        var suggested: [YouTubeQueueItem] = []
        var seenVideos = Set<String>()
        if let cur = pageContext.videoID { seenVideos.insert(cur) }

        for entry in entries {
            guard suggested.count < 15 else { break }
            guard entry.role == "AXLink",
                  entry.hasClass("ytLockupMetadataViewModelTitle") || entry.hasClass("ytd-compact-video-renderer"),
                  let url = entry.url,
                  let linkCtx = YouTubeWatchContext.parse(url: url),
                  let videoID = linkCtx.videoID,
                  seenVideos.insert(videoID).inserted else { continue }
            let title = (entry.label.isEmpty ? entry.text : entry.label).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            suggested.append(YouTubeQueueItem(
                id: "ax-next-\(videoID)",
                title: title,
                artist: "",
                duration: 0,
                artworkURL: YouTubeWatchContext.thumbnailURL(forVideoID: videoID),
                videoID: videoID,
                playlistIndex: nil,
                action: .accessibility(ref: entry.ref)
            ))
        }

        guard !suggested.isEmpty else { return nil }
        return (.suggestedRadio, suggested)
    }


    static func parsePearQueue(data: Data) -> [YouTubeQueueItem]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawItems = root["items"] as? [[String: Any]], !rawItems.isEmpty else { return nil }
        var rows: [(index0: Int, title: String, artist: String, duration: TimeInterval, artworkURL: URL?, videoID: String?, selected: Bool)] = []
        for (idx, item) in rawItems.enumerated() {
            let wrapper = item["playlistPanelVideoWrapperRenderer"] as? [String: Any]
            let renderer = (item["playlistPanelVideoRenderer"] as? [String: Any])
                ?? ((wrapper?["primaryRenderer"] as? [String: Any])?["playlistPanelVideoRenderer"] as? [String: Any])
            guard let r = renderer else { continue }
            let title = extractText(r["title"]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            let videoID = (r["videoId"] as? String).flatMap { YouTubeWatchContext.isValidVideoID($0) ? $0 : nil }
            let rawArtist = extractText(r["shortBylineText"]).isEmpty ? extractText(r["longBylineText"]) : extractText(r["shortBylineText"])
            let artist = cleanByline(rawArtist)
            let duration = parseDuration(extractText(r["lengthText"]))
            let thumb = extractThumbnailURL(from: r["thumbnail"]) ?? videoID.flatMap(YouTubeWatchContext.thumbnailURL(forVideoID:))
            rows.append((idx, title, artist, duration, thumb, videoID, r["selected"] as? Bool == true))
        }
        guard !rows.isEmpty else { return nil }
        let start = rows.firstIndex(where: \.selected).map { $0 + 1 } ?? 0
        guard start < rows.count else { return [] }
        return rows[start...].prefix(maximumItems).map { row in
            YouTubeQueueItem(
                id: "pear-\(row.index0)-\(row.videoID ?? "")",
                title: row.title,
                artist: row.artist,
                duration: row.duration,
                artworkURL: row.artworkURL,
                videoID: row.videoID,
                playlistIndex: row.index0 + 1,
                action: .pear(index: row.index0)
            )
        }
    }

    static func parseKasetQueue(data: Data) -> [YouTubeQueueItem]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tracks = root["tracks"] as? [[String: Any]], !tracks.isEmpty else { return nil }
        let current1Based = root["currentIndex"] as? Int ?? 0
        let startOffset = current1Based >= 1 ? current1Based : 0
        guard startOffset < tracks.count else { return [] }
        var items: [YouTubeQueueItem] = []
        for idx in startOffset..<min(tracks.count, startOffset + maximumItems) {
            let t = tracks[idx]
            let title = (t["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            let artist = (t["artist"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let duration = (t["duration"] as? Double).flatMap { $0.isFinite && $0 >= 0 ? $0 : nil } ?? 0
            let videoID = (t["videoId"] as? String).flatMap { YouTubeWatchContext.isValidVideoID($0) ? $0 : nil }
            let rawThumb = (t["artworkURL"] as? String).flatMap(URL.init(string:))
            let thumb = YouTubeWatchContext.isTrustedArtworkURL(rawThumb)
                ? rawThumb
                : videoID.flatMap(YouTubeWatchContext.thumbnailURL(forVideoID:))
            items.append(YouTubeQueueItem(
                id: "kaset-\(idx + 1)-\(videoID ?? "")",
                title: title,
                artist: artist,
                duration: duration,
                artworkURL: thumb,
                videoID: videoID,
                playlistIndex: idx + 1,
                action: .kaset(index: idx + 1)
            ))
        }
        return items
    }

    // MARK: - Helpers

    private static func matchAXPlayButton(
        for title: String,
        in buttons: [(index: Int, ref: Int, text: String)],
        at index: Int,
        lookBehind: Int
    ) -> (ref: Int, text: String)? {
        let target = fold(title)
        guard !target.isEmpty else { return nil }
        return buttons.last { entry in
            index - entry.index <= lookBehind && fold(entry.text).contains(target)
        }.map { ($0.ref, $0.text) }
    }

    private static func isPauseButtonLabel(_ label: String) -> Bool {
        let folded = fold(label)
        return folded.hasPrefix("pause ") || folded.hasPrefix("tam dung ")
    }

    private static func cleanByline(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if let first = trimmed.components(separatedBy: " • ").first?.trimmingCharacters(in: .whitespacesAndNewlines),
           !first.isEmpty {
            return first
        }
        return trimmed
    }

    private static func extractText(_ value: Any?) -> String {
        if let dict = value as? [String: Any] {
            if let simple = dict["simpleText"] as? String { return simple }
            if let content = dict["content"] as? String { return content }
            if let runs = dict["runs"] as? [[String: Any]] {
                return runs.compactMap { $0["text"] as? String }.joined()
            }
        }
        return value as? String ?? ""
    }

    private static func extractThumbnailURL(from value: Any?) -> URL? {
        guard let dict = value as? [String: Any],
              let list = dict["thumbnails"] as? [[String: Any]], !list.isEmpty else { return nil }
        let candidates: [(width: Int, url: URL)] = list.compactMap { entry in
            guard let raw = entry["url"] as? String,
                  let url = URL(string: raw.hasPrefix("//") ? "https:" + raw : raw),
                  YouTubeWatchContext.isTrustedArtworkURL(url) else { return nil }
            return (entry["width"] as? Int ?? 0, url)
        }
        // Chọn ảnh vuông/vừa đủ nét (ưu tiên <= 360px, lớn nhất trong nhóm nhỏ để tiết kiệm băng thông).
        let preferred = candidates.filter { $0.width > 0 && $0.width <= 360 }.max { $0.width < $1.width }
        return (preferred ?? candidates.first)?.url
    }

    // MARK: - Self-tests

    static func validateSelfTests() -> Bool {
        // 1. URL & bảo mật
        guard let plCtx = YouTubeWatchContext.parse(url: URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=PLMC9KNkIncKtPzgY-5rmhvj7fax8fdxoj&index=4")!),
              plCtx.site == .youtube, plCtx.videoID == "dQw4w9WgXcQ",
              plCtx.playlistID == "PLMC9KNkIncKtPzgY-5rmhvj7fax8fdxoj", plCtx.index == 4,
              plCtx.isFixedPublicPlaylist, !plCtx.isPrivateListID, !plCtx.isRadioOrMix else { return false }
        guard let destPL = plCtx.destinationURL(videoID: "yPYZpwSpKmA", index: 5),
              destPL.absoluteString == "https://www.youtube.com/watch?v=yPYZpwSpKmA&list=PLMC9KNkIncKtPzgY-5rmhvj7fax8fdxoj&index=5" else { return false }

        guard let lmCtx = YouTubeWatchContext.parse(url: URL(string: "https://music.youtube.com/watch?v=dQw4w9WgXcQ&list=LM")!),
              lmCtx.site == .youtubeMusic, lmCtx.isPrivateListID, !lmCtx.isFixedPublicPlaylist else { return false }
        guard let rdCtx = YouTubeWatchContext.parse(url: URL(string: "https://www.youtube.com/watch?v=MgKAgKTJuJw&list=RDmKa0v9JHWdE&index=27")!),
              rdCtx.isRadioOrMix, !rdCtx.isFixedPublicPlaylist,
              rdCtx.destinationURL(videoID: "kH8zrrhiMx4", index: 2)?.absoluteString == "https://www.youtube.com/watch?v=kH8zrrhiMx4&list=RDmKa0v9JHWdE" else { return false }
        guard YouTubeWatchContext.parse(url: URL(string: "https://evil.example/watch?v=dQw4w9WgXcQ")!) == nil else { return false }
        guard plCtx.destinationURL(videoID: "bad\"id", index: 1) == nil else { return false }
        guard YouTubeWatchContext.isTrustedArtworkURL(URL(string: "https://i.ytimg.com/vi/dQw4w9WgXcQ/mqdefault.jpg")),
              YouTubeWatchContext.isTrustedArtworkURL(URL(string: "https://lh3.googleusercontent.com/abc")),
              !YouTubeWatchContext.isTrustedArtworkURL(URL(string: "http://i.ytimg.com/vi/dQw4w9WgXcQ/mqdefault.jpg")),
              !YouTubeWatchContext.isTrustedArtworkURL(URL(string: "https://evil.com/x.jpg")) else { return false }

        // 2. Multi-tab matching với tiêu đề có ký tự |, emoji, tiếng Việt có dấu
        let sep = "\u{1F}"
        let rec = "\u{1E}"
        let listing = [
            "1\(sep)1\(sep)0\(sep)101\(sep)Ngàn Lần Xin Đừng Khóc | Official Lofi - YouTube\(sep)https://www.youtube.com/watch?v=MgKAgKTJuJw&list=RDmKa0v9JHWdE&index=27",
            "1\(sep)2\(sep)1\(sep)102\(sep)(2) TỔNG HỢP NHẠC DRILL 🔥 - YouTube\(sep)https://www.youtube.com/watch?v=rSYGfKyl_4A&list=RDrSYGfKyl_4A"
        ].joined(separator: rec)
        let parsedTabs = BrowserTabLocator.parseAppleScriptTabListing(listing, bundleID: "com.google.Chrome")
        guard parsedTabs.count == 2,
              let chosen = BrowserTabLocator.selectBestTab(from: parsedTabs, trackTitle: "Ngàn Lần Xin Đừng Khóc | Official Lofi", trackArtist: ""),
              chosen.tabIdentifier == "101", chosen.context.videoID == "MgKAgKTJuJw" else { return false }
        guard BrowserTabLocator.selectBestTab(
            from: [parsedTabs[0], parsedTabs[0]],
            trackTitle: "Ngàn Lần Xin Đừng Khóc | Official Lofi", trackArtist: ""
        ) == nil else { return false }
        guard matchesTabTitle("APT. - ROSÉ & Bruno Mars - YouTube Music", trackTitle: "APT.", trackArtist: "ROSÉ"),
              !matchesTabTitle("APT tour video - YouTube", trackTitle: "APT.", trackArtist: "ROSÉ") else { return false }

        // 3. InnerTube WEB playlist parsing + selected slicing
        let webPlaylistJSON = Data(#"""
        {
          "contents": {
            "twoColumnWatchNextResults": {
              "playlist": {
                "playlist": {
                  "title": "Pop Hits",
                  "contents": [
                    {"playlistPanelVideoRenderer": {"videoId": "aaaaaaaaaaa", "title": {"simpleText": "First"}, "shortBylineText": {"runs": [{"text": "Artist 1"}]}, "lengthText": {"simpleText": "3:10"}, "selected": false}},
                    {"playlistPanelVideoRenderer": {"videoId": "dQw4w9WgXcQ", "title": {"simpleText": "Current"}, "shortBylineText": {"runs": [{"text": "Rick"}]}, "lengthText": {"simpleText": "3:33"}, "selected": true}},
                    {"playlistPanelVideoRenderer": {"videoId": "yPYZpwSpKmA", "title": {"simpleText": "Together Forever"}, "shortBylineText": {"runs": [{"text": "Rick Astley"}]}, "lengthText": {"simpleText": "3:25"}, "selected": false}}
                  ]
                }
              }
            }
          }
        }
        """#.utf8)
        let plParsed = parseInnerTubeNext(data: webPlaylistJSON, context: plCtx, currentTitle: "Current") { vid, idx in
            .navigateTab(browserBundleID: "com.google.Chrome", tabIdentifier: "101", windowIndex: 1, tabIndex: 1,
                         expectedURL: URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")!,
                         destinationURL: plCtx.destinationURL(videoID: vid, index: idx)!)
        }
        guard plParsed.sourceKind == .publicPlaylist, plParsed.playlistTitle == "Pop Hits",
              plParsed.items.count == 1, plParsed.items[0].videoID == "yPYZpwSpKmA",
              plParsed.items[0].duration == 205, plParsed.items[0].canPlay else { return false }

        // 4. InnerTube WEB single-video autoplay hoisting + lockupViewModel
        let singleCtx = YouTubeWatchContext.parse(url: URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")!)!
        let singleJSON = Data(#"""
        {
          "contents": {
            "twoColumnWatchNextResults": {
              "autoplay": {"autoplay": {"sets": [{"autoplayVideo": {"watchEndpoint": {"videoId": "djV11Xbc914"}}}]}},
              "secondaryResults": {
                "secondaryResults": {
                  "results": [
                    {"lockupViewModel": {"contentId": "yPYZpwSpKmA", "metadata": {"lockupMetadataViewModel": {"title": {"content": "Other Song"}, "metadata": {"contentMetadataViewModel": {"metadataRows": [{"metadataParts": [{"text": {"content": "Channel A"}}]}]}}}}}},
                    {"lockupViewModel": {"contentId": "djV11Xbc914", "metadata": {"lockupMetadataViewModel": {"title": {"content": "Take On Me"}, "metadata": {"contentMetadataViewModel": {"metadataRows": [{"metadataParts": [{"text": {"content": "a-ha"}}]}]}}}}}}
                  ]
                }
              }
            }
          }
        }
        """#.utf8)
        let singleParsed = parseInnerTubeNext(data: singleJSON, context: singleCtx, currentTitle: "Never Gonna Give You Up") { _, _ in .none }
        guard singleParsed.sourceKind == .suggestedRadio, singleParsed.items.count == 2,
              singleParsed.items[0].videoID == "djV11Xbc914", singleParsed.items[0].artist == "a-ha" else { return false }

        // 5. InnerTube WEB_REMIX (YouTube Music wrapper + private LM empty)
        let ytmCtx = YouTubeWatchContext.parse(url: URL(string: "https://music.youtube.com/watch?v=dQw4w9WgXcQ&list=RDAMVMdQw4w9WgXcQ")!)!
        let ytmJSON = Data(#"""
        {
          "contents": {
            "singleColumnMusicWatchNextResultsRenderer": {
              "tabbedRenderer": {
                "watchNextTabbedResultsRenderer": {
                  "tabs": [{
                    "tabRenderer": {
                      "content": {
                        "musicQueueRenderer": {
                          "content": {
                            "playlistPanelRenderer": {
                              "contents": [
                                {"playlistPanelVideoRenderer": {"videoId": "dQw4w9WgXcQ", "title": {"runs": [{"text": "Now"}]}, "longBylineText": {"runs": [{"text": "Rick • Album • 1987"}]}, "selected": true}},
                                {"playlistPanelVideoWrapperRenderer": {"primaryRenderer": {"playlistPanelVideoRenderer": {"videoId": "yPYZpwSpKmA", "title": {"runs": [{"text": "Next Track"}]}, "longBylineText": {"runs": [{"text": "Artist B • Single • 2025"}]}, "lengthText": {"runs": [{"text": "4:05"}]}, "selected": false}}}}
                              ]
                            }
                          }
                        }
                      }
                    }
                  }]
                }
              }
            }
          }
        }
        """#.utf8)
        let ytmParsed = parseInnerTubeNext(data: ytmJSON, context: ytmCtx, currentTitle: "Now") { _, _ in .none }
        guard ytmParsed.sourceKind == .suggestedRadio, ytmParsed.items.count == 1,
              ytmParsed.items[0].title == "Next Track", ytmParsed.items[0].artist == "Artist B",
              ytmParsed.items[0].duration == 245 else { return false }

        let ytmPrivateEmpty = Data(#"{"contents":{"singleColumnMusicWatchNextResultsRenderer":{"tabbedRenderer":{"watchNextTabbedResultsRenderer":{"tabs":[{"tabRenderer":{"content":{"musicQueueRenderer":{"content":{"playlistPanelRenderer":{"contents":[]}}}}}}]}}}}}"#.utf8)
        let lmParsed = parseInnerTubeNext(data: ytmPrivateEmpty, context: lmCtx, currentTitle: "Liked") { _, _ in .none }
        guard lmParsed.items.isEmpty, lmParsed.emptyReason == .privatePlaylistInBackground else { return false }

        // 6. AX YouTube Music parser: sửa lỗi trùng tên bài bằng nhận diện hàng đang phát (Pause / selected)
        let ytmScope: Set<String> = ["ytmusic-player-queue-item", "style-scope"]
        let axYTMEntries: [YouTubeAXNodeEntry] = [
            .init(role: "AXButton", domID: "", classes: [], text: "Play Same Song", label: "Play Same Song", url: nil, isSelected: false, ref: 1),
            .init(role: "AXGroup", domID: "", classes: ytmScope.union(["song-title"]), text: "Same Song", label: "", url: nil, isSelected: false, ref: 2),
            .init(role: "AXGroup", domID: "", classes: ytmScope.union(["byline"]), text: "Artist A", label: "", url: nil, isSelected: false, ref: 3),
            .init(role: "AXButton", domID: "", classes: [], text: "Pause Same Song", label: "Pause Same Song", url: nil, isSelected: false, ref: 11),
            .init(role: "AXGroup", domID: "", classes: ytmScope.union(["song-title"]), text: "Same Song", label: "", url: nil, isSelected: false, ref: 12),
            .init(role: "AXGroup", domID: "", classes: ytmScope.union(["byline"]), text: "Artist A", label: "", url: nil, isSelected: false, ref: 13),
            .init(role: "AXImage", domID: "", classes: [], text: "", label: "", url: URL(string: "https://lh3.googleusercontent.com/cover"), isSelected: false, ref: 20),
            .init(role: "AXButton", domID: "", classes: [], text: "Play Real Next", label: "Play Real Next", url: nil, isSelected: false, ref: 21),
            .init(role: "AXGroup", domID: "", classes: ytmScope.union(["song-title"]), text: "Real Next", label: "", url: nil, isSelected: false, ref: 22),
            .init(role: "AXGroup", domID: "", classes: ytmScope.union(["byline"]), text: "Artist C • Album", label: "", url: nil, isSelected: false, ref: 23),
            .init(role: "AXGroup", domID: "", classes: ytmScope.union(["duration"]), text: "2:50", label: "", url: nil, isSelected: false, ref: 24)
        ]
        guard let axYTM = parseAXYouTubeMusicQueue(entries: axYTMEntries, currentTitle: "Same Song", currentArtist: "Artist A"),
              axYTM.count == 1, axYTM[0].title == "Real Next", axYTM[0].artist == "Artist C",
              axYTM[0].duration == 170, axYTM[0].action == .accessibility(ref: 21) else { return false }

        // 7. AX YouTube Web playlist panel + single video lockup
        let axYTEntries: [YouTubeAXNodeEntry] = [
            .init(role: "AXStaticText", domID: "", classes: [], text: "▶", label: "", url: nil, isSelected: false, ref: 1),
            .init(role: "AXLink", domID: "wc-endpoint", classes: ["ytd-playlist-panel-video-renderer"], text: "Current Vid", label: "Current Vid",
                  url: URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=PLMC9KNkIncKtPzgY-5rmhvj7fax8fdxoj&index=1"), isSelected: false, ref: 2),
            .init(role: "AXLink", domID: "wc-endpoint", classes: ["ytd-playlist-panel-video-renderer"], text: "Next Vid", label: "Next Vid",
                  url: URL(string: "https://www.youtube.com/watch?v=yPYZpwSpKmA&list=PLMC9KNkIncKtPzgY-5rmhvj7fax8fdxoj&index=2"), isSelected: false, ref: 3),
            .init(role: "AXStaticText", domID: "byline", classes: [], text: "Channel X", label: "", url: nil, isSelected: false, ref: 4),
            .init(role: "AXStaticText", domID: "", classes: [], text: "5:02", label: "", url: nil, isSelected: false, ref: 5)
        ]
        guard let axYT = parseAXYouTubeWebQueue(entries: axYTEntries, pageContext: plCtx, currentTitle: "Current Vid"),
              axYT.sourceKind == .liveAccessibility, axYT.items.count == 1,
              axYT.items[0].videoID == "yPYZpwSpKmA", axYT.items[0].artist == "Channel X",
              axYT.items[0].duration == 302, axYT.items[0].action == .accessibility(ref: 3) else { return false }

        let pearJSON = Data(#"{"items":[{"playlistPanelVideoRenderer":{"videoId":"dQw4w9WgXcQ","title":{"runs":[{"text":"Playing"}]},"selected":true}},{"playlistPanelVideoRenderer":{"videoId":"yPYZpwSpKmA","title":{"runs":[{"text":"Up Next Pear"}]},"shortBylineText":{"runs":[{"text":"Artist P"}]},"lengthText":{"runs":[{"text":"3:00"}]},"selected":false}}]}"#.utf8)
        let kasetJSON = Data(#"{"currentIndex":1,"tracks":[{"name":"Playing","artist":"A","duration":180,"videoId":"dQw4w9WgXcQ"},{"name":"Up Next Kaset","artist":"Artist K","duration":210,"videoId":"yPYZpwSpKmA"}]}"#.utf8)
        guard let pearItems = parsePearQueue(data: pearJSON), pearItems.count == 1, pearItems[0].action == .pear(index: 1),
              let kasetItems = parseKasetQueue(data: kasetJSON), kasetItems.count == 1, kasetItems[0].action == .kaset(index: 2) else { return false }
        guard YouTubeCandidateFamily.classify(bundleID: "com.google.Chrome") != nil,
              YouTubeCandidateFamily.classify(bundleID: "com.apple.Safari") != nil,
              YouTubeCandidateFamily.classify(bundleID: "com.apple.Safari.WebApp.12345") != nil,
              YouTubeCandidateFamily.classify(bundleID: "app.zen-browser.zen") != nil,
              YouTubeCandidateFamily.classify(bundleID: "com.spotify.client") == nil,
              YouTubeCandidateFamily.classify(bundleID: "com.apple.Music") == nil else { return false }

        return true
    }
}
