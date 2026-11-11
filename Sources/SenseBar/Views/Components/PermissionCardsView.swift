import SwiftUI

struct PermissionSectionCard: View {
    @ObservedObject var permissions = PermissionManager.shared
    @ObservedObject var l10n = L10n.shared
    var compact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PermissionRow(
                title: l10n.string(vi: "Trợ năng (Accessibility)", en: "Accessibility"),
                description: l10n.string(
                    vi: "Cần thiết để điều khiển Tai thỏ & Dynamic Island, nhận diện cửa sổ toàn màn hình và hỗ trợ phím tắt âm thanh.",
                    en: "Required for Dynamic Island interactions, fullscreen detection, and audio hotkeys."
                ),
                granted: permissions.accessibilityGranted,
                l10n: l10n,
                requestAction: { permissions.requestAccessibility() },
                openAction: { permissions.openAccessibilitySettings() }
            )
        }
        .padding(compact ? 14 : 16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        )
    }
}

struct PermissionRow: View {
    let title: String
    let description: String
    let granted: Bool
    let l10n: L10n
    let requestAction: () -> Void
    let openAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(granted ? .green : .orange)
                Text(title)
                    .font(.system(size: 13.5, weight: .medium))
                Spacer()
                Text(granted
                     ? l10n.string(vi: "Đã cấp quyền", en: "Granted")
                     : l10n.string(vi: "Cần cấp quyền", en: "Not Granted"))
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(granted ? .green : .orange)
            }

            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !granted {
                HStack(spacing: 8) {
                    Button(l10n.string(vi: "Cấp quyền ngay", en: "Request Permission"), action: requestAction)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    Button(l10n.string(vi: "Mở Cài đặt Hệ thống", en: "Open System Settings"), action: openAction)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                .padding(.top, 2)
            }
        }
    }
}
