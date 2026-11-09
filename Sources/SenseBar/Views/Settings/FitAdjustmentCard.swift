import AppKit
import SwiftUI

/// Thẻ căn chỉnh kích thước Capsule / Notch kèm bản xem trước trực tiếp.
struct FitAdjustmentCard: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var islandController = NotchDynamicIslandController.shared
    @AppStorage(DefaultsKey.notchStyle) private var notchStyle: String = "notch"
    @AppStorage(DefaultsKey.notchCapsuleFitWidth) private var capsuleFitWidth: Double = 0
    @AppStorage(DefaultsKey.notchCapsuleFitHeight) private var capsuleFitHeight: Double = 0
    @AppStorage(DefaultsKey.notchCapsuleFitDrop) private var capsuleFitDrop: Double = 0

    /// Capsule chỉ có hiệu lực khi có màn hình không tai thỏ, ngược lại luôn là Notch.
    private var showsCapsule: Bool {
        notchStyle == "pill" && islandController.canChooseStyle
    }

    var body: some View {
        let isPill = showsCapsule
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
        let isPill = showsCapsule
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
}
