import AppKit
import SwiftUI

/// Nút mở danh sách chờ trên Island.
struct IslandQueueControls: View {
    @ObservedObject var music: MusicService
    @Binding var presented: Bool
    @ObservedObject private var queue = YouTubeQueueService.shared
    @ObservedObject private var l10n = L10n.shared
    @State private var holdingIsland = false

    private var track: NowPlayingTrack? { music.track }

    var body: some View {
        Button { presented.toggle() } label: {
            Image(systemName: "list.bullet")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(presented ? music.accentColor : .white.opacity(0.78))
                .frame(width: 27, height: 25)
                .background(.white.opacity(presented ? 0.18 : 0.10), in: Capsule())
        }
        .buttonStyle(.plain)
        .help(l10n.string(vi: "Danh sách chờ YouTube / YouTube Music", en: "YouTube / YouTube Music Up Next"))
        .accessibilityLabel(l10n.string(vi: "Danh sách chờ", en: "Up Next"))
        .popover(isPresented: $presented, arrowEdge: .bottom) {
            IslandQueuePanelView(
                music: music,
                queue: queue,
                onDismiss: { presented = false }
            )
            .environment(\.colorScheme, .dark)
            .onExitCommand { presented = false }
        }
        .onAppear {
            queue.preload(track: track)
        }
        .onChange(of: presented) { _, open in
            if open {
                holdIsland()
                queue.setVisible(true, track: track)
            } else {
                queue.setVisible(false, track: track)
                releaseIsland()
            }
        }
        .onChange(of: music.track) { _, next in
            if YouTubeQueueService.isCandidateSource(next) {
                if presented {
                    queue.updateTrack(next)
                } else {
                    queue.preload(track: next)
                }
            } else {
                if presented { presented = false }
                queue.preload(track: nil)
            }
        }
        .onDisappear {
            presented = false
            queue.setVisible(false, track: track)
            releaseIsland()
        }
    }

    private func holdIsland() {
        guard !holdingIsland else { return }
        holdingIsland = true
        IslandController.shared.beginAudioPopover()
    }

    private func releaseIsland() {
        guard holdingIsland else { return }
        holdingIsland = false
        IslandController.shared.endAudioPopover()
    }
}

/// Danh sách chờ và trạng thái nguồn phát.
struct IslandQueuePanelView: View {
    @ObservedObject var music: MusicService
    @ObservedObject var queue: YouTubeQueueService
    var onDismiss: () -> Void = {}
    @ObservedObject private var l10n = L10n.shared

    private var headerTitle: String {
        if queue.snapshot?.isSuggested == true {
            return l10n.string(vi: "Gợi ý tiếp theo", en: "Suggested Up Next")
        }
        return l10n.string(vi: "Tiếp theo", en: "Up Next")
    }

