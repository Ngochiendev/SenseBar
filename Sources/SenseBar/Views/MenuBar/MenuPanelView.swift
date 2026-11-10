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
    @ObservedObject private var islandController = IslandController.shared
    @ObservedObject private var audio = AudioStudioService.shared
    @ObservedObject private var updateService = UpdateService.shared

    @AppStorage(DefaultsKey.selectedPopoverTab) private var selectedModeRaw: String = PopoverMode.dynamicIsland.rawValue
    @AppStorage(DefaultsKey.pillarDynamicIslandEnabled) private var dynamicIslandEnabled: Bool = true
    @AppStorage(DefaultsKey.notchStyle) private var notchStyle: String = "notch"
    @AppStorage(DefaultsKey.notchExpandOnHover) private var expandOnHover: Bool = true
    @AppStorage(DefaultsKey.notchShowVisualizer) private var showVisualizer: Bool = true
    @State private var showingSettings: Bool = false
    @Namespace private var modeAnimation

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
                AudioMixerSection()
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
        ScrollView(showsIndicators: false) {
            VStack(spacing: 8) {
                // Khung Ảnh Example trực quan cho Dynamic Island
                IslandPreviewCard()

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

                // Thú cưng Dynamic Island (Pet)
                PetCard()
            }
        }
        .frame(maxHeight: 520)
    }

    private func styleOptionButton(id: String, icon: String, title: String) -> some View {
        let selected = notchStyle == id
        return Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                notchStyle = id
            }
            IslandController.shared.syncVisibility()
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
