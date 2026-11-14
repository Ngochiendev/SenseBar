import AppKit
import SwiftUI

/// Thẻ minh họa Dynamic Island hiển thị trực tiếp ảnh GIF thực tế trong menu chính.
struct IslandPreviewCard: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var islandController = IslandController.shared
    @AppStorage(DefaultsKey.notchStyle) private var notchStyle: String = "notch"

    /// Capsule chỉ có hiệu lực khi có màn hình không tai thỏ, ngược lại luôn là Notch.
    private var showsCapsule: Bool {
        notchStyle == "pill" && islandController.canChooseStyle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(
                    l10n.string(vi: "Minh họa Dynamic Island", en: "Dynamic Island Example"),
                    systemImage: "eye.fill"
                )
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.secondary)

                Spacer()

                Text(showsCapsule
                     ? l10n.string(vi: "Kiểu Viên nang", en: "Pill Style")
                     : l10n.string(vi: "Kiểu Tai thỏ", en: "Notch Style"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.blue.opacity(0.10)))
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.blue.opacity(0.28), lineWidth: 0.8)
                    )
            }

            if let gifURL = BrandIconResources.previewGIFURL(isCapsule: showsCapsule) {
                AnimatedGIFView(url: gifURL)
                    .aspectRatio(1120.0 / 500.0, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
        }
        .panelCard()
    }
}

/// Gắn trực tiếp file GIF vào `NSImageView` có sẵn của macOS (`animates = true`).
private struct AnimatedGIFView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> NSImageView {
        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.animates = true
        imageView.canDrawSubviewsIntoLayer = true
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return imageView
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {
        nsView.image = NSImage(contentsOf: url)
        nsView.animates = true
    }
}
