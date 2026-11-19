import AppKit
import ApplicationServices
import Foundation
import ImageIO

/// Định danh nguồn phát tại thời điểm đọc danh sách chờ, chống PID reuse và kết quả cũ ghi đè.
struct YouTubeQueueTarget: Equatable, Sendable {
    let bundleID: String
    let pid: Int32
    let launched: Date
    let title: String
    let artist: String
    let family: YouTubeCandidateFamily

    @MainActor
    init?(_ track: NowPlayingTrack) {
        guard !track.title.isEmpty,
              let family = YouTubeCandidateFamily.classify(bundleID: track.bundleID) else { return nil }
        let app: NSRunningApplication?
        if track.pid > 0, let exact = NSRunningApplication(processIdentifier: Int32(track.pid)),
           exact.bundleIdentifier?.caseInsensitiveCompare(track.bundleID) == .orderedSame {
            app = exact
        } else {
            app = NSRunningApplication.runningApplications(withBundleIdentifier: track.bundleID).first
        }
        guard let app, let launched = app.launchDate, !app.isTerminated else { return nil }
        self.bundleID = track.bundleID
        self.pid = app.processIdentifier
        self.launched = launched
        self.title = track.title
        self.artist = track.artist
        self.family = family
    }

    var alive: Bool {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return false }
        return !app.isTerminated
            && app.bundleIdentifier?.caseInsensitiveCompare(bundleID) == .orderedSame
            && app.launchDate == launched
    }
}

/// Quản lý trạng thái và vòng đời on-demand cho danh sách chờ YouTube / YouTube Music trên Island.
@MainActor
final class YouTubeQueueService: ObservableObject {
    static let shared = YouTubeQueueService()

    @Published private(set) var snapshot: YouTubeQueueSnapshot?
    @Published private(set) var thumbnails: [URL: NSImage] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var isActionPending = false
    @Published private(set) var actionFailed = false

    private let worker = YouTubeQueueWorker()
    private var isVisible = false
    private var currentTarget: YouTubeQueueTarget?
    private var generation = UUID()
    private var actionGeneration = UUID()
    private var loadTask: Task<Void, Never>?
    private var actionTask: Task<Void, Never>?
    private var refreshTimer: Timer?
    private var imageTasks: [URL: Task<Void, Never>] = [:]

    private init() {}

    /// Kiểm tra nguồn đang phát có thuộc phạm vi trình duyệt/app YouTube được hỗ trợ hay không.
    static func isCandidateSource(_ track: NowPlayingTrack?) -> Bool {
        guard let track, !track.title.isEmpty else { return false }
        return YouTubeCandidateFamily.classify(bundleID: track.bundleID) != nil
    }

    /// Nạp sẵn danh sách chờ ngay khi người dùng mở rộng Dynamic Island (trước khi bấm nút Up Next).
    /// Nếu dữ liệu của đúng bài hiện tại đã có sẵn hoặc đang tải thì giữ nguyên, không tải lại.
    func preload(track: NowPlayingTrack?) {
        guard Self.isCandidateSource(track),
              let nextTarget = track.flatMap(YouTubeQueueTarget.init) else {
            clearCacheAndTasks()
            return
        }
        if nextTarget == currentTarget {
            if isLoading { return }
            if snapshot != nil { return }
        }
        let sameApp = nextTarget.bundleID == currentTarget?.bundleID && nextTarget.pid == currentTarget?.pid
        currentTarget = nextTarget
        actionFailed = false
        if !sameApp { snapshot = nil }
        reload(keepExistingWhileLoading: sameApp)
    }

    /// Bật/tắt trạng thái hiển thị bảng popover Up Next trên Island.
    /// Khi đóng popover, giữ nguyên dữ liệu đã nạp của bài hiện tại để lần bấm tiếp theo mở tức thì (0 ms).
    func setVisible(_ visible: Bool, track: NowPlayingTrack?) {
        isVisible = visible
        if !visible {
            stopLivePollingOnly()
            return
        }
        guard let nextTarget = track.flatMap(YouTubeQueueTarget.init) else {
            clearCacheAndTasks()
            snapshot = YouTubeQueueSnapshot(
                sourceKind: .publicPlaylist,
                site: .youtube,
                playlistTitle: nil,
                items: [],
                emptyReason: .notYouTubeSource
            )
            return
        }
        if nextTarget == currentTarget {
            if isLoading { return }
            if let snapshot, snapshot.emptyReason == nil {
                loadThumbnails(for: snapshot.items)
                reload(keepExistingWhileLoading: true, bypassCache: true)
                return
            }
        }
        updateTrack(track, forceReload: true)
    }

