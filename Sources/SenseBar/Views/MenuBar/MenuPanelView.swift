import AppKit
import SwiftUI

enum PopoverMode: String, CaseIterable, Identifiable {
    case dynamicIsland = "island"
    case audioApps = "audio"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .dynamicIsland: return "macbook"
        case .audioApps: return "speaker.wave.2.fill"
        }
    }

    @MainActor
    func title(_ l10n: L10n) -> String {
        switch self {
        case .dynamicIsland:
            return l10n.string(vi: "Dynamic Island", en: "Dynamic Island")
        case .audioApps:
            return l10n.string(vi: "Loa & Ứng dụng", en: "Speaker & Apps")
        }
    }
}

struct MenuPanelView: View {
    let onQuit: () -> Void

    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = PermissionManager.shared
    @ObservedObject private var islandController = NotchDynamicIslandController.shared
    @ObservedObject private var music = NotchMusicService.shared
    @ObservedObject private var audio = AudioStudioService.shared
    @ObservedObject private var updateService = UpdateService.shared

    @AppStorage(DefaultsKey.selectedPopoverTab) private var selectedModeRaw: String = PopoverMode.dynamicIsland.rawValue
    @AppStorage(DefaultsKey.pillarDynamicIslandEnabled) private var dynamicIslandEnabled: Bool = true
    @AppStorage(DefaultsKey.notchStyle) private var notchStyle: String = "notch"
    @AppStorage(DefaultsKey.notchExpandOnHover) private var expandOnHover: Bool = true
    @AppStorage(DefaultsKey.notchShowVisualizer) private var showVisualizer: Bool = true
    @State private var showingSettings: Bool = false
    @Namespace private var modeAnimation

    /// Capsule chỉ có hiệu lực khi có màn hình không tai thỏ, ngược lại luôn là Notch.
    private var showsCapsule: Bool {
        notchStyle == "pill" && islandController.canChooseStyle
    }

    private var selectedMode: PopoverMode {
        PopoverMode(rawValue: selectedModeRaw) ?? .dynamicIsland
    }

