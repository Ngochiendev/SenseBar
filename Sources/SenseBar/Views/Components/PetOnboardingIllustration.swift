import SwiftUI

/// Minh họa nhẹ cho lựa chọn thú cưng trong onboarding.
struct PetOnboardingIllustration: View {
    let enabled: Bool
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                LinearGradient(
                    colors: [Color.pink.opacity(0.22), Color.purple.opacity(0.10)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Rectangle().fill(.black.opacity(0.11)).frame(height: 15)

                ZStack {
                    Capsule().fill(.black.opacity(0.9))
                    HStack(spacing: 0) {
                        PetView(look: .standard, mood: enabled ? .wink : .sleepy, size: 18, idles: false)
                            .frame(width: 24, height: 24)
                            .padding(.leading, 4)
                        Spacer(minLength: 0)
                    }
                    Label(
                        enabled ? l10n.string(vi: "Xin chào", en: "Hello")
                            : l10n.string(vi: "Tùy chọn", en: "Optional"),
                        systemImage: enabled ? "hand.wave.fill" : "pawprint.fill"
                    )
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(enabled ? 1 : 0.58))
                }
                .frame(width: min(190, proxy.size.width * 0.58), height: 30)
                .shadow(color: .black.opacity(0.2), radius: 7, y: 3)
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