    /// Cập nhật bài đang phát khi Island đang mở rộng hoặc popover Up Next đang hiển thị.
    func updateTrack(_ track: NowPlayingTrack?, forceReload: Bool = false) {
        guard Self.isCandidateSource(track) else {
            clearCacheAndTasks()
            return
        }
        let nextTarget = track.flatMap(YouTubeQueueTarget.init)
        guard forceReload || nextTarget != currentTarget else { return }
        let sameApp = nextTarget?.bundleID == currentTarget?.bundleID && nextTarget?.pid == currentTarget?.pid
        currentTarget = nextTarget
        actionFailed = false
        isActionPending = false
        actionTask?.cancel()
        actionTask = nil
        if !sameApp { snapshot = nil }
        reload(keepExistingWhileLoading: sameApp)
    }

    /// Làm mới danh sách chờ theo thao tác thủ công của người dùng.
    func refresh() {
        guard isVisible, !isActionPending else { return }
        actionFailed = false
        reload(keepExistingWhileLoading: true, bypassCache: true)
    }

    /// Phát một bài trong danh sách chờ (ưu tiên in-place qua AX/Desktop; fallback điều hướng tab qua Apple Events).
    func play(_ item: YouTubeQueueItem) {
        guard isVisible, !isLoading, !isActionPending, item.canPlay,
              snapshot?.items.contains(item) == true, let target = currentTarget else { return }
        isActionPending = true
        actionFailed = false
        let requestGeneration = generation
        actionGeneration = UUID()
        let actionID = actionGeneration
        actionTask?.cancel()
        actionTask = Task { [weak self, worker] in
            let ok = await worker.perform(action: item.action, target: target, generation: requestGeneration)
            guard !Task.isCancelled, let self, self.actionGeneration == actionID else { return }
            self.isActionPending = false
            guard self.generation == requestGeneration, self.isVisible else { return }
            self.actionFailed = !ok
            if ok {
                MusicService.shared.refreshNowPlaying()
                try? await Task.sleep(for: .milliseconds(900))
                guard !Task.isCancelled, self.generation == requestGeneration, self.isVisible else { return }
                self.reload(keepExistingWhileLoading: true, bypassCache: true)
            }
        }
    }

    private func reload(keepExistingWhileLoading: Bool, bypassCache: Bool = false) {
        actionGeneration = UUID()
        actionTask?.cancel()
        actionTask = nil
        isActionPending = false
        loadTask?.cancel()
        loadTask = nil
        refreshTimer?.invalidate()
        refreshTimer = nil
        generation = UUID()
        let requestGeneration = generation

        guard let target = currentTarget else {
            snapshot = YouTubeQueueSnapshot(
                sourceKind: .publicPlaylist,
                site: .youtube,
                playlistTitle: nil,
                items: [],
                emptyReason: .notYouTubeSource
            )
            isLoading = false
            trimThumbnails()
            return
        }

        if !keepExistingWhileLoading { snapshot = nil }
        isLoading = true
        let language = L10n.shared.language == .vi ? "vi" : "en"

        loadTask = Task { [weak self, worker] in
            let result = await worker.load(
                target: target,
                generation: requestGeneration,
                language: language,
                bypassCache: bypassCache
            )
            guard !Task.isCancelled, let self, self.generation == requestGeneration else { return }
            self.isLoading = false
            self.snapshot = result
            self.loadThumbnails(for: result.items)
            if self.isVisible {
                self.scheduleLiveRefreshIfNeeded(for: result)
            }
        }
    }

