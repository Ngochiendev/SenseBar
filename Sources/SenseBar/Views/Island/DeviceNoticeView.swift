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
    private var subtitle: String {
        if let component = notice.batteryComponent, component != .main {
            return notice.detail + " · " + componentName(component)
        }
        return notice.detail
    }

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
                             notice.percent.map { "\($0)%" }, componentAccessibility]
            .compactMap { $0 }.joined(separator: ", "))
        .transition(reduceMotion ? .identity : .opacity)
    }

    private var floatingContent: some View {
        HStack(spacing: 10) {
            deviceIcon(size: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(notice.title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.95))
                if notice.batteryReading?.hasComponents == true && !isLow {
                    componentDetails
                } else { statusLabel }
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
                if notice.batteryReading?.hasComponents == true && !isLow {
                    componentDetails
                } else { statusLabel }
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
            .foregroundStyle(isLow ? accent : .white.opacity(0.92))
            .frame(width: size, height: size)
            .padding(4)
            .background(accent.opacity(isLow ? 0.13 : 0.06), in: RoundedRectangle(cornerRadius: 9))
            .accessibilityHidden(true)
    }

    private var statusLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: isLow ? "exclamationmark.circle.fill" : isPower ? "powerplug" : "checkmark.circle.fill")
                .font(.system(size: 8))
            Text(subtitle).font(.system(size: 9.5, weight: .medium))
        }
        .foregroundStyle(isLow ? accent : .white.opacity(0.55))
    }

    private func componentName(_ component: DeviceBatteryReading.Component) -> String {
        switch component {
        case .main: l10n.string(vi: "Pin", en: "Battery")
        case .left: l10n.string(vi: "Tai trái", en: "Left earbud")
        case .right: l10n.string(vi: "Tai phải", en: "Right earbud")
        case .batteryCase: l10n.string(vi: "Hộp sạc", en: "Case")
        }
    }

    private var componentAccessibility: String? {
        guard let reading = notice.batteryReading, reading.hasComponents else { return nil }
        return reading.alertComponents.compactMap { component -> String? in
            guard let level = reading.level(component) else { return nil }
            return componentName(component) + " \(level)%"
                + (reading.isCharging(component) == true ? l10n.string(vi: ", đang sạc", en: ", charging") : "")
        }.joined(separator: ", ")
    }

    private var componentDetails: some View {
        HStack(spacing: 7) {
            if let reading = notice.batteryReading {
                ForEach([DeviceBatteryReading.Component.left, .right, .batteryCase], id: \.self) { part in
                    if let level = reading.level(part) {
                        HStack(spacing: 2) {
                            Text(part == .left ? l10n.string(vi: "T", en: "L")
                                 : part == .right ? l10n.string(vi: "P", en: "R")
                                 : l10n.string(vi: "Hộp", en: "Case"))
                                .foregroundStyle(.white.opacity(0.4))
                            Text("\(level)%").monospacedDigit()
                            if reading.isCharging(part) == true {
                                Image(systemName: "bolt.fill").foregroundStyle(.green)
                            }
                        }
                    }
                }
            }
        }
        .font(.system(size: 9, weight: .medium))
        .foregroundStyle(.white.opacity(0.8))
    }

    @ViewBuilder
    private func batteryReadout(compact: Bool) -> some View {
        if let percent = notice.percent {
            HStack(spacing: compact ? 5 : 4) {
                Text("\(percent)%")
                    .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(isLow || isPlugged ? accent : .white.opacity(0.9))
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: percent)
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2.5).strokeBorder(accent.opacity(0.3), lineWidth: 1)
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(accent)
                        .frame(width: max(1, 17 * CGFloat(min(100, max(0, percent))) / 100), height: 6)
                        .padding(.leading, 2)
                    if isPlugged || (notice.batteryReading?.charging == true && notice.batteryReading?.hasComponents != true) {
                        Image(systemName: "bolt.fill").font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.black).frame(width: 21, height: 10)
                    }
                }
                .frame(width: 21, height: 10)
                .scaleEffect(compact ? 1 : 0.85)
                .frame(width: compact ? 21 : 18, height: compact ? 10 : 9)
                .accessibilityHidden(true)
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
