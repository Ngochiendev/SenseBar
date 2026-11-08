import AppKit
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case permissions
    case about

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .permissions: return "lock.shield.fill"
        case .about: return "info.circle.fill"
        }
    }
}

struct SettingsWindowView: View {
    var onReopenWelcome: () -> Void

    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.selectedSettingsTab) private var selectedTabRaw: String = SettingsTab.general.rawValue
    @AppStorage(DefaultsKey.pillarDynamicIslandEnabled) private var dynamicIslandEnabled: Bool = true
    @AppStorage(DefaultsKey.pillarAudioStudioEnabled) private var audioStudioEnabled: Bool = true
    @AppStorage(DefaultsKey.notchDisplayTarget) private var displayTarget: String = "automatic"
    @AppStorage(DefaultsKey.notchExpandAllDisplays) private var expandAllDisplays: Bool = false
    @AppStorage(DefaultsKey.notchStyle) private var notchStyle: String = "notch"
    @AppStorage(DefaultsKey.notchHideInFullscreen) private var hideInFullscreen: Bool = false
    @AppStorage(DefaultsKey.notchCapsuleFitWidth) private var capsuleFitWidth: Double = 0
    @AppStorage(DefaultsKey.notchCapsuleFitHeight) private var capsuleFitHeight: Double = 0
    @AppStorage(DefaultsKey.notchCapsuleFitDrop) private var capsuleFitDrop: Double = 0
    @AppStorage(DefaultsKey.liquidGlassEnabled) private var liquidGlassOtherWindows: Bool = true
    @AppStorage(DefaultsKey.liquidGlassIslandEnabled) private var liquidGlassIsland: Bool = true
    @State private var launchAtLogin: Bool = LaunchAtLoginManager.isEnabled

    private var selectedTab: SettingsTab {
        SettingsTab(rawValue: selectedTabRaw) ?? .general
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar

            Divider()
                .opacity(0.6)

            ScrollView(.vertical, showsIndicators: false) {
                tabContent
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 640, height: 480)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                BrandBadge(size: 32)

                VStack(alignment: .leading, spacing: 1) {
                    Text(AppInfo.name)
                        .font(.system(size: 14, weight: .bold))
                    Text("v\(AppInfo.version)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 28)
            .padding(.bottom, 14)

            sidebarRow(tab: .general, title: l10n.s.settingsTabGeneral)
            sidebarRow(tab: .permissions, title: l10n.s.settingsTabPermissions)
            sidebarRow(tab: .about, title: l10n.s.settingsTabAbout)

            Spacer()

            Text(AppInfo.brandSignature)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 12)
                .padding(.bottom, 14)
        }
        .padding(.horizontal, 10)
        .frame(width: 196)
        .frame(maxHeight: .infinity)
        .background(Color.primary.opacity(0.03))
    }

    private func sidebarRow(tab: SettingsTab, title: String) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            selectedTabRaw = tab.rawValue
        } label: {
            HStack(spacing: 9) {
                Image(systemName: tab.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .frame(width: 18)

                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .general:
            generalTab
        case .permissions:
            SettingsPermissionsTab()
        case .about:
            aboutTab
        }
    }

    // MARK: - Tab 1: Cài đặt chung

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(l10n.s.settingsTabGeneral)
                .font(.system(size: 20, weight: .bold))

            // Khởi động cùng macOS
            settingsCard(title: l10n.s.settingsStartupSection) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(l10n.s.settingsLaunchAtLogin)
                            .font(.system(size: 13, weight: .semibold))
                        Text(l10n.s.settingsLaunchAtLoginDesc)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Toggle("", isOn: Binding(
                        get: { launchAtLogin },
                        set: { newValue in
                            launchAtLogin = newValue
                            LaunchAtLoginManager.setEnabled(newValue)
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                }
            }

            // Bật / Tắt 2 tính năng chính
            settingsCard(title: l10n.s.settingsFeaturesSection) {
                VStack(spacing: 12) {
                    featureToggleRow(
                        icon: "macbook",
                        title: l10n.s.pillar1Title,
                        subtitle: l10n.s.pillar1Subtitle,
                        isOn: $dynamicIslandEnabled
                    )

                    Divider().opacity(0.5)

                    featureToggleRow(
                        icon: "speaker.wave.2.fill",
                        title: l10n.s.pillar2Title,
                        subtitle: l10n.s.pillar2Subtitle,
                        isOn: $audioStudioEnabled
                    )
                }
            }

            // Tùy chỉnh Màn hình hiển thị Dynamic Island (Display)
            settingsCard(title: l10n.string(vi: "Màn hình hiển thị", en: "Display")) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 13))
                            .foregroundStyle(.blue)
                            .frame(width: 24, height: 24)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.blue.opacity(0.12)))

                        Text(l10n.string(vi: "Ẩn nội dung khi chạy toàn màn hình", en: "Hide content in full screen"))
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(.primary)

                        Spacer()

                        Toggle("", isOn: $hideInFullscreen)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                    }

                    HStack {
                        Image(systemName: "rectangle.expand.vertical")
                            .font(.system(size: 13))
                            .foregroundStyle(.blue)
                            .frame(width: 24, height: 24)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.blue.opacity(0.12)))

                        VStack(alignment: .leading, spacing: 1.5) {
                            Text(l10n.string(vi: "Mở rộng đồng thời trên tất cả màn hình", en: "Expand on all displays simultaneously"))
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(.primary)
                            Text(l10n.string(vi: "Khi tắt, chỉ màn hình đang trỏ chuột mới mở rộng.", en: "When off, only the hovered display expands."))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Toggle("", isOn: $expandAllDisplays)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                    }

                    // Danh sách màn hình hiển thị - SenseBar Inset Cards
                    VStack(spacing: 7) {
                        displayOptionRow(
                            id: "automatic",
                            title: l10n.string(vi: "Tự động phát hiện", en: "Automatic"),
                            subtitle: l10n.string(vi: "Tự động chọn màn hình tối ưu nhất khi cắm/rút thiết bị", en: "Automatically selects the best display"),
                            icon: "sparkles.tv"
                        )
                        displayOptionRow(
                            id: "builtIn",
                            title: l10n.string(vi: "Màn hình tích hợp", en: "Built-in display"),
                            subtitle: l10n.string(vi: "Chỉ hiển thị trên màn hình chính của MacBook", en: "Shows only on MacBook built-in screen"),
                            icon: "laptopcomputer"
                        )
                        displayOptionRow(
                            id: "main",
                            title: l10n.string(vi: "Màn hình chính macOS", en: "Main display"),
                            subtitle: l10n.string(vi: "Hiển thị trên màn hình chứa thanh Menu Bar chính", en: "Always pinned to macOS primary display"),
                            icon: "display"
                        )
                        displayOptionRow(
                            id: "pointer",
                            title: l10n.string(vi: "Đi theo con trỏ chuột", en: "Follow mouse pointer"),
                            subtitle: l10n.string(vi: "Dynamic Island tự động di chuyển sang màn hình đang trỏ chuột", en: "Dynamic Island moves to where your mouse is"),
                            icon: "cursorarrow.motionlines"
                        )
                        displayOptionRow(
                            id: "all",
                            title: l10n.string(vi: "Tất cả màn hình", en: "All displays"),
                            subtitle: l10n.string(vi: "Hiển thị đồng thời trên mọi màn hình đang kết nối", en: "Shows simultaneously on all connected screens"),
                            icon: "rectangle.on.rectangle"
                        )
                    }
                }
            }

            // Màn hình không có tai thỏ (Displays without a notch)
            settingsCard(title: l10n.string(vi: "Màn hình không có tai thỏ", en: "Displays without a notch")) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        styleSilhouetteButton(id: "pill", title: l10n.string(vi: "Capsule (Viên nang)", en: "Capsule"))
                        styleSilhouetteButton(id: "notch", title: l10n.string(vi: "Notch (Tai thỏ ảo)", en: "Notch"))
                    }
                }
            }

            // Tinh chỉnh kích thước (Capsule fit / Notch fit) - SenseBar Studio
            let isPill = notchStyle == "pill"
            let fitTitle = isPill
                ? l10n.string(vi: "Căn chỉnh kích thước (Capsule fit)", en: "Capsule fit")
                : l10n.string(vi: "Căn chỉnh kích thước (Notch fit)", en: "Notch fit")

            settingsCard(title: fitTitle) {
                VStack(alignment: .leading, spacing: 14) {
                    screenMenuPreviewMockup

                    Divider().opacity(0.4)

                    VStack(alignment: .leading, spacing: 12) {
                        sliderSettingRow(
                            icon: "arrow.left.and.right",
                            title: l10n.string(vi: "Chiều rộng", en: "Width"),
                            value: $capsuleFitWidth,
                            range: -60...120,
                            step: 2
                        )
                        sliderSettingRow(
                            icon: "arrow.up.and.down",
                            title: l10n.string(vi: "Chiều cao", en: "Height"),
                            value: $capsuleFitHeight,
                            range: -4...6,
                            step: 1
                        )
                        if isPill {
                            sliderSettingRow(
                                icon: "arrow.down.to.line",
                                title: l10n.string(vi: "Khoảng cách mép trên", en: "Distance from top"),
                                value: $capsuleFitDrop,
                                range: -6...16,
                                step: 1
                            )
                        }
                    }

                    Text(isPill
                        ? l10n.string(
                            vi: "Thay đổi kích thước và khoảng cách hạ thấp của viên nang trên thanh Menu Bar đối với màn hình không có tai thỏ.",
                            en: "Resizes the capsule and lowers it from the top of the menu bar on displays without a notch."
                        )
                        : l10n.string(
                            vi: "Thay đổi chiều rộng và chiều cao của tai thỏ ảo gắn liền thanh Menu Bar đối với màn hình không có tai thỏ.",
                            en: "Resizes the width and height of the virtual notch on the menu bar on displays without a notch."
                        )
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                }
            }

            // Liquid Glass
            settingsCard(title: "Liquid Glass") {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.blue)
                            .frame(width: 26, height: 26)
                            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.blue.opacity(0.12)))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Liquid Glass")
                                .font(.system(size: 13, weight: .semibold))
                            Text(l10n.string(vi: "Kính mờ xuyên thấu, trong suốt tự nhiên của macOS.", en: "See-through, glass-like panels."))
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack {
                        Text(l10n.string(vi: "Các cửa sổ và bảng điều khiển khác", en: "Other windows and panels"))
                            .font(.system(size: 12.5))
                        Spacer()
                        Toggle("", isOn: $liquidGlassOtherWindows)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                    }

                    HStack {
                        Text(l10n.string(vi: "Tai thỏ & Dynamic Island", en: "Dynamic Island"))
                            .font(.system(size: 12.5))
                        Spacer()
                        Toggle("", isOn: $liquidGlassIsland)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                    }
                }
            }

            // Mở lại màn hình Chào mừng & Khôi phục mặc định
            settingsCard(title: l10n.s.settingsOnboardingSection) {
                VStack(spacing: 12) {
                    HStack {
                        Text(l10n.s.settingsReopenWelcomeDesc)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button(l10n.s.menuShowWelcome) {
                            onReopenWelcome()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    Divider().opacity(0.5)

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(l10n.string(vi: "Khôi phục cài đặt mặc định", en: "Reset to default settings"))
                                .font(.system(size: 12.5, weight: .medium))
                            Text(l10n.string(vi: "Đưa kiểu hiển thị, kích thước notch và viên nang về thông số chuẩn Apple.", en: "Restores display mode, notch and capsule sizes to standard Apple defaults."))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button {
                            resetToDefaults()
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "arrow.counterclockwise")
                                Text(l10n.string(vi: "Khôi phục", en: "Reset"))
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        }
    }

    private func resetToDefaults() {
        dynamicIslandEnabled = true
        audioStudioEnabled = true
        displayTarget = "automatic"
        expandAllDisplays = false
        notchStyle = "notch"
        hideInFullscreen = false
        capsuleFitWidth = 0
        capsuleFitHeight = 0
        capsuleFitDrop = 0
        liquidGlassOtherWindows = true
        liquidGlassIsland = true
        DefaultsResetter.resetAllToDefaults()
        NotchDynamicIslandController.shared.syncVisibility()
        NotchDynamicIslandController.shared.repositionPanel()
    }

    private func displayOptionRow(
        id: String,
        title: String,
        subtitle: String,
        icon: String
    ) -> some View {
        let isSelected = displayTarget == id
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                displayTarget = id
            }
            NotchDynamicIslandController.shared.repositionPanel()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? Color.blue : Color.primary.opacity(0.06))
                        .frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.8))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? Color.blue : Color.primary)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                ZStack {
                    Circle()
                        .stroke(isSelected ? Color.blue : Color.secondary.opacity(0.4), lineWidth: 1.5)
                        .frame(width: 16, height: 16)
                    if isSelected {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 8, height: 8)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.blue.opacity(0.08) : Color.primary.opacity(0.025))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? Color.blue.opacity(0.35) : Color.primary.opacity(0.05), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func styleSilhouetteButton(id: String, title: String) -> some View {
        let isSelected = notchStyle == id
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                notchStyle = id
            }
            NotchDynamicIslandController.shared.syncVisibility()
        } label: {
            VStack(spacing: 8) {
                ZStack(alignment: .top) {
                    // Nền desktop thu nhỏ
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: isSelected
                                    ? [Color.blue.opacity(0.20), Color.blue.opacity(0.06)]
                                    : [Color.primary.opacity(0.06), Color.primary.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(height: 54)

                    // Thanh Menu Bar mờ ảo
                    HStack(spacing: 4) {
                        Image(systemName: "apple.logo")
                            .font(.system(size: 6))
                            .opacity(0.6)
                        Spacer()
                        Circle().fill(Color.primary.opacity(0.35)).frame(width: 3, height: 3)
                        Circle().fill(Color.primary.opacity(0.35)).frame(width: 3, height: 3)
                    }
                    .padding(.horizontal, 6)
                    .frame(height: 14)
                    .background(
                        Rectangle().fill(Color.primary.opacity(0.06))
                    )

                    // Capsule hoặc Notch nằm trên Menu Bar
                    if id == "pill" {
                        Capsule(style: .continuous)
                            .fill(isSelected ? Color.blue : Color.primary.opacity(0.75))
                            .frame(width: 44, height: 8.5)
                            .padding(.top, 2.7)
                            .shadow(color: isSelected ? Color.blue.opacity(0.4) : Color.black.opacity(0.2), radius: 2, y: 1)
                    } else {
                        NotchAttachedShape(topShoulder: 3, bottomRadius: 4)
                            .fill(isSelected ? Color.blue : Color.primary.opacity(0.75))
                            .frame(width: 46, height: 14)
                            .shadow(color: isSelected ? Color.blue.opacity(0.4) : Color.black.opacity(0.2), radius: 2, y: 1)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                HStack(spacing: 5) {
                    Circle()
                        .fill(isSelected ? Color.blue : Color.secondary.opacity(0.35))
                        .frame(width: 6, height: 6)

                    Text(title)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? Color.blue : Color.primary.opacity(0.85))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(7)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(isSelected ? Color.blue.opacity(0.08) : Color.primary.opacity(0.02))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(isSelected ? Color.blue.opacity(0.45) : Color.primary.opacity(0.06), lineWidth: 1.2)
            )
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var screenMenuPreviewMockup: some View {
        let isPill = notchStyle == "pill"
        return VStack(spacing: 8) {
            ZStack(alignment: .top) {
                // 1. Màn hình Desktop (Wallpaper phong cách macOS sang trọng)
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.16, green: 0.22, blue: 0.38),
                                Color(red: 0.09, green: 0.12, blue: 0.20)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 86)

                // 2. Thanh Menu Bar macOS (Nền kính mờ bán trong suốt)
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "apple.logo")
                            .font(.system(size: 9, weight: .bold))
                        Text("Finder")
                            .font(.system(size: 9, weight: .semibold))
                        Text("File")
                            .font(.system(size: 8.5))
                            .opacity(0.7)
                        Text("Edit")
                            .font(.system(size: 8.5))
                            .opacity(0.7)
                    }
                    .foregroundStyle(.white)
                    .padding(.leading, 12)

                    Spacer()

                    HStack(spacing: 6) {
                        Image(systemName: "wifi")
                            .font(.system(size: 7.5))
                        Image(systemName: "battery.100")
                            .font(.system(size: 7.5))
                        Image(systemName: "switch.2")
                            .font(.system(size: 7.5))
                        Text("9:41")
                            .font(.system(size: 8.5, weight: .medium))
                    }
                    .foregroundStyle(.white)
                    .padding(.trailing, 12)
                }
                .frame(height: 24)
                .background(
                    Rectangle()
                        .fill(Color.white.opacity(0.12))
                        .background(.ultraThinMaterial)
                )

                // 3. Dynamic Island (Capsule hoặc Notch) trực tiếp trên Menu Bar
                if isPill {
                    // Chế độ Capsule: Viên nang nổi nằm trên Menu Bar
                    Capsule(style: .continuous)
                        .fill(Color.black)
                        .frame(
                            width: max(45, 115 + CGFloat(capsuleFitWidth) * 0.42),
                            height: max(10, 16 + CGFloat(capsuleFitHeight) * 0.8)
                        )
                        .padding(.top, max(1, 4 + CGFloat(capsuleFitDrop) * 0.5))
                        .overlay(
                            HStack(spacing: 4) {
                                Circle().fill(Color(red: 0.15, green: 0.85, blue: 0.45)).frame(width: 3.5, height: 3.5)
                                Spacer()
                                Image(systemName: "waveform")
                                    .font(.system(size: 7, weight: .bold))
                                    .foregroundStyle(Color(red: 0.20, green: 0.60, blue: 1.0))
                            }
                            .padding(.horizontal, 8)
                            .padding(.top, max(1, 4 + CGFloat(capsuleFitDrop) * 0.5))
                        )
                        .shadow(color: Color.black.opacity(0.5), radius: 5, x: 0, y: 2)
                        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: capsuleFitWidth)
                        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: capsuleFitHeight)
                        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: capsuleFitDrop)
                } else {
                    // Chế độ Notch: Tai thỏ đính từ mép trên phủ xuống Menu Bar
                    NotchAttachedShape(topShoulder: 5, bottomRadius: 7)
                        .fill(Color.black)
                        .frame(
                            width: max(55, 125 + CGFloat(capsuleFitWidth) * 0.45),
                            height: max(14, 24 + CGFloat(capsuleFitHeight) * 0.8)
                        )
                        .overlay(
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color(red: 0.08, green: 0.08, blue: 0.12))
                                    .frame(width: 5, height: 5)
                                    .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 0.5))
                                Spacer()
                                Image(systemName: "waveform")
                                    .font(.system(size: 7, weight: .bold))
                                    .foregroundStyle(Color(red: 0.20, green: 0.60, blue: 1.0))
                            }
                            .padding(.horizontal, 10)
                            .padding(.top, 4)
                        )
                        .shadow(color: Color.black.opacity(0.5), radius: 5, x: 0, y: 2)
                        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: capsuleFitWidth)
                        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: capsuleFitHeight)
                }
            }
            .frame(height: 86)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )

            // Thanh thông tin & Nút reset
            HStack {
                Text(isPill
                    ? l10n.string(vi: "Mô phỏng viên nang (Capsule) trực tiếp trên thanh Menu Bar", en: "Live preview of Capsule on Menu Bar")
                    : l10n.string(vi: "Mô phỏng tai thỏ ảo (Notch) trực tiếp trên thanh Menu Bar", en: "Live preview of Notch on Menu Bar")
                )
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)

                Spacer()

                if capsuleFitWidth != 0 || capsuleFitHeight != 0 || (isPill && capsuleFitDrop != 0) {
                    Button {
                        withAnimation {
                            capsuleFitWidth = 0
                            capsuleFitHeight = 0
                            capsuleFitDrop = 0
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 9, weight: .bold))
                            Text(l10n.string(vi: "Đặt lại về 0", en: "Reset to 0"))
                                .font(.system(size: 10.5, weight: .medium))
                        }
                        .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func sliderSettingRow(
        icon: String,
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        unit: String = "px"
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 18)

            Text(title)
                .font(.system(size: 12.5, weight: .regular))
                .foregroundStyle(.primary)
                .frame(width: 140, alignment: .leading)

            Button {
                value.wrappedValue = max(range.lowerBound, value.wrappedValue - step)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Color.primary.opacity(0.06)))
            }
            .buttonStyle(.plain)

            Slider(value: value, in: range, step: step)
                .controlSize(.small)

            Button {
                value.wrappedValue = min(range.upperBound, value.wrappedValue + step)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Color.primary.opacity(0.06)))
            }
            .buttonStyle(.plain)

            let intVal = Int(value.wrappedValue)
            Text("\(intVal > 0 ? "+" : "")\(intVal) \(unit)")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(intVal == 0 ? Color.secondary : Color.blue)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(intVal == 0 ? Color.primary.opacity(0.05) : Color.blue.opacity(0.12))
                )
                .frame(width: 58, alignment: .trailing)
        }
    }

    private func featureToggleRow(
        icon: String,
        title: String,
        subtitle: String,
        isOn: Binding<Bool>
    ) -> some View {
        let accent = Theme.iconColor(for: icon)
        return HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(accent.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
    }

    // MARK: - Tab 3: Giới thiệu (SenseBar by ngochiendev)

    private var aboutTab: some View {
        VStack(spacing: 16) {
            BrandBadge(size: 84)
                .padding(.top, 12)

            VStack(spacing: 4) {
                Text(AppInfo.name)
                    .font(.system(size: 24, weight: .bold))

                Text(AppInfo.brandSignature)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text(String(format: l10n.s.aboutVersionFormat, AppInfo.version, AppInfo.buildNumber))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }

            Text(l10n.s.aboutLicenseBadge)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.12), in: Capsule())
                .foregroundStyle(Color.accentColor)

            Text(l10n.s.aboutSubtitle)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.horizontal, 28)

            HStack(spacing: 12) {
                Button {
                    NSWorkspace.shared.open(AppInfo.repositoryURL)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "link")
                            .font(.system(size: 11.5, weight: .semibold))
                        Text(l10n.s.aboutOpenGitHub)
                            .font(.system(size: 12.5, weight: .semibold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 6)

            Spacer()

            Text(AppInfo.copyright)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 6)
        }
        .frame(maxWidth: .infinity, minHeight: 380)
    }

    private func settingsCard<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.secondary)

            content()
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(0.035))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8)
                )
        }
    }
}

// MARK: - Tab 2: Quyền truy cập trong Cài đặt

private struct SettingsPermissionsTab: View {
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(l10n.s.settingsTabPermissions)
                .font(.system(size: 20, weight: .bold))

            Text(l10n.s.permissionsSubtitle)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)

            PermissionSectionCard(compact: false)
        }
    }
}

