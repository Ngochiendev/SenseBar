import AppKit
import SwiftUI

/// Thẻ chọn kiểu Capsule / Notch cho màn hình không có tai thỏ.
struct NotchStyleCard: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var islandController = NotchDynamicIslandController.shared
    @AppStorage(DefaultsKey.notchStyle) private var notchStyle: String = "notch"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(l10n.string(vi: "Màn hình không có tai thỏ", en: "Displays without a notch"))
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                styleSilhouetteButton(id: "pill", title: l10n.string(vi: "Capsule", en: "Capsule"))
                styleSilhouetteButton(id: "notch", title: l10n.string(vi: "Notch", en: "Notch"))
            }

            if islandController.hasNotchedDisplay {
                notchedDisplayNote
            }
        }
        .panelCard()
    }

    /// Lưu ý: màn hình có tai thỏ thật luôn dùng Notch, lựa chọn trên chỉ áp dụng cho màn hình rời.
    private var notchedDisplayNote: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 10.5))
                .foregroundStyle(.blue)
            Text(l10n.string(
                vi: "Màn hình MacBook có tai thỏ luôn dùng kiểu Notch để ôm sát camera. Lựa chọn trên chỉ áp dụng cho màn hình không có tai thỏ.",
                en: "Notched MacBook displays always use the Notch style to fit the camera. This choice applies only to displays without a notch."
            ))
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.blue.opacity(0.07))
        )
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
}
