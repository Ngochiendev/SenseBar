import AppKit
import SwiftUI

/// Thẻ chọn màn hình hiển thị Island và hành vi khi chạy toàn màn hình.
struct DisplayTargetCard: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var islandController = IslandController.shared
    @AppStorage(DefaultsKey.notchDisplayTarget) private var displayTarget: String = "all"
    @AppStorage(DefaultsKey.notchExpandAllDisplays) private var expandAllDisplays: Bool = false
    @AppStorage(DefaultsKey.notchHideInFullscreen) private var hideInFullscreen: Bool = true

    var body: some View {
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

                selectionMark(isSelected: isSelected)
            }
            .frame(minHeight: 42)
            .frame(maxWidth: .infinity)
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
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// A fixed trailing control keeps the selection affordance optically centred
    /// regardless of the title and subtitle heights.
    private func selectionMark(isSelected: Bool) -> some View {
        Group {
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(Color.blue, in: Circle())
            } else {
                Circle()
                    .strokeBorder(Color.secondary.opacity(0.32), lineWidth: 1)
                    .frame(width: 18, height: 18)
            }
        }
        .frame(width: 24, height: 24, alignment: .center)
        .accessibilityHidden(true)
    }
}
