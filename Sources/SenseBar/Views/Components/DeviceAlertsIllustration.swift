import SwiftUI

/// Minh họa code-native cho thông báo phụ kiện, không cần tài nguyên ảnh bitmap.
struct DeviceAlertsIllustration: View {
    let enabled: Bool
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                LinearGradient(
                    colors: [Color.blue.opacity(0.24), Color.purple.opacity(0.10)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                HStack(spacing: 4) {
                    Circle().fill(.white.opacity(0.55)).frame(width: 3, height: 3)
                    Spacer()
                    Circle().fill(.white.opacity(0.35)).frame(width: 3, height: 3)
                    Circle().fill(.white.opacity(0.35)).frame(width: 3, height: 3)
                }
                .padding(.horizontal, 9).frame(height: 15)
                .background(.black.opacity(0.12))

                HStack(spacing: 7) {
                    Image(systemName: "airpodspro")
                        .font(.system(size: 12, weight: .semibold))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("AirPods Pro").font(.system(size: 9, weight: .semibold))
                        Text(enabled
                             ? l10n.string(vi: "Đã kết nối · 88%", en: "Connected · 88%")
                             : l10n.string(vi: "Thông báo khi bạn cho phép", en: "Alerts when you allow"))
                            .font(.system(size: 7.5)).foregroundStyle(.white.opacity(0.65))
                    }
                    Image(systemName: enabled ? "battery.100percent" : "bell.slash.fill")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(enabled ? Color.green : Color.white.opacity(0.55))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 11).padding(.vertical, 7)
                .background(.black.opacity(0.88), in: Capsule())
                .shadow(color: .black.opacity(0.18), radius: 7, y: 3)
                .position(x: proxy.size.width / 2, y: proxy.size.height * 0.56)
                .scaleEffect(enabled && !reduceMotion ? 1 : 0.97)
                .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.78), value: enabled)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.12)))
        }
        .accessibilityHidden(true)
    }
}