    private func scheduleLiveRefreshIfNeeded(for result: YouTubeQueueSnapshot) {
        refreshTimer?.invalidate()
        refreshTimer = nil
        guard isVisible else { return }
        // Chỉ tự làm mới nhẹ khi đang đọc live DOM/app desktop; InnerTube dùng cache + nút làm mới.
        guard result.sourceKind == .liveAccessibility || result.sourceKind == .desktopApp else { return }
        let timer = Timer(timeInterval: 6.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isVisible, !self.isLoading, !self.isActionPending else { return }
                self.reload(keepExistingWhileLoading: true)
            }
        }
        timer.tolerance = 1.5
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    /// Dừng timer làm mới định kỳ khi đóng popover nhưng giữ lại dữ liệu & ảnh thu nhỏ đã nạp cho bài hiện tại.
    private func stopLivePollingOnly() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        actionTask?.cancel()
        actionTask = nil
        isActionPending = false
        actionFailed = false
    }

    private func clearCacheAndTasks() {
        generation = UUID()
        loadTask?.cancel()
        loadTask = nil
        actionTask?.cancel()
        actionTask = nil
        refreshTimer?.invalidate()
        refreshTimer = nil
        for task in imageTasks.values { task.cancel() }
        imageTasks.removeAll()
        thumbnails.removeAll()
        snapshot = nil
        currentTarget = nil
        isLoading = false
        isActionPending = false
        actionFailed = false
        Task { [worker] in await worker.clearTransientElements() }
    }

    // MARK: - Thumbnails (HTTPS trusted YouTube hosts only, bounded size)

    private func loadThumbnails(for items: [YouTubeQueueItem]) {
        let wanted = Set(items.compactMap(\.artworkURL))
        trimThumbnails(keeping: wanted)
        for url in wanted where thumbnails[url] == nil && imageTasks[url] == nil {
            guard YouTubeWatchContext.isTrustedArtworkURL(url) else { continue }
            imageTasks[url] = Task { [weak self, worker] in
                let cgImage = await worker.downloadThumbnail(url: url)
                guard !Task.isCancelled, let self else { return }
                self.imageTasks[url] = nil
                guard let cgImage,
                      self.snapshot?.items.contains(where: { $0.artworkURL == url }) == true else { return }
                self.thumbnails[url] = NSImage(cgImage: cgImage, size: NSSize(width: 72, height: 72))
            }
        }
    }

    private func trimThumbnails(keeping wanted: Set<URL> = []) {
        for (url, task) in imageTasks where !wanted.contains(url) {
            task.cancel()
            imageTasks[url] = nil
        }
        thumbnails = thumbnails.filter { wanted.contains($0.key) }
    }
}

// MARK: - Background Worker (AXUIElement isolated, ephemeral networking)