    var body: some View {
        Group {
            if showingSettings {
                PopoverSettingsView(
                    onBack: {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                            showingSettings = false
                        }
                    },
                    onQuit: onQuit
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .trailing).combined(with: .opacity)
                ))
            } else {
                mainControlsView
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            }
        }
        .padding(14)
        .frame(width: 356)
        .fixedSize(horizontal: false, vertical: true)
        .panelGlassSurface()
        .onAppear {
            permissions.refreshStatus()
            audio.refreshAll()
        }
    }

    private var mainControlsView: some View {
        VStack(spacing: 10) {
            topHeaderBar

            if !permissions.allRequiredGranted {
                permissionWarningBanner
            }

            neutralSegmentBar

            if selectedMode == .dynamicIsland {
                dynamicIslandControlSection
                    .transition(.opacity)
            } else {
                audioMixerControlSection
                    .transition(.opacity)
            }

            bottomFooterBar
        }
    }

    // MARK: - Header Bar

    private var topHeaderBar: some View {
        HStack(spacing: 10) {
            BrandBadge(size: 26)

            Text("SenseBar")
                .font(.system(size: 14.5, weight: .bold))
                .foregroundStyle(.primary)

            Spacer()

            Button {
                dynamicIslandEnabled.toggle()
                islandController.syncVisibility()
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(dynamicIslandEnabled ? Color.green : Color.secondary.opacity(0.4))
                        .frame(width: 6.5, height: 6.5)

                    Text(dynamicIslandEnabled
                         ? l10n.string(vi: "Đang bật", en: "Active")
                         : l10n.string(vi: "Đang tắt", en: "Off"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(dynamicIslandEnabled ? .primary : .secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.8)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 2)
    }

    // MARK: - Cảnh báo quyền Trợ năng

    private var permissionWarningBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.orange)

            Text(l10n.string(
                vi: "Cần cấp quyền Trợ năng để hoạt động đầy đủ",
                en: "Accessibility permission required"
            ))
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.primary)
            .lineLimit(1)

            Spacer(minLength: 4)

            Button {
                PermissionManager.shared.requestAccessibility()
            } label: {
                Text(l10n.string(vi: "Cấp quyền", en: "Grant"))
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.orange.opacity(0.14))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.orange.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(Color.orange.opacity(0.24), lineWidth: 0.8)
                )
        )
    }

    // MARK: - Thanh chuyển chế độ

    private var neutralSegmentBar: some View {
        HStack(spacing: 4) {
            ForEach(PopoverMode.allCases) { mode in
                let isSelected = selectedMode == mode
                Button {
                    withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
                        selectedModeRaw = mode.rawValue
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: mode.symbol)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(isSelected ? .primary : .secondary)

                        Text(mode.title(l10n))
                            .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                            .foregroundStyle(isSelected ? .primary : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6.5)
                    .background {
                        if isSelected {
                            Capsule(style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor))
                                .shadow(color: .black.opacity(0.08), radius: 2.5, y: 1)
                                .matchedGeometryEffect(id: "popoverModeThumb", in: modeAnimation)
                        }
                    }
                    .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3.5)
        .background(
            Capsule(style: .continuous)
                .fill(Color.primary.opacity(0.055))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.8)
        )
    }

    // MARK: - Tab Dynamic Island

    private var dynamicIslandControlSection: some View {
        VStack(spacing: 8) {
            // Khung Ảnh Example trực quan cho Dynamic Island
            dynamicIslandExampleCard

            // Khung Điều khiển Dynamic Island
            VStack(alignment: .leading, spacing: 10) {
                Text(l10n.string(vi: "Tùy chỉnh Dynamic Island", en: "Dynamic Island Controls"))
                    .font(.system(size: 12, weight: .bold))

                // Chọn kiểu dáng: chỉ hiện khi có màn hình không tai thỏ
                if islandController.canChooseStyle {
                    HStack(spacing: 6) {
                        styleOptionButton(
                            id: "notch",
                            icon: "macbook",
                            title: l10n.string(vi: "Ôm sát Tai thỏ", en: "Notch Cutout")
                        )
                        styleOptionButton(
                            id: "pill",
                            icon: "capsule.fill",
                            title: l10n.string(vi: "Viên nang nổi", en: "Floating Pill")
                        )
                    }
                    .transition(.opacity)

                    if islandController.hasNotchedDisplay {
                        Label(
                            l10n.string(
                                vi: "Màn hình MacBook có tai thỏ luôn dùng kiểu Notch.",
                                en: "Notched MacBook displays always use the Notch style."
                            ),
                            systemImage: "info.circle.fill"
                        )
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                    }

                    Divider().opacity(0.5)
                }

                compactToggleRow(
                    icon: "cursorarrow.motionlines",
                    title: l10n.string(vi: "Tự mở rộng khi rê chuột vào tai thỏ", en: "Expand when hovering over notch"),
                    isOn: $expandOnHover
                )

                compactToggleRow(
                    icon: "waveform",
                    title: l10n.string(vi: "Hiển thị sóng nhạc theo bài hát", en: "Show album-tinted audio visualizer"),
                    isOn: $showVisualizer
                )
            }
            .panelCard()
            .animation(.easeInOut(duration: 0.25), value: islandController.canChooseStyle)
        }
    }

    private var dynamicIslandExampleCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(
                    l10n.string(vi: "Minh họa Dynamic Island", en: "Dynamic Island Example"),
                    systemImage: "eye.fill"
                )
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.secondary)

                Spacer()

                Text(showsCapsule
                     ? l10n.string(vi: "Kiểu Viên nang", en: "Pill Style")
                     : l10n.string(vi: "Kiểu Tai thỏ", en: "Notch Style"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
            }

            // Hình ảnh Example mô phỏng trực tiếp thanh Menu Bar & Tai thỏ MacBook (có hiệu ứng trỏ chuột mở rộng)
            TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
                let cycle = timeline.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 4.2) / 4.2
                let exp = previewExpansionProgress(for: cycle)
                let isPill = showsCapsule
                let compactW: CGFloat = isPill ? 162 : 148
                let compactH: CGFloat = isPill ? 18 : 22
                let expandedW: CGFloat = 248
                let expandedH: CGFloat = 62
                let currentW = compactW + (expandedW - compactW) * exp
                let currentH = compactH + (expandedH - compactH) * exp
                let cursorPt = previewCursorPoint(for: cycle)

                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.13, green: 0.16, blue: 0.24),
                                    Color(red: 0.08, green: 0.10, blue: 0.16)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    // Thanh Menu Bar giả lập
                    HStack {
                        HStack(spacing: 4) {
                            Image(systemName: "apple.logo")
                                .font(.system(size: 8.5, weight: .bold))
                            Text("SenseBar")
                                .font(.system(size: 8.5, weight: .semibold))
                        }
                        .foregroundStyle(.white.opacity(0.78))

                        Spacer()

                        HStack(spacing: 5) {
                            Image(systemName: "wifi")
                                .font(.system(size: 8))
                            Text("9:41")
                                .font(.system(size: 8.5, weight: .medium))
                        }
                        .foregroundStyle(.white.opacity(0.78))
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 22)
                    .background(Color.white.opacity(0.07))

                    // Island tự động biến hình từ Thu gọn -> Mở rộng khi con trỏ chạm vào
                    ZStack(alignment: .top) {
                        Group {
                            if isPill {
                                RoundedRectangle(cornerRadius: compactH / 2 + (14 - compactH / 2) * exp, style: .continuous)
                                    .fill(Color.black)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: compactH / 2 + (14 - compactH / 2) * exp, style: .continuous)
                                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.6)
                                    )
                            } else {
                                NotchAttachedShape(topShoulder: 7 + 3 * exp, bottomRadius: 8 + 6 * exp)
                                    .fill(Color.black)
                                    .overlay(
                                        NotchAttachedShape(topShoulder: 7 + 3 * exp, bottomRadius: 8 + 6 * exp)
                                            .stroke(Color.white.opacity(0.16), lineWidth: 0.6)
                                    )
                            }
                        }

                        if exp < 0.45 {
                            Group {
                                if isPill {
                                    HStack(spacing: 5) {
                                        previewAlbumBadge(size: 13, cornerRadius: 3.5)
                                        HStack(spacing: 3) {
                                            Image(systemName: "headphones")
                                                .font(.system(size: 7.5, weight: .semibold))
                                                .foregroundStyle(.white.opacity(0.85))
                                            Text(music.track?.title ?? "Midnight City — M83")
                                                .font(.system(size: 8.5, weight: .semibold))
                                                .foregroundStyle(.white)
                                                .lineLimit(1)
                                        }
                                        Spacer(minLength: 3)
                                        if showVisualizer {
                                            SenseEqualizerBars(
                                                isPlaying: true,
                                                bars: 4,
                                                barWidth: 1.5,
                                                height: 8.5,
                                                tint: music.accentColor
                                            )
                                        } else {
                                            Image(systemName: "music.note")
                                                .font(.system(size: 7.5, weight: .semibold))
                                                .foregroundStyle(music.accentColor)
                                        }
                                    }
                                    .padding(.horizontal, 6)
                                } else {
                                    HStack(spacing: 0) {
                                        previewAlbumBadge(size: 13, cornerRadius: 3.8)
                                            .padding(.leading, 13)
                                        Spacer()
                                        Circle()
                                            .fill(Color(red: 0.12, green: 0.15, blue: 0.22))
                                            .frame(width: 5.5, height: 5.5)
                                            .overlay(
                                                Circle()
                                                    .fill(Color.cyan.opacity(0.45))
                                                    .frame(width: 2, height: 2)
                                            )
                                        Spacer()
                                        Group {
                                            if showVisualizer {
                                                SenseEqualizerBars(
                                                    isPlaying: true,
                                                    bars: 5,
                                                    barWidth: 1.5,
                                                    height: 9,
                                                    tint: music.accentColor
                                                )
                                            } else {
                                                Image(systemName: "music.note")
                                                    .font(.system(size: 8, weight: .semibold))
                                                    .foregroundStyle(music.accentColor)
                                            }
                                        }
                                        .padding(.trailing, 13)
                                    }
                                }
                            }
                            .frame(width: compactW, height: compactH)
                            .opacity(Double(max(0, 1.0 - exp * 2.4)))
                        }

                        if exp > 0.22 {
                            VStack(spacing: 5) {
                                HStack(spacing: 0) {
                                    HStack(spacing: 4) {
                                        Circle().fill(Color.green).frame(width: 4.5, height: 4.5)
                                        Text(music.track?.appName ?? "Apple Music")
                                            .font(.system(size: 7.5, weight: .semibold))
                                            .foregroundStyle(.white.opacity(0.78))
                                    }
                                    Spacer()
                                    if showVisualizer {
                                        SenseEqualizerBars(
                                            isPlaying: true,
                                            bars: 5,
                                            barWidth: 1.4,
                                            height: 8,
                                            tint: music.accentColor
                                        )
                                    }
                                }

                                HStack(spacing: 8) {
                                    previewAlbumBadge(size: 28, cornerRadius: 6)

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(music.track?.title ?? "Midnight City — M83")
                                            .font(.system(size: 9.5, weight: .bold))
                                            .foregroundStyle(.white)
                                            .lineLimit(1)
                                        Capsule()
                                            .fill(Color.white.opacity(0.22))
                                            .frame(width: 92, height: 3)
                                            .overlay(alignment: .leading) {
                                                Capsule()
                                                    .fill(music.accentColor)
                                                    .frame(width: 56, height: 3)
                                            }
                                    }

                                    Spacer()

                                    HStack(spacing: 6) {
                                        Image(systemName: "backward.fill")
                                            .font(.system(size: 8.5))
                                        Image(systemName: "pause.circle.fill")
                                            .font(.system(size: 14))
                                        Image(systemName: "forward.fill")
                                            .font(.system(size: 8.5))
                                    }
                                    .foregroundStyle(.white.opacity(0.92))
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .frame(width: expandedW, height: expandedH)
                            .opacity(Double(min(1, (exp - 0.22) / 0.45)))
                        }
                    }
                    .frame(width: currentW, height: currentH)
                    .padding(.top, isPill ? 2 : 0)

                    // Con trỏ chuột minh họa trỏ vào Notch / Capsule
                    Image(systemName: "cursorarrow")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.65), radius: 2, x: 0.5, y: 1)
                        .position(x: cursorPt.x, y: cursorPt.y)
                }
                .frame(height: 86)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
        }
        .panelCard()
    }

    private func previewExpansionProgress(for cycle: Double) -> CGFloat {
        if cycle < 0.22 {
            return 0
        } else if cycle < 0.34 {
            let t = (cycle - 0.22) / 0.12
            return CGFloat(t * t * (3.0 - 2.0 * t))
        } else if cycle < 0.72 {
            return 1
        } else if cycle < 0.84 {
            let t = (cycle - 0.72) / 0.12
            return CGFloat(1.0 - t * t * (3.0 - 2.0 * t))
        } else {
            return 0
        }
    }

    private func previewCursorPoint(for cycle: Double) -> CGPoint {
        let start = CGPoint(x: 266, y: 72)
        let targetCompact = CGPoint(x: 186, y: 14)
        let targetExpanded = CGPoint(x: 198, y: 42)
        if cycle < 0.22 {
            let t = cycle / 0.22
            let s = CGFloat(t * t * (3.0 - 2.0 * t))
            return CGPoint(x: start.x + (targetCompact.x - start.x) * s, y: start.y + (targetCompact.y - start.y) * s)
        } else if cycle < 0.36 {
            let t = (cycle - 0.22) / 0.14
            let s = CGFloat(t * t * (3.0 - 2.0 * t))
            return CGPoint(x: targetCompact.x + (targetExpanded.x - targetCompact.x) * s, y: targetCompact.y + (targetExpanded.y - targetCompact.y) * s)
        } else if cycle < 0.72 {
            return targetExpanded
        } else if cycle < 0.86 {
            let t = (cycle - 0.72) / 0.14
            let s = CGFloat(t * t * (3.0 - 2.0 * t))
            return CGPoint(x: targetExpanded.x + (start.x - targetExpanded.x) * s, y: targetExpanded.y + (start.y - targetExpanded.y) * s)
        } else {
            return start
        }
    }

    @ViewBuilder
    private func previewAlbumBadge(size: CGFloat, cornerRadius: CGFloat) -> some View {
        if let artwork = music.artwork {
            Image(nsImage: artwork)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
                .overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.45, weight: .bold))
                        .foregroundStyle(.white)
                )
        }
    }

    private func styleOptionButton(id: String, icon: String, title: String) -> some View {
        let selected = notchStyle == id
        return Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                notchStyle = id
            }
            NotchDynamicIslandController.shared.syncVisibility()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: selected ? .bold : .medium))
            }
            .foregroundStyle(selected ? Color.blue : Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selected ? Color.blue.opacity(0.14) : Color.primary.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(selected ? Color.blue.opacity(0.55) : Color.primary.opacity(0.06), lineWidth: selected ? 1.2 : 0.8)
            )
        }
        .buttonStyle(.plain)
    }

    private func compactToggleRow(icon: String, title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 18)

            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer()

            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
    }

    // MARK: - Tab Loa & Ứng dụng

    private var audioMixerControlSection: some View {
        VStack(spacing: 8) {
            // Khung Ảnh Example trực quan cho Bộ trộn âm lượng nhiều ứng dụng
            audioMixerExampleCard

            // Khung Loa chính (Master Output)
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Image(systemName: audio.isMasterMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(audio.outputDeviceName)
                        .font(.system(size: 12, weight: .bold))
                        .lineLimit(1)
                    Spacer()
                    Text("\(Int((audio.isMasterMuted ? 0 : audio.masterVolume) * 100))%")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    Button {
                        audio.toggleMasterMute()
                    } label: {
                        Image(systemName: audio.isMasterMuted ? "speaker.slash.fill" : "speaker.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(audio.isMasterMuted ? .orange : .secondary)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Color.primary.opacity(0.06)))
                    }
                    .buttonStyle(.plain)

                    Slider(
                        value: Binding(
                            get: { audio.isMasterMuted ? 0 : audio.masterVolume },
                            set: { audio.setMasterVolume($0) }
                        ),
                        in: 0...1
                    )
                    .controlSize(.small)
                }
            }
            .panelCard()

            // Khung Điều chỉnh âm lượng từng ứng dụng (0% - 200%)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(l10n.string(vi: "Âm lượng từng ứng dụng", en: "Per-App Volume"))
                        .font(.system(size: 12, weight: .bold))
                    Spacer()
                    Text("0% – 200%")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.primary.opacity(0.06)))
                }

                VStack(spacing: 7) {
                    ForEach(audio.apps.prefix(4)) { app in
                        appVolumeRow(app)
                    }
                }
            }
            .panelCard()
        }
    }

    private var audioMixerExampleCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label(
                    l10n.string(vi: "Minh họa Bộ trộn đa ứng dụng", en: "Multi-App Mixer Example"),
                    systemImage: "slider.horizontal.below.rectangle"
                )
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.secondary)

                Spacer()

                Text(l10n.string(vi: "Độc lập từng App", en: "Independent Gain"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            // Hình Example trực quan hiển thị 3 thanh sóng ứng dụng độc lập
            HStack(spacing: 8) {
                exampleAppBar(name: "Music", percent: "140%", ratio: 0.85, symbol: "music.note")
                exampleAppBar(name: "Chrome", percent: "75%", ratio: 0.50, symbol: "globe")
                exampleAppBar(name: "Spotify", percent: "100%", ratio: 0.68, symbol: "waveform")
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
        }
        .panelCard()
    }

    private func exampleAppBar(name: String, percent: String, ratio: CGFloat, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(name)
                    .font(.system(size: 9.5, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(percent)
                    .font(.system(size: 8.5, weight: .bold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.10))
                        .frame(height: 4)
                    Capsule()
                        .fill(Color.primary.opacity(0.65))
                        .frame(width: geo.size.width * ratio, height: 4)
                }
            }
            .frame(height: 4)
        }
        .padding(7)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.7))
        )
    }

    private func appVolumeRow(_ app: AudioAppEntry) -> some View {
        HStack(spacing: 8) {
            Image(nsImage: app.icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 20, height: 20)

            Text(app.name)
                .font(.system(size: 11.5, weight: .medium))
                .lineLimit(1)
                .frame(width: 78, alignment: .leading)

            Button {
                audio.toggleAppMute(id: app.id)
            } label: {
                Image(systemName: app.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 10.5))
                    .foregroundStyle(app.isMuted ? .orange : .secondary)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)

            Slider(
                value: Binding(
                    get: { app.isMuted ? 0 : app.volume },
                    set: { audio.setAppVolume(id: app.id, volume: $0) }
                ),
                in: 0...2.0
            )
            .controlSize(.mini)

            Text("\(Int(((app.isMuted ? 0 : app.volume) * 100).rounded()))%")
                .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)
        }
    }

    // MARK: - Footer Bar

    private var bottomFooterBar: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                    showingSettings = true
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text(l10n.string(vi: "Cài đặt", en: "Settings"))
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )
            }
            .buttonStyle(.plain)

            Spacer()

            if let release = updateService.availableRelease {
                Button {
                    updateService.openDownloadPage()
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 5.5, height: 5.5)
                        Text(l10n.string(vi: "v\(release.version) mới", en: "v\(release.version) new"))
                            .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(Color.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.blue.opacity(0.12))
                    )
                }
                .buttonStyle(.plain)
            } else {
                Text("v\(AppInfo.version)")
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button(action: onQuit) {
                HStack(spacing: 4) {
                    Image(systemName: "power")
                        .font(.system(size: 10.5, weight: .semibold))
                    Text(l10n.string(vi: "Thoát", en: "Quit"))
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 2)
    }
}
