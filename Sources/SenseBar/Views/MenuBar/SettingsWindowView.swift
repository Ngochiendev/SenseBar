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
                    }

                    VStack(spacing: 10) {
                        HStack(spacing: 10) {
                            displayOptionButton(id: "automatic", title: l10n.string(vi: "Tự động", en: "Automatic"), symbol: "display.2")
                            displayOptionButton(id: "builtIn", title: l10n.string(vi: "Màn hình tích hợp", en: "Built-in display"), symbol: "laptopcomputer")
                        }
                        HStack(spacing: 10) {
                            displayOptionButton(id: "main", title: l10n.string(vi: "Màn hình chính", en: "Main display"), symbol: "display")
                            displayOptionButton(id: "pointer", title: l10n.string(vi: "Đi theo con trỏ", en: "Follow pointer"), symbol: "cursorarrow.motionlines")
                        }
                        HStack(spacing: 10) {
                            displayOptionButton(id: "all", title: l10n.string(vi: "Tất cả màn hình", en: "All displays"), symbol: "rectangle.on.rectangle")
                            Spacer()
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }

            // Màn hình không có tai thỏ (Displays without a notch)
            settingsCard(title: l10n.string(vi: "Màn hình không có tai thỏ", en: "Displays without a notch")) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        styleSilhouetteButton(id: "pill", title: l10n.string(vi: "Capsule", en: "Capsule"))
                        styleSilhouetteButton(id: "notch", title: l10n.string(vi: "Notch", en: "Notch"))
                    }
                }
            }

            // Tinh chỉnh kích thước viên nang (Capsule fit)
            settingsCard(title: l10n.string(vi: "Căn chỉnh kích thước (Capsule fit)", en: "Capsule fit")) {
                VStack(alignment: .leading, spacing: 12) {
                    sliderSettingRow(
                        title: l10n.string(vi: "Chiều rộng (Width)", en: "Width"),
                        value: $capsuleFitWidth,
                        range: -60...120,
                        step: 2
                    )
                    sliderSettingRow(
                        title: l10n.string(vi: "Chiều cao (Height)", en: "Height"),
                        value: $capsuleFitHeight,
                        range: -4...6,
                        step: 1
                    )
                    sliderSettingRow(
                        title: l10n.string(vi: "Cách mép trên (Distance from top)", en: "Distance from top"),
                        value: $capsuleFitDrop,
                        range: -6...16,
                        step: 1
                    )

                    Text(l10n.string(
                        vi: "Thay đổi kích thước và hạ thấp vị trí của viên nang từ mép trên màn hình đối với màn hình không có tai thỏ.",
                        en: "Resizes the capsule and lowers it from the top of the screen on displays without a notch."
                    ))
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
                    }

                    HStack {
                        Text(l10n.string(vi: "Tai thỏ & Dynamic Island", en: "Dynamic Island"))
                            .font(.system(size: 12.5))
                        Spacer()
                        Toggle("", isOn: $liquidGlassIsland)
                            .labelsHidden()
                            .toggleStyle(.switch)
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

    private func displayOptionButton(id: String, title: String, symbol: String) -> some View {
        let isSelected = displayTarget == id
        return Button {
            displayTarget = id
            NotchDynamicIslandController.shared.repositionPanel()
        } label: {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(isSelected ? Color(red: 0.16, green: 0.50, blue: 0.98) : Color.primary.opacity(0.85))

                Text(title)
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Color(red: 0.16, green: 0.50, blue: 0.98) : Color.primary.opacity(0.85))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 78)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .circular)
                    .fill(isSelected ? Color.blue.opacity(0.12) : Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .circular)
                    .stroke(isSelected ? Color(red: 0.16, green: 0.50, blue: 0.98) : Color.clear, lineWidth: 1.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .circular))
        }
        .buttonStyle(.plain)
    }

    private func styleSilhouetteButton(id: String, title: String) -> some View {
        let isSelected = notchStyle == id
        return Button {
            notchStyle = id
            NotchDynamicIslandController.shared.syncVisibility()
        } label: {
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .circular)
                        .fill(isSelected ? Color.blue.opacity(0.12) : Color.primary.opacity(0.06))
                        .frame(height: 42)

                    HStack(spacing: 4) {
                        Capsule().fill(Color.primary.opacity(0.25)).frame(width: 14, height: 4)
                        Capsule().fill(Color.primary.opacity(0.18)).frame(width: 10, height: 4)
                        Capsule().fill(Color.primary.opacity(0.18)).frame(width: 10, height: 4)
                        Spacer()
                        Circle().fill(Color.primary.opacity(0.20)).frame(width: 4.5, height: 4.5)
                        Circle().fill(Color.primary.opacity(0.20)).frame(width: 4.5, height: 4.5)
                        Circle().fill(Color.primary.opacity(0.20)).frame(width: 4.5, height: 4.5)
                    }
                    .padding(.horizontal, 10)

                    if id == "pill" {
                        Capsule(style: .continuous)
                            .fill(Color.black)
                            .frame(width: 52, height: 12)
                    } else {
                        NotchAttachedShape(topShoulder: 3.5, bottomRadius: 4.5)
                            .fill(Color.black)
                            .frame(width: 52, height: 14)
                            .frame(maxHeight: .infinity, alignment: .top)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 8)

                Text(title)
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Color(red: 0.16, green: 0.50, blue: 0.98) : Color.primary.opacity(0.85))
                    .padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .circular)
                    .fill(isSelected ? Color.blue.opacity(0.08) : Color.primary.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .circular)
                    .stroke(isSelected ? Color(red: 0.16, green: 0.50, blue: 0.98) : Color.clear, lineWidth: 1.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .circular))
        }
        .buttonStyle(.plain)
    }



    private func sliderSettingRow(title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 12.5))
                .foregroundStyle(.primary)
                .frame(width: 150, alignment: .leading)

            Slider(value: value, in: range, step: step)
                .controlSize(.small)

            Text("\(Int(value.wrappedValue))")
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(.primary)
                .frame(width: 32, alignment: .trailing)
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

