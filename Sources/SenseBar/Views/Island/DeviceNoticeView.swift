import SwiftUI

/// A transient device surface with a camera-safe layout and static, semantic accents.
struct DeviceNoticeView: View {
    let notice: IslandDeviceNotice
    let size: CGSize
    let geometry: ScreenGeometry
    let isPill: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var l10n = L10n.shared

    private var isLow: Bool { notice.id.hasPrefix("low:") }
    private var isPower: Bool { notice.id == "mac-power" }
    private var isPlugged: Bool { isPower && notice.symbol == "powerplug.fill" }
    private var accent: Color {
        if isLow { return (notice.percent ?? 20) <= 10 ? .red : .orange }
        return isPower && isPlugged ? .green : .white.opacity(0.85)
    }
    private var subtitle: String { notice.batteryDetail ?? notice.detail }

    var body: some View {
        Group {
            if geometry.isNotched { notchedContent }
            else { floatingContent }
        }
        .frame(width: size.width, height: size.height)
        .foregroundStyle(.white)
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([notice.title, notice.detail, notice.batteryDetail,
                             notice.percent.map { "\($0)%" }].compactMap { $0 }.joined(separator: ", "))
        .transition(reduceMotion ? .identity : .opacity)
    }

    private var floatingContent: some View {
        HStack(spacing: 10) {
            deviceIcon(size: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(notice.title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.95))
                Text(subtitle)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(isLow ? accent : .white.opacity(0.48))
            }
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            batteryReadout(compact: false)
        }
        .padding(.leading, isPill ? 15 : geometry.shoulderRadius.shoulder + 10)
        .padding(.trailing, isPill ? 16 : geometry.shoulderRadius.shoulder + 12)
    }

    private var notchedContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                deviceIcon(size: 23)
                    .frame(maxWidth: .infinity)
                Color.clear.frame(width: geometry.cameraWidth)
                batteryReadout(compact: true)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, geometry.shoulderRadius.shoulder + 5)
            .frame(height: geometry.cameraHeight)

            VStack(spacing: 2) {
                Text(notice.title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.95))
                HStack(spacing: 5) {
                    Text(subtitle)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(isLow ? accent : .white.opacity(0.55))
                }
            }
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            .frame(height: 34, alignment: .top)
        }
    }

    private func deviceIcon(size: CGFloat) -> some View {
        Image(systemName: isPower ? "laptopcomputer" : notice.symbol)
            .font(.system(size: size * 0.78, weight: .regular))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(isLow ? .white.opacity(0.9) : accent)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func batteryReadout(compact: Bool) -> some View {
        if let percent = notice.percent {
            HStack(spacing: 5) {
                Text("\(percent)%")
                    .font(.system(size: compact ? 10.5 : 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(isLow || isPlugged ? accent : .white.opacity(0.9))
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: percent)
                Image(systemName: isPlugged ? "battery.100percent.bolt"
                    : percent <= 10 ? "battery.0percent" : percent <= 30 ? "battery.25percent"
                    : percent <= 60 ? "battery.50percent" : percent <= 85 ? "battery.75percent" : "battery.100percent")
                    .font(.system(size: compact ? 11 : 12, weight: .regular))
                    .foregroundStyle(accent)
            }
            .fixedSize()
        } else if compact {
            Text(isLow ? l10n.string(vi: "PIN YẾU", en: "LOW BATTERY")
                 : isPower ? l10n.string(vi: "NGUỒN", en: "POWER")
                 : l10n.string(vi: "KẾT NỐI", en: "CONNECTED"))
                .font(.system(size: 7.5, weight: .semibold))
                .tracking(0.7)
                .foregroundStyle(accent.opacity(0.8))
        }
    }

}