private actor YouTubeQueueWorker {
    private static let maxAXNodes = 8_000
    private static let axDeadlineSeconds: TimeInterval = 1.8
    private static let maxResponseBytes = 4_194_304
    private static let maxThumbnailBytes = 524_288
    private static let maxCacheEntries = 16
    private static let cacheTTL: TimeInterval = 600

    private struct CacheKey: Hashable {
        let site: YouTubeSite
        let videoID: String
        let playlistID: String?
        let index: Int?
        let language: String
    }

    private struct CacheEntry {
        let expiresAt: Date
        let data: Data
    }

    private var capturedElements: [AXUIElement] = []
    private var capturedGeneration: UUID?
    private var capturedPID: Int32 = 0
    private var capturedWebArea: AXUIElement?
    private var capturedPageURL: URL?
    private var innerTubeCache: [CacheKey: CacheEntry] = [:]
    private var innerTubeCacheOrder: [CacheKey] = []

    private let redirectBlocker = YouTubeRedirectBlocker()
    private lazy var networkSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 10
        config.httpMaximumConnectionsPerHost = 2
        config.urlCache = nil
        config.urlCredentialStorage = nil
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        return URLSession(configuration: config, delegate: redirectBlocker, delegateQueue: nil)
    }()

    func clearTransientElements() {
        capturedElements.removeAll(keepingCapacity: false)
        capturedGeneration = nil
        capturedPID = 0
        capturedWebArea = nil
        capturedPageURL = nil
    }

    func load(
        target: YouTubeQueueTarget,
        generation: UUID,
        language: String,
        bypassCache: Bool
    ) async -> YouTubeQueueSnapshot {
        clearTransientElements()
        guard !Task.isCancelled, target.alive else {
            return YouTubeQueueSnapshot(sourceKind: .publicPlaylist, site: .youtube, playlistTitle: nil, items: [], emptyReason: .queueNotVisible)
        }

        // Bước 0: App desktop YouTube Music (Kaset / Pear Desktop) — queue thật 100%, không cần trình duyệt.
        switch target.family {
        case .kaset(let bundleID):
            return loadKasetQueue(bundleID: bundleID)
        case .pearDesktop:
            return await loadPearDesktopQueue()
        default:
            break
        }

        // Đọc trực tiếp cây AX của tab đang hiển thị (không bật AXEnhancedUserInterface).
        var activeAXContext: YouTubeWatchContext?
        if AXIsProcessTrusted() {
            let axOutcome = readLiveAXQueue(target: target, generation: generation)
            activeAXContext = axOutcome.pageContext
            if let snapshot = axOutcome.snapshot {
                return snapshot
            }
        }

        guard !Task.isCancelled, target.alive else {
            return YouTubeQueueSnapshot(sourceKind: .publicPlaylist, site: .youtube, playlistTitle: nil, items: [], emptyReason: .queueNotVisible)
        }

        // Đọc URL tab (kể cả tab nền, 0 extension, 0 bật JavaScript) + InnerTube `/youtubei/v1/next`.
        let located = BrowserTabLocator.locateTab(
            family: target.family,
            trackTitle: target.title,
            trackArtist: target.artist
        )

        var resolvedContext: YouTubeWatchContext?
        var resolvedTab: BrowserYouTubeTab?

        switch located {
        case .found(let tab):
            resolvedTab = tab
            resolvedContext = tab.context
        case .automationDenied:
            // Nếu có sẵn URL từ active AXWebArea thì vẫn dùng được dù Automation bị từ chối.
            if let activeAXContext {
                resolvedContext = activeAXContext
            } else {
                return YouTubeQueueSnapshot(
                    sourceKind: .publicPlaylist,
                    site: .youtube,
                    playlistTitle: nil,
                    items: [],
                    emptyReason: .automationDenied
                )
            }
        case .notFound:
            if let activeAXContext {
                resolvedContext = activeAXContext
            } else {
                let reason: YouTubeQueueEmptyReason
                if case .safariWebApp = target.family, !AXIsProcessTrusted() {
                    reason = .accessibilityRequired
                } else {
                    reason = .notYouTubeSource
                }
                return YouTubeQueueSnapshot(
                    sourceKind: .publicPlaylist,
                    site: .youtube,
                    playlistTitle: nil,
                    items: [],
                    emptyReason: reason
                )
            }
        }

        guard let context = resolvedContext else {
            return YouTubeQueueSnapshot(sourceKind: .publicPlaylist, site: .youtube, playlistTitle: nil, items: [], emptyReason: .notYouTubeSource)
        }

        if context.isPrivateListID {
            return YouTubeQueueSnapshot(
                sourceKind: .publicPlaylist,
                site: context.site,
                playlistTitle: nil,
                items: [],
                emptyReason: .privatePlaylistInBackground
            )
        }

        guard let videoID = context.videoID else {
            return YouTubeQueueSnapshot(
                sourceKind: .publicPlaylist,
                site: context.site,
                playlistTitle: nil,
                items: [],
                emptyReason: .queueNotVisible
            )
        }

        guard let responseData = await fetchInnerTubeNext(
            context: context,
            videoID: videoID,
            language: language,
            bypassCache: bypassCache
        ) else {
            return YouTubeQueueSnapshot(
                sourceKind: .publicPlaylist,
                site: context.site,
                playlistTitle: nil,
                items: [],
                emptyReason: .networkFailed
            )
        }

        let tabForAction = resolvedTab
        let canNavigate = target.family.supportsAppleScriptNavigation && tabForAction != nil
        let parsed = YouTubeQueueParser.parseInnerTubeNext(
            data: responseData,
            context: context,
            currentTitle: target.title
        ) { nextVideoID, nextIndex in
            guard canNavigate, let tab = tabForAction,
                  let destURL = context.destinationURL(videoID: nextVideoID, index: nextIndex) else {
                return .none
            }
            return .navigateTab(
                browserBundleID: tab.browserBundleID,
                tabIdentifier: tab.tabIdentifier,
                windowIndex: tab.windowIndex,
                tabIndex: tab.tabIndex,
                expectedURL: tab.url,
                destinationURL: destURL
            )
        }

        return YouTubeQueueSnapshot(
            sourceKind: parsed.sourceKind,
            site: context.site,
            playlistTitle: parsed.playlistTitle,
            items: parsed.items,
            emptyReason: parsed.emptyReason
        )
    }

    func perform(action: YouTubeQueueAction, target: YouTubeQueueTarget, generation: UUID) async -> Bool {
        guard !Task.isCancelled, target.alive else { return false }
        switch action {
        case .accessibility(let ref):
            guard capturedGeneration == generation,
                  capturedPID == target.pid,
                  let area = capturedWebArea,
                  capturedElements.indices.contains(ref) else { return false }
            let areaTitle = axValue(area, kAXTitleAttribute) as? String
            let areaDescription = axValue(area, kAXDescriptionAttribute) as? String
            let title = areaTitle ?? areaDescription ?? ""
            guard YouTubeQueueParser.matchesTabTitle(title, trackTitle: target.title, trackArtist: target.artist),
                  (axValue(area, kAXURLAttribute) as? URL) == capturedPageURL else { return false }
            return pressAXElement(capturedElements[ref], target: target)
        case .navigateTab(let bundleID, let tabIdentifier, let windowIndex, let tabIndex, let expectedURL, let destinationURL):
            return BrowserTabLocator.navigateTab(
                bundleID: bundleID,
                tabIdentifier: tabIdentifier,
                windowIndex: windowIndex,
                tabIndex: tabIndex,
                expectedURL: expectedURL,
                destinationURL: destinationURL
            )
        case .kaset(let index):
            guard index >= 1 else { return false }
            let script = """
            with timeout of 2 seconds
                tell application id "com.sertacozercan.Kaset"
                    play track at index \(index)
                end tell
            end timeout
            """
            return BrowserTabLocator.runAppleScript(script, timeout: 2.5).exitCode == 0
        case .pear(let index):
            guard index >= 0 else { return false }
            return await selectPearQueueIndex(index)
        case .none:
            return false
        }
    }

    func downloadThumbnail(url: URL) async -> CGImage? {
        guard YouTubeWatchContext.isTrustedArtworkURL(url) else { return nil }
        guard let data = await downloadBounded(url: url, limit: Self.maxThumbnailBytes) else { return nil }
        return Self.squareThumbnail(from: data, pixels: 72)
    }

    // MARK: - Tier 1: Accessibility Tree Reader

    private func readLiveAXQueue(
        target: YouTubeQueueTarget,
        generation: UUID
    ) -> (pageContext: YouTubeWatchContext?, snapshot: YouTubeQueueSnapshot?) {
        let appElement = AXUIElementCreateApplication(target.pid)
        AXUIElementSetMessagingTimeout(appElement, 0.4)

        let trustsSafariWebApp = safariWebAppSite(bundleID: target.bundleID)
        let webAreas = findWebAreas(in: appElement)
        guard !webAreas.isEmpty else { return (nil, nil) }

        var matchedArea: (element: AXUIElement, context: YouTubeWatchContext)?

        for area in webAreas {
            guard !Task.isCancelled, target.alive else { return (nil, nil) }
            let url = axValue(area, kAXURLAttribute) as? URL
            let areaTitle: String
            if let titleAttr = axValue(area, kAXTitleAttribute) as? String, !titleAttr.isEmpty {
                areaTitle = titleAttr
            } else if let descAttr = axValue(area, kAXDescriptionAttribute) as? String {
                areaTitle = descAttr
            } else {
                areaTitle = ""
            }

            let context: YouTubeWatchContext?
            if let url, let parsed = YouTubeWatchContext.parse(url: url) {
                context = parsed
            } else if url == nil, let site = trustsSafariWebApp {
                context = YouTubeWatchContext(site: site, videoID: nil, playlistID: nil, index: nil)
            } else {
                context = nil
            }
            guard let context else { continue }

            if YouTubeQueueParser.matchesTabTitle(areaTitle, trackTitle: target.title, trackArtist: target.artist) {
                // Nhiều cửa sổ cùng tiêu đề không đủ để xác định phiên đang phát.
                guard matchedArea == nil else { return (nil, nil) }
                matchedArea = (area, context)
            }
        }

        guard let chosen = matchedArea else { return (nil, nil) }
        capturedWebArea = chosen.element
        capturedPageURL = axValue(chosen.element, kAXURLAttribute) as? URL

        var elements: [AXUIElement] = []
        var entries: [YouTubeAXNodeEntry] = []
        walkAXWebArea(chosen.element, elements: &elements, entries: &entries)

        guard !Task.isCancelled, target.alive else { return (chosen.context, nil) }

        switch chosen.context.site {
        case .youtubeMusic:
            if let rows = YouTubeQueueParser.parseAXYouTubeMusicQueue(
                entries: entries,
                currentTitle: target.title,
                currentArtist: target.artist
            ) {
                capturedElements = elements
                capturedGeneration = generation
                capturedPID = target.pid
                return (
                    chosen.context,
                    YouTubeQueueSnapshot(
                        sourceKind: .liveAccessibility,
                        site: .youtubeMusic,
                        playlistTitle: nil,
                        items: rows,
                        emptyReason: rows.isEmpty ? .empty : nil
                    )
                )
            }
        case .youtube:
            if let parsed = YouTubeQueueParser.parseAXYouTubeWebQueue(
                entries: entries,
                pageContext: chosen.context,
                currentTitle: target.title
            ) {
                capturedElements = elements
                capturedGeneration = generation
                capturedPID = target.pid
                return (
                    chosen.context,
                    YouTubeQueueSnapshot(
                        sourceKind: parsed.sourceKind,
                        site: .youtube,
                        playlistTitle: nil,
                        items: parsed.items,
                        emptyReason: parsed.items.isEmpty ? .empty : nil
                    )
                )
            }
        }

        return (chosen.context, nil)
    }

    private func findWebAreas(in appElement: AXUIElement) -> [AXUIElement] {
        guard let windows = axValue(appElement, kAXWindowsAttribute) as? [AXUIElement] else { return [] }
        let deadline = ProcessInfo.processInfo.systemUptime + Self.axDeadlineSeconds
        var found: [AXUIElement] = []
        for window in windows.prefix(4) {
            var level = [window]
            var visited = 0
            var foundInWindow = false
            for _ in 0..<10 where !level.isEmpty && visited < 180 && !foundInWindow {
                var next: [AXUIElement] = []
                for el in level {
                    guard !Task.isCancelled, ProcessInfo.processInfo.systemUptime < deadline,
                          visited < 180 else { return [] }
                    visited += 1
                    let role = axValue(el, kAXRoleAttribute) as? String ?? ""
                    if role == kAXMenuBarRole { continue }
                    if role == "AXWebArea" {
                        found.append(el)
                        foundInWindow = true
                        break
                    }
                    if let children = axValue(el, kAXChildrenAttribute) as? [AXUIElement] {
                        next.append(contentsOf: children)
                    }
                }
                level = next
            }
        }
        return found
    }

    private static let walkAttributeNames: [String] = [
        kAXRoleAttribute,
        kAXChildrenAttribute,
        "AXDOMIdentifier",
        "AXDOMClassList",
        kAXValueAttribute,
        kAXTitleAttribute,
        kAXDescriptionAttribute,
        kAXURLAttribute,
        kAXSelectedAttribute
    ]

    private func walkAXWebArea(
        _ root: AXUIElement,
        elements: inout [AXUIElement],
        entries: inout [YouTubeAXNodeEntry]
    ) {
        let walkAttrs = Self.walkAttributeNames as CFArray
        var budget = Self.maxAXNodes
        let deadline = ProcessInfo.processInfo.systemUptime + Self.axDeadlineSeconds
        var stop = false

        @discardableResult
        func visit(_ element: AXUIElement, depth: Int) -> String {
            guard !stop, !Task.isCancelled else { return "" }
            guard budget > 0, depth < 90,
                  ProcessInfo.processInfo.systemUptime < deadline else {
                stop = true
                return ""
            }
            budget -= 1
            var raw: CFArray?
            guard AXUIElementCopyMultipleAttributeValues(element, walkAttrs, [], &raw) == .success,
                  let values = raw as? [AnyObject], values.count == 9 else { return "" }

            func item(_ index: Int) -> AnyObject? {
                let value = values[index]
                if CFGetTypeID(value) == AXValueGetTypeID(),
                   AXValueGetType(value as! AXValue) == .axError {
                    return nil
                }
                return value
            }

            let role = item(0) as? String ?? ""
            var inner = ""
            if let children = item(1) as? [AXUIElement] {
                for child in children {
                    let piece = visit(child, depth: depth + 1)
                    if !piece.isEmpty {
                        inner = inner.isEmpty ? piece : (inner + " " + piece)
                    }
                    if stop { return "" }
                }
            }

            let domID = item(2) as? String ?? ""
            let classes = Set((item(3) as? [String]) ?? [])
            let ownText = item(4) as? String ?? ""
            let titleText = item(5) as? String ?? ""
            let descText = item(6) as? String ?? ""
            let label = !descText.isEmpty ? descText : titleText
            let url = (role == "AXImage" || role == "AXLink") ? (item(7) as? URL) : nil
            let selected = (item(8) as? Bool == true) || ((item(8) as? NSNumber)?.boolValue == true)

            let text: String
            switch role {
            case "AXStaticText": text = ownText
            case "AXButton", "AXLink", "AXImage": text = !label.isEmpty ? label : inner
            default: text = inner.isEmpty ? label : inner
            }

            let interesting = role == "AXStaticText" || role == "AXButton" || role == "AXLink"
                || role == "AXImage" || !domID.isEmpty || !classes.isEmpty
            if interesting {
                let ref = elements.count
                elements.append(element)
                let compactText = text.split(whereSeparator: \.isNewline).joined(separator: " ")
                entries.append(YouTubeAXNodeEntry(
                    role: role,
                    domID: domID,
                    classes: classes,
                    text: compactText,
                    label: label,
                    url: url,
                    isSelected: selected,
                    ref: ref
                ))
            }
            return text
        }

        visit(root, depth: 0)
        if stop || ProcessInfo.processInfo.systemUptime >= deadline {
            elements.removeAll()
            entries.removeAll()
        }
    }

    private func pressAXElement(_ element: AXUIElement, target: YouTubeQueueTarget) -> Bool {
        var actions: CFArray?
        _ = AXUIElementCopyActionNames(element, &actions)
        if (actions as? [String])?.contains(kAXPressAction) == true {
            if AXUIElementPerformAction(element, kAXPressAction as CFString) == .success {
                return true
            }
        }
        // Fallback cho Chromium khi nút web cho phép focus nhưng không công bố AXPress.
        guard target.alive else { return false }
        let focused = AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        Thread.sleep(forTimeInterval: 0.08)
        let hasFocus = axValue(element, kAXFocusedAttribute) as? Bool == true
        guard !Task.isCancelled, target.alive, focused == .success, hasFocus else { return false }
        let role = axValue(element, kAXRoleAttribute) as? String ?? ""
        let keyCode: CGKeyCode = role == "AXLink" ? 36 : 49 // Return cho link, Space cho button
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else { return false }
        down.flags = []
        up.flags = []
        down.postToPid(target.pid)
        up.postToPid(target.pid)
        Thread.sleep(forTimeInterval: 0.08)
        return true
    }

    private func safariWebAppSite(bundleID: String) -> YouTubeSite? {
        guard bundleID.lowercased().hasPrefix("com.apple.safari.webapp."),
              let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
              let manifest = Bundle(url: appURL)?.object(forInfoDictionaryKey: "Manifest") as? [String: Any] else { return nil }
        for key in ["start_url", "scope", "id"] {
            if let raw = manifest[key] as? String,
               let url = URL(string: raw),
               let ctx = YouTubeWatchContext.parse(url: url) {
                return ctx.site
            }
        }
        return nil
    }

    private func axValue(_ element: AXUIElement, _ attr: String) -> AnyObject? {
        var out: AnyObject?
        return AXUIElementCopyAttributeValue(element, attr as CFString, &out) == .success ? out : nil
    }

    // MARK: - Tier 2: InnerTube `/youtubei/v1/next` (Unauthenticated, Ephemeral)

    private func fetchInnerTubeNext(
        context: YouTubeWatchContext,
        videoID: String,
        language: String,
        bypassCache: Bool
    ) async -> Data? {
        let key = CacheKey(
            site: context.site,
            videoID: videoID,
            playlistID: context.playlistID,
            index: context.index,
            language: language
        )
        let now = Date()
        if !bypassCache, let cached = innerTubeCache[key], cached.expiresAt > now {
            return cached.data
        }

        guard let url = URL(string: "https://\(context.site.host)/youtubei/v1/next?prettyPrint=false") else { return nil }
        var body: [String: Any] = [
            "context": [
                "client": [
                    "clientName": context.site.innerTubeClientName,
                    "clientVersion": context.site.innerTubeClientVersion(date: now),
                    "hl": language,
                    "gl": language == "vi" ? "VN" : "US"
                ]
            ],
            "videoId": videoID
        ]
        if let playlistID = context.playlistID {
            body["playlistId"] = playlistID
            if let idx = context.index, idx >= 1 {
                body["index"] = idx - 1
            }
        }
        if context.site == .youtubeMusic {
            body["isAudioOnly"] = true
            body["enablePersistentPlaylistPanel"] = true
        }

        guard let payload = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = payload
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://\(context.site.host)", forHTTPHeaderField: "Origin")
        request.setValue("https://\(context.site.host)/watch?v=\(videoID)", forHTTPHeaderField: "Referer")

        guard let data = await downloadBounded(request: request, limit: Self.maxResponseBytes) else { return nil }

        innerTubeCache[key] = CacheEntry(expiresAt: now.addingTimeInterval(Self.cacheTTL), data: data)
        innerTubeCacheOrder.removeAll { $0 == key }
        innerTubeCacheOrder.append(key)
        while innerTubeCacheOrder.count > Self.maxCacheEntries {
            innerTubeCache.removeValue(forKey: innerTubeCacheOrder.removeFirst())
        }
        return data
    }

    // MARK: - Tier 3: Desktop Apps (Kaset & Pear Desktop)

    private func loadKasetQueue(bundleID: String) -> YouTubeQueueSnapshot {
        let script = """
        with timeout of 2 seconds
            tell application id "\(bundleID)"
                return get play queue
            end tell
        end timeout
        """
        let output = BrowserTabLocator.runAppleScript(script, timeout: 2.5)
        if output.exitCode != 0 {
            let reason: YouTubeQueueEmptyReason = output.stderr.contains("-1743") ? .automationDenied : .queueNotVisible
            return YouTubeQueueSnapshot(sourceKind: .desktopApp, site: .youtubeMusic, playlistTitle: nil, items: [], emptyReason: reason)
        }
        guard let data = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8),
              let items = YouTubeQueueParser.parseKasetQueue(data: data) else {
            return YouTubeQueueSnapshot(sourceKind: .desktopApp, site: .youtubeMusic, playlistTitle: nil, items: [], emptyReason: .empty)
        }
        return YouTubeQueueSnapshot(
            sourceKind: .desktopApp,
            site: .youtubeMusic,
            playlistTitle: "Kaset",
            items: items,
            emptyReason: items.isEmpty ? .empty : nil
        )
    }

    private struct PearConfig {
        let port: Int
        let needsAuth: Bool
    }

    private func readPearAPIConfig() -> PearConfig? {
        let support = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let candidates = [
            support.appendingPathComponent("YouTube Music/config.json"),
            support.appendingPathComponent("Pear Desktop/config.json")
        ]
        for file in candidates {
            guard let data = try? Data(contentsOf: file),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let plugins = root["plugins"] as? [String: Any],
                  let api = plugins["api-server"] as? [String: Any],
                  api["enabled"] as? Bool == true else { continue }
            let port = (api["port"] as? Int) ?? 26538
            guard (1024...65535).contains(port) else { continue }
            let strategy = (api["authorizationStrategy"] as? String ?? "").uppercased()
            return PearConfig(port: port, needsAuth: strategy != "NONE")
        }
        return nil
    }

    private func loadPearDesktopQueue() async -> YouTubeQueueSnapshot {
        guard let config = readPearAPIConfig(), !config.needsAuth,
              let url = URL(string: "http://127.0.0.1:\(config.port)/api/v1/queue") else {
            return YouTubeQueueSnapshot(sourceKind: .desktopApp, site: .youtubeMusic, playlistTitle: nil, items: [], emptyReason: .queueNotVisible)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 1.0
        guard let data = await downloadBounded(request: request, limit: Self.maxResponseBytes),
              let items = YouTubeQueueParser.parsePearQueue(data: data) else {
            return YouTubeQueueSnapshot(sourceKind: .desktopApp, site: .youtubeMusic, playlistTitle: nil, items: [], emptyReason: .queueNotVisible)
        }
        return YouTubeQueueSnapshot(
            sourceKind: .desktopApp,
            site: .youtubeMusic,
            playlistTitle: "Pear Desktop",
            items: items,
            emptyReason: items.isEmpty ? .empty : nil
        )
    }

    private func selectPearQueueIndex(_ index: Int) async -> Bool {
        guard let config = readPearAPIConfig(), !config.needsAuth,
              let url = URL(string: "http://127.0.0.1:\(config.port)/api/v1/queue"),
              let body = try? JSONSerialization.data(withJSONObject: ["index": index]) else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.httpBody = body
        request.timeoutInterval = 1.5
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            let (_, response) = try await networkSession.data(for: request)
            return (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
        } catch {
            return false
        }
    }

    // MARK: - Bounded Network Helpers

    private func downloadBounded(url: URL, limit: Int) async -> Data? {
        await downloadBounded(request: URLRequest(url: url), limit: limit)
    }

    private func downloadBounded(request: URLRequest, limit: Int) async -> Data? {
        do {
            let (bytes, response) = try await networkSession.bytes(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  response.expectedContentLength <= Int64(limit) else { return nil }
            var data = Data()
            data.reserveCapacity(Int(max(0, min(response.expectedContentLength, Int64(limit)))))
            for try await byte in bytes {
                guard !Task.isCancelled, data.count < limit else { return nil }
                data.append(byte)
            }
            return data
        } catch {
            return nil
        }
    }

    private static func squareThumbnail(from data: Data, pixels: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: max(pixels * 2, 160)
              ] as CFDictionary) else { return nil }
        let side = min(thumb.width, thumb.height)
        guard side > 0 else { return nil }
        let cropRect = CGRect(
            x: (thumb.width - side) / 2,
            y: (thumb.height - side) / 2,
            width: side,
            height: side
        )
        return thumb.cropping(to: cropRect) ?? thumb
    }
}

private final class YouTubeRedirectBlocker: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