    private var sourceBadge: String? {
        guard let snap = queue.snapshot, !snap.items.isEmpty else { return nil }
        if let title = snap.playlistTitle, !title.isEmpty { return title }
        switch snap.sourceKind {
        case .liveAccessibility:
            return snap.site == .youtubeMusic
                ? l10n.string(vi: "Trực tiếp · YouTube Music", en: "Live · YouTube Music")
                : l10n.string(vi: "Trực tiếp · YouTube", en: "Live · YouTube")
        case .publicPlaylist:
            return l10n.string(vi: "Danh sách phát", en: "Playlist")
        case .suggestedRadio:
            return snap.site == .youtubeMusic
                ? l10n.string(vi: "Radio YouTube Music", en: "YouTube Music Radio")
                : l10n.string(vi: "Gợi ý từ YouTube", en: "YouTube Suggestions")
        case .desktopApp:
            return l10n.string(vi: "Trực tiếp", en: "Live")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(headerTitle)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white)
                    if let badge = sourceBadge {
                        Text(badge)
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                if queue.isLoading || queue.isActionPending {
                    ProgressView().controlSize(.mini)
                }
                Button { queue.refresh() } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(width: 24, height: 24)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .disabled(queue.isLoading || queue.isActionPending)
                .help(l10n.string(vi: "Làm mới danh sách chờ", en: "Refresh up next"))
                .accessibilityLabel(l10n.string(vi: "Làm mới", en: "Refresh"))
            }

            if queue.actionFailed {
                Label(
                    l10n.string(
                        vi: "Không thể chuyển bài. Hãy kiểm tra tab trình duyệt rồi thử lại.",
                        en: "Couldn't play that track. Check the browser tab and try again."
                    ),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.system(size: 10))
                .foregroundStyle(.orange)
            }

            Divider().overlay(.white.opacity(0.08))

            if let snap = queue.snapshot, !snap.items.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(snap.items) { item in
                            IslandQueueRowView(
                                item: item,
                                thumbnail: item.artworkURL.flatMap { queue.thumbnails[$0] },
                                disabled: queue.isLoading || queue.isActionPending,
                                onPlay: { queue.play(item) }
                            )
                        }
                    }
                }
                .frame(height: min(290, max(50, CGFloat(snap.items.count) * 48)))
            } else if queue.isLoading {
                VStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(l10n.string(vi: "Đang đọc danh sách chờ…", en: "Reading up next…"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                emptyState(reason: queue.snapshot?.emptyReason ?? .queueNotVisible)
            }
        }
        .padding(12)
        .frame(width: 320)
    }

    @ViewBuilder
    private func emptyState(reason: YouTubeQueueEmptyReason) -> some View {
        let info: (symbol: String, title: String, detail: String) = {
            switch reason {
            case .privatePlaylistInBackground:
                return (
                    "lock.fill",
                    l10n.string(vi: "Danh sách riêng tư đang ở tab nền", en: "Private queue is in a background tab"),
                    l10n.string(
                        vi: "Mở tab YouTube / YouTube Music (hiện mục Tiếp theo) rồi nhấn làm mới để đọc trực tiếp mà không cần extension.",
                        en: "Open the YouTube / YouTube Music tab (with Up Next visible) and refresh to read it directly without extensions."
                    )
                )
            case .automationDenied:
                return (
                    "hand.raised.fill",
                    l10n.string(vi: "Cần quyền Tự động hóa (Automation)", en: "Automation permission required"),
                    l10n.string(
                        vi: "Cho phép SenseBar đọc URL tab trình duyệt trong Cài đặt Hệ thống → Quyền riêng tư & Bảo mật → Tự động hóa (không cần bật JavaScript).",
                        en: "Allow SenseBar to read browser tab URLs in System Settings → Privacy & Security → Automation (no JavaScript setting needed)."
                    )
                )
            case .accessibilityRequired:
                return (
                    "figure.wave",
                    l10n.string(vi: "Cần quyền Trợ năng (Accessibility)", en: "Accessibility permission required"),
                    l10n.string(
                        vi: "Bật quyền Trợ năng cho SenseBar để đọc trực tiếp danh sách chờ trên trình duyệt.",
                        en: "Enable Accessibility for SenseBar to read the browser's Up Next list directly."
                    )
                )
            case .notYouTubeSource:
                return (
                    "play.rectangle",
                    l10n.string(vi: "Chưa phát YouTube / YouTube Music", en: "Not playing YouTube / YouTube Music"),
                    l10n.string(
                        vi: "Tab đang phát không thuộc YouTube hoặc YouTube Music.",
                        en: "The active media tab isn't YouTube or YouTube Music."
                    )
                )
            case .networkFailed:
                return (
                    "wifi.exclamationmark",
                    l10n.string(vi: "Không tải được danh sách chờ", en: "Couldn't load Up Next"),
                    l10n.string(
                        vi: "Kết nối tới YouTube bị gián đoạn. Nhấn làm mới để thử lại.",
                        en: "The request to YouTube failed. Press refresh to try again."
                    )
                )
            case .empty:
                return (
                    "list.bullet",
                    l10n.string(vi: "Không có bài tiếp theo", en: "No upcoming tracks"),
                    l10n.string(
                        vi: "Đã đến cuối danh sách phát hiện tại.",
                        en: "You've reached the end of the current queue."
                    )
                )
            case .queueNotVisible:
                return (
                    "list.bullet",
                    l10n.string(vi: "Chưa thấy danh sách chờ", en: "Up Next unavailable"),
                    l10n.string(
                        vi: "Mở tab YouTube / YouTube Music hoặc hiển thị khung Tiếp theo trong trình duyệt rồi nhấn làm mới.",
                        en: "Open the YouTube / YouTube Music tab or show the Up Next panel in your browser, then refresh."
                    )
                )
            }
        }()

        VStack(spacing: 8) {
            Image(systemName: info.symbol)
                .font(.system(size: 18))
                .foregroundStyle(.white.opacity(0.55))
            Text(info.title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text(info.detail)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                if reason == .accessibilityRequired {
                    Button {
                        PermissionManager.shared.openAccessibilitySettings()
                        onDismiss()
                    } label: {
                        Text(l10n.string(vi: "Mở Cài đặt Trợ năng", en: "Open Accessibility"))
                            .font(.system(size: 10.5, weight: .semibold))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(.white.opacity(0.14), in: Capsule())
                    }
                    .buttonStyle(.plain)
                } else if reason == .automationDenied {
                    Button {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                            NSWorkspace.shared.open(url)
                        }
                        onDismiss()
                    } label: {
                        Text(l10n.string(vi: "Mở Quyền Tự động hóa", en: "Open Automation"))
                            .font(.system(size: 10.5, weight: .semibold))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(.white.opacity(0.14), in: Capsule())
                    }
                    .buttonStyle(.plain)
                } else if reason == .privatePlaylistInBackground || reason == .queueNotVisible {
                    Button {
                        music.openPlayerApp()
                        onDismiss()
                    } label: {
                        Text(l10n.string(vi: "Mở \(music.sourceDisplayName)", en: "Open \(music.sourceDisplayName)"))
                            .font(.system(size: 10.5, weight: .semibold))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(.white.opacity(0.14), in: Capsule())
                    }
                    .buttonStyle(.plain)
                } else if reason == .networkFailed {
                    Button { queue.refresh() } label: {
                        Text(l10n.string(vi: "Thử lại", en: "Retry"))
                            .font(.system(size: 10.5, weight: .semibold))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(.white.opacity(0.14), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 8)
    }
}

private struct IslandQueueRowView: View {
    let item: YouTubeQueueItem
    let thumbnail: NSImage?
    let disabled: Bool
    let onPlay: () -> Void
    @ObservedObject private var l10n = L10n.shared
    @State private var hovered = false

    private var subtitleText: String {
        let dur = item.duration > 0 ? NowPlayingTrack.formattedTime(item.duration) : ""
        if !item.artist.isEmpty && !dur.isEmpty { return "\(item.artist) · \(dur)" }
        return !item.artist.isEmpty ? item.artist : dur
    }

    private var playHelpText: String {
        switch item.action {
        case .navigateTab:
            return l10n.string(vi: "Chuyển tab YouTube sang bài này", en: "Play in YouTube tab")
        default:
            return l10n.string(vi: "Phát ngay", en: "Play now")
        }
    }

    var body: some View {
        let rowContent = HStack(spacing: 10) {
            ZStack {
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.white.opacity(0.08))
                    Image(systemName: "music.note")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            .frame(width: 34, height: 34)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if !subtitleText.isEmpty {
                    Text(subtitleText)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if item.canPlay {
                Image(systemName: "play.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(hovered ? 0.95 : 0.45))
                    .frame(width: 24, height: 24)
                    .background(.white.opacity(hovered ? 0.14 : 0.06), in: Circle())
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.white.opacity(hovered && item.canPlay ? 0.09 : 0), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())

        if item.canPlay {
            Button(action: onPlay) { rowContent }
                .buttonStyle(.plain)
                .disabled(disabled)
                .onHover { hovered = $0 }
                .help(playHelpText)
                .accessibilityLabel("\(playHelpText): \(item.title)")
        } else {
            rowContent
        }
    }
}
