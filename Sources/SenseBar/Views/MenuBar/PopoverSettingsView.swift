import AppKit
import SwiftUI

/// Màn hình Cài đặt tích hợp trực tiếp bên trong Menu Bar Popover
struct PopoverSettingsView: View {
    let onBack: () -> Void
    let onQuit: () -> Void

    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = PermissionManager.shared
    @ObservedObject private var islandController = NotchDynamicIslandController.shared

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

    var body: some View {
        VStack(spacing: 10) {
            headerBar

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 12) {
                    startupAndFeaturesCard

                    displayTargetCard

                    notchStyleCard

                    fitAdjustmentCard

                    liquidGlassCard

                    permissionsAndAboutCard
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: 450)

            footerBar
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 8) {
            Button(action: onBack) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .bold))
                    Text(l10n.string(vi: "Quay lại", en: "Back"))
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(Color.blue)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.1), in: Capsule())
            }
            .buttonStyle(.plain)

            Spacer()

            Text(l10n.string(vi: "Cài đặt", en: "Settings"))
                .font(.system(size: 13.5, weight: .bold))
                .foregroundStyle(.primary)

            Spacer()

            Text("v\(AppInfo.version)")
                .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.05), in: Capsule())
        }
        .padding(.horizontal, 2)
        .padding(.bottom, 2)
    }

    // MARK: - Khởi động & Tính năng chính

    private var startupAndFeaturesCard: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.blue.opacity(0.12))
                        .frame(width: 24, height: 24)
                    Image(systemName: "power")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.blue)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(l10n.s.settingsLaunchAtLogin)
                        .font(.system(size: 12, weight: .semibold))
                    Text(l10n.s.settingsLaunchAtLoginDesc)
                        .font(.system(size: 10.5))
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

            Divider().opacity(0.4)

            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Theme.iconColor(for: "macbook").opacity(0.15))
                        .frame(width: 24, height: 24)
                    Image(systemName: "macbook")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.iconColor(for: "macbook"))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(l10n.s.pillar1Title)
                        .font(.system(size: 12, weight: .semibold))
                    Text(l10n.s.pillar1Subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Toggle("", isOn: $dynamicIslandEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }

            Divider().opacity(0.4)

            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Theme.iconColor(for: "speaker.wave.2.fill").opacity(0.15))
                        .frame(width: 24, height: 24)
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.iconColor(for: "speaker.wave.2.fill"))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(l10n.s.pillar2Title)
                        .font(.system(size: 12, weight: .semibold))
                    Text(l10n.s.pillar2Subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Toggle("", isOn: $audioStudioEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }
        }
        .panelCard()
    }

    // MARK: - Màn hình hiển thị

    private var displayTargetCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(l10n.string(vi: "Màn hình hiển thị", en: "Display Target"))
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11))
                    .foregroundStyle(.blue)
                    .frame(width: 22, height: 22)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.blue.opacity(0.12)))

                Text(l10n.string(vi: "Ẩn nội dung khi chạy toàn màn hình", en: "Hide content in full screen"))
                    .font(.system(size: 11.5))
                Spacer()
                Toggle("", isOn: $hideInFullscreen)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }

            HStack(spacing: 8) {
                Image(systemName: "rectangle.expand.vertical")
                    .font(.system(size: 11))
                    .foregroundStyle(.blue)
                    .frame(width: 22, height: 22)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.blue.opacity(0.12)))

                VStack(alignment: .leading, spacing: 1) {
                    Text(l10n.string(vi: "Mở rộng đồng thời trên tất cả màn hình", en: "Expand on all displays"))
                        .font(.system(size: 11.5))
                    Text(l10n.string(vi: "Khi tắt, chỉ màn hình đang trỏ chuột mới mở rộng.", en: "When off, only hovered display expands."))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: $expandAllDisplays)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }

            Divider().opacity(0.4)

            VStack(spacing: 6) {
                displayOptionRow(
                    id: "automatic",
                    title: l10n.string(vi: "Tự động phát hiện", en: "Automatic"),
                    subtitle: l10n.string(vi: "Tự chọn màn hình tối ưu nhất", en: "Detects the best display"),
                    icon: "sparkles.tv"
                )
                displayOptionRow(
                    id: "builtIn",
                    title: l10n.string(vi: "Màn hình tích hợp", en: "Built-in display"),
                    subtitle: l10n.string(vi: "Cố định trên màn hình MacBook", en: "Pinned to MacBook screen"),
                    icon: "laptopcomputer"
                )
                displayOptionRow(
                    id: "main",
                    title: l10n.string(vi: "Màn hình chính macOS", en: "Main display"),
                    subtitle: l10n.string(vi: "Màn hình chứa thanh Menu Bar chính", en: "Primary macOS screen"),
                    icon: "display"
                )
                displayOptionRow(
                    id: "pointer",
                    title: l10n.string(vi: "Đi theo con trỏ chuột", en: "Follow mouse pointer"),
                    subtitle: l10n.string(vi: "Di chuyển theo vị trí chuột", en: "Follows active cursor"),
                    icon: "cursorarrow.motionlines"
                )
                displayOptionRow(
                    id: "all",
                    title: l10n.string(vi: "Tất cả màn hình", en: "All displays"),
                    subtitle: l10n.string(vi: "Hiển thị đồng thời trên mọi màn hình", en: "Shows on all screens"),
                    icon: "rectangle.on.rectangle"
                )
            }
        }
        .panelCard()
    }

    private func displayOptionRow(id: String, title: String, subtitle: String, icon: String) -> some View {
        let isSelected = displayTarget == id
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                displayTarget = id
            }
            islandController.repositionPanel()
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isSelected ? Color.blue : Color.primary.opacity(0.06))
                        .frame(width: 26, height: 26)
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.75))
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? Color.blue : Color.primary)
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                ZStack {
                    Circle()
                        .stroke(isSelected ? Color.blue : Color.secondary.opacity(0.35), lineWidth: 1.2)
                        .frame(width: 14, height: 14)
                    if isSelected {
                        Circle().fill(Color.blue).frame(width: 7, height: 7)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.blue.opacity(0.08) : Color.primary.opacity(0.02))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? Color.blue.opacity(0.35) : Color.primary.opacity(0.04), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Kiểu dáng hiển thị

    private var notchStyleCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(l10n.string(vi: "Màn hình không có tai thỏ", en: "Displays without a notch"))
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                styleSilhouetteButton(id: "pill", title: l10n.string(vi: "Capsule", en: "Capsule"))
                styleSilhouetteButton(id: "notch", title: l10n.string(vi: "Notch", en: "Notch"))
            }
        }
        .panelCard()
    }

    private func styleSilhouetteButton(id: String, title: String) -> some View {
        let isSelected = notchStyle == id
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                notchStyle = id
            }
            islandController.syncVisibility()
        } label: {
            VStack(spacing: 6) {
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: isSelected
                                    ? [Color.blue.opacity(0.20), Color.blue.opacity(0.06)]
                                    : [Color.primary.opacity(0.06), Color.primary.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(height: 46)

                    HStack(spacing: 3) {
                        Image(systemName: "apple.logo")
                            .font(.system(size: 5.5))
                            .opacity(0.6)
                        Spacer()
                        Circle().fill(Color.primary.opacity(0.35)).frame(width: 2.5, height: 2.5)
                        Circle().fill(Color.primary.opacity(0.35)).frame(width: 2.5, height: 2.5)
                    }
                    .padding(.horizontal, 6)
                    .frame(height: 12)
                    .background(Rectangle().fill(Color.primary.opacity(0.06)))

                    if id == "pill" {
                        Capsule(style: .continuous)
                            .fill(isSelected ? Color.blue : Color.primary.opacity(0.75))
                            .frame(width: 40, height: 7.5)
                            .padding(.top, 2.2)
                            .shadow(color: isSelected ? Color.blue.opacity(0.4) : Color.black.opacity(0.2), radius: 2, y: 1)
                    } else {
                        NotchAttachedShape(topShoulder: 2.5, bottomRadius: 3.5)
                            .fill(isSelected ? Color.blue : Color.primary.opacity(0.75))
                            .frame(width: 42, height: 12)
                            .shadow(color: isSelected ? Color.blue.opacity(0.4) : Color.black.opacity(0.2), radius: 2, y: 1)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                HStack(spacing: 4) {
                    Circle()
                        .fill(isSelected ? Color.blue : Color.secondary.opacity(0.35))
                        .frame(width: 5.5, height: 5.5)
                    Text(title)
                        .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? Color.blue : Color.primary.opacity(0.85))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? Color.blue.opacity(0.08) : Color.primary.opacity(0.02))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(isSelected ? Color.blue.opacity(0.45) : Color.primary.opacity(0.06), lineWidth: 1.2)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Căn chỉnh kích thước

    private var fitAdjustmentCard: some View {
        let isPill = notchStyle == "pill"
        let fitTitle = isPill
            ? l10n.string(vi: "Căn chỉnh kích thước (Capsule fit)", en: "Capsule fit")
            : l10n.string(vi: "Căn chỉnh kích thước (Notch fit)", en: "Notch fit")

        return VStack(alignment: .leading, spacing: 10) {
            Text(fitTitle)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.secondary)

            screenMenuPreviewMockup

            Divider().opacity(0.4)

            VStack(alignment: .leading, spacing: 10) {
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
                        title: l10n.string(vi: "Cách mép trên", en: "Distance from top"),
                        value: $capsuleFitDrop,
                        range: -6...16,
                        step: 1
                    )
                }
            }
        }
        .panelCard()
    }

    private var screenMenuPreviewMockup: some View {
        let isPill = notchStyle == "pill"
        return VStack(spacing: 6) {
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
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
                    .frame(height: 72)

                HStack(spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "apple.logo").font(.system(size: 7.5, weight: .bold))
                        Text("Finder").font(.system(size: 7.5, weight: .semibold))
                        Text("File").font(.system(size: 7)).opacity(0.7)
                    }
                    .foregroundStyle(.white)
                    .padding(.leading, 8)

                    Spacer()

                    HStack(spacing: 5) {
                        Image(systemName: "wifi").font(.system(size: 6.5))
                        Image(systemName: "battery.100").font(.system(size: 6.5))
                        Text("9:41").font(.system(size: 7.5, weight: .medium))
                    }
                    .foregroundStyle(.white)
                    .padding(.trailing, 8)
                }
                .frame(height: 18)
                .background(Rectangle().fill(Color.white.opacity(0.12)).background(.ultraThinMaterial))

                if isPill {
                    Capsule(style: .continuous)
                        .fill(Color.black)
                        .frame(
                            width: max(40, 105 + CGFloat(capsuleFitWidth) * 0.4),
                            height: max(9, 13 + CGFloat(capsuleFitHeight) * 0.7)
                        )
                        .padding(.top, max(1, 2.8 + CGFloat(capsuleFitDrop) * 0.45))
                        .overlay(
                            HStack(spacing: 3) {
                                Circle().fill(Color(red: 0.15, green: 0.85, blue: 0.45)).frame(width: 2.8, height: 2.8)
                                Spacer()
                                Image(systemName: "waveform")
                                    .font(.system(size: 5.5, weight: .bold))
                                    .foregroundStyle(Color(red: 0.20, green: 0.60, blue: 1.0))
                            }
                            .padding(.horizontal, 6)
                            .padding(.top, max(1, 2.8 + CGFloat(capsuleFitDrop) * 0.45))
                        )
                        .shadow(color: Color.black.opacity(0.5), radius: 4, y: 1.5)
                        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: capsuleFitWidth)
                        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: capsuleFitHeight)
                        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: capsuleFitDrop)
                } else {
                    NotchAttachedShape(topShoulder: 4, bottomRadius: 5.5)
                        .fill(Color.black)
                        .frame(
                            width: max(48, 115 + CGFloat(capsuleFitWidth) * 0.4),
                            height: max(12, 19 + CGFloat(capsuleFitHeight) * 0.7)
                        )
                        .overlay(
                            HStack(spacing: 3) {
                                Circle()
                                    .fill(Color(red: 0.08, green: 0.08, blue: 0.12))
                                    .frame(width: 4, height: 4)
                                    .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 0.4))
                                Spacer()
                                Image(systemName: "waveform")
                                    .font(.system(size: 5.5, weight: .bold))
                                    .foregroundStyle(Color(red: 0.20, green: 0.60, blue: 1.0))
                            }
                            .padding(.horizontal, 8)
                            .padding(.top, 2)
                        )
                        .shadow(color: Color.black.opacity(0.5), radius: 4, y: 1.5)
                        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: capsuleFitWidth)
                        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: capsuleFitHeight)
                }
            }
            .frame(height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )

            HStack {
                Text(isPill
                    ? l10n.string(vi: "Mô phỏng viên nang trên Menu Bar", en: "Live preview of Capsule")
                    : l10n.string(vi: "Mô phỏng tai thỏ ảo trên Menu Bar", en: "Live preview of Notch")
                )
                .font(.system(size: 9.5))
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
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.counterclockwise").font(.system(size: 8, weight: .bold))
                            Text(l10n.string(vi: "Đặt lại", en: "Reset")).font(.system(size: 9.5, weight: .medium))
                        }
                        .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func sliderSettingRow(icon: String, title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 16)

            Text(title)
                .font(.system(size: 11.5))
                .foregroundStyle(.primary)
                .frame(width: 110, alignment: .leading)

            Button {
                value.wrappedValue = max(range.lowerBound, value.wrappedValue - step)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Color.primary.opacity(0.06)))
            }
            .buttonStyle(.plain)

            Slider(
                value: Binding(
                    get: { value.wrappedValue },
                    set: { value.wrappedValue = ($0 / step).rounded() * step }
                ),
                in: range
            )
            .controlSize(.mini)

            Button {
                value.wrappedValue = min(range.upperBound, value.wrappedValue + step)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Color.primary.opacity(0.06)))
            }
            .buttonStyle(.plain)

            let intVal = Int(value.wrappedValue)
            Text("\(intVal > 0 ? "+" : "")\(intVal) px")
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .foregroundStyle(intVal == 0 ? Color.secondary : Color.blue)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    Capsule().fill(intVal == 0 ? Color.primary.opacity(0.05) : Color.blue.opacity(0.12))
                )
                .frame(width: 50, alignment: .trailing)
        }
    }

    // MARK: - Hiệu ứng Liquid Glass

    private var liquidGlassCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.blue)
                Text("Liquid Glass")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.primary)
            }

            Divider().opacity(0.4)

            HStack(spacing: 8) {
                Image(systemName: "macwindow.on.rectangle")
                    .font(.system(size: 11))
                    .foregroundStyle(.blue)
                    .frame(width: 22, height: 22)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.blue.opacity(0.12)))

                Text(l10n.string(vi: "Các cửa sổ và bảng điều khiển", en: "Other panels"))
                    .font(.system(size: 11.5))
                Spacer()
                Toggle("", isOn: $liquidGlassOtherWindows)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }

            HStack(spacing: 8) {
                Image(systemName: "macbook.gen2")
                    .font(.system(size: 11))
                    .foregroundStyle(.blue)
                    .frame(width: 22, height: 22)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.blue.opacity(0.12)))

                Text(l10n.string(vi: "Tai thỏ & Dynamic Island", en: "Dynamic Island"))
                    .font(.system(size: 11.5))
                Spacer()
                Toggle("", isOn: $liquidGlassIsland)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }
        }
        .panelCard()
    }

    // MARK: - Quyền & Thông tin ứng dụng

    private var permissionsAndAboutCard: some View {
        VStack(spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: permissions.allRequiredGranted ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(permissions.allRequiredGranted ? Color.green : Color.orange)

                    Text(l10n.string(vi: "Quyền Trợ năng (Accessibility)", en: "Accessibility Permission"))
                        .font(.system(size: 11.5, weight: .medium))
                }

                Spacer()

                if !permissions.allRequiredGranted {
                    Button {
                        PermissionManager.shared.requestAccessibility()
                    } label: {
                        Text(l10n.string(vi: "Cấp quyền", en: "Grant"))
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.blue, in: Capsule())
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(l10n.string(vi: "Đã bật", en: "Granted"))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.green)
                }
            }

            Divider().opacity(0.4)

            // Thông tin SenseBar: App Logo + Tên + Phiên bản + Giấy phép GPL v3 + GitHub
            HStack(spacing: 9) {
                BrandBadge(size: 34)

                VStack(alignment: .leading, spacing: 2.5) {
                    HStack(spacing: 5) {
                        Text(AppInfo.name)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.primary)

                        Text("v\(AppInfo.version)")
                            .font(.system(size: 10, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 4) {
                        Text(AppInfo.author)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        Text("•")
                            .font(.system(size: 8))
                            .foregroundStyle(.tertiary)

                        Text("GPL v3.0")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(Color.blue)
                            .padding(.horizontal, 4.5)
                            .padding(.vertical, 1)
                            .background(
                                Capsule().fill(Color.blue.opacity(0.12))
                            )
                    }
                }

                Spacer(minLength: 4)

                Button {
                    NSWorkspace.shared.open(AppInfo.repositoryURL)
                } label: {
                    HStack(spacing: 4) {
                        if let svg = BrandIconResources.svgImage(named: "github") {
                            Image(nsImage: svg)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 12, height: 12)
                        } else {
                            Image(systemName: "link")
                                .font(.system(size: 9))
                        }
                        Text("GitHub")
                            .font(.system(size: 10.5, weight: .medium))
                    }
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .panelCard()
    }

    // MARK: - Footer Bar

    private var footerBar: some View {
        HStack {
            Button(action: onQuit) {
                HStack(spacing: 5) {
                    Image(systemName: "power")
                        .font(.system(size: 11, weight: .semibold))
                    Text(l10n.string(vi: "Thoát SenseBar", en: "Quit SenseBar"))
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(.red.opacity(0.85))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)

            Spacer()

            Button(action: onBack) {
                Text(l10n.string(vi: "Đóng", en: "Done"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 2)
        .padding(.top, 2)
    }
}

