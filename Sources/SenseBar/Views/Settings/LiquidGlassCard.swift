import AppKit
import SwiftUI

/// Thẻ bật/tắt hiệu ứng Liquid Glass (macOS 26+).
struct LiquidGlassCard: View {
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.liquidGlassEnabled) private var liquidGlassOtherWindows: Bool = true
    @AppStorage(DefaultsKey.liquidGlassIslandEnabled) private var liquidGlassIsland: Bool = true

    var body: some View {
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
}
