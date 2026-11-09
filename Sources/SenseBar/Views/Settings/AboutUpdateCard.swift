import AppKit
import SwiftUI

/// Thẻ quyền Trợ năng, thông tin ứng dụng và kiểm tra cập nhật.
struct AboutUpdateCard: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = PermissionManager.shared
    @ObservedObject private var updateService = UpdateService.shared
    @AppStorage(DefaultsKey.autoCheckUpdates) private var autoCheckUpdates: Bool = true

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: permissions.allRequiredGranted ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(permissions.allRequiredGranted ? Color.green : Color.orange)

                    Text(l10n.string(vi: "Quyền Trợ năng (Accessibility)", en: "Accessibility Permission"))
                        .font(.system(size: 11.5, weight: .medium))
                }

                Spacer()

                if !permissions.allRequiredGranted {
                    Button {
                        PermissionManager.shared.requestAccessibility()
                    } label: {
                        Text(l10n.string(vi: "Cấp quyền", en: "Grant"))
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.blue, in: Capsule())
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(l10n.string(vi: "Đã bật", en: "Granted"))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.green)
                }
            }

            Divider().opacity(0.4)

            // Thông tin SenseBar: App Logo + Tên + Phiên bản + Giấy phép GPL v3 + GitHub
            HStack(spacing: 9) {
                BrandBadge(size: 34)

                VStack(alignment: .leading, spacing: 2.5) {
                    HStack(spacing: 5) {
                        Text(AppInfo.name)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.primary)

                        Text("v\(AppInfo.version)")
                            .font(.system(size: 9.5, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.primary.opacity(0.75))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                Capsule().fill(Color.primary.opacity(0.08))
                            )
                    }

                    HStack(spacing: 4) {
                        Text(AppInfo.author)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        Text("•")
                            .font(.system(size: 8))
                            .foregroundStyle(.tertiary)

                        Text("GPL v3.0")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(Color.blue)
                            .padding(.horizontal, 4.5)
                            .padding(.vertical, 1)
                            .background(
                                Capsule().fill(Color.blue.opacity(0.12))
                            )
                    }
                }

                Spacer(minLength: 4)

                Button {
                    NSWorkspace.shared.open(AppInfo.repositoryURL)
                } label: {
                    HStack(spacing: 4) {
                        if let svg = BrandIconResources.svgImage(named: "github") {
                            Image(nsImage: svg)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 12, height: 12)
                        } else {
                            Image(systemName: "link")
                                .font(.system(size: 9))
                        }
                        Text("GitHub")
                            .font(.system(size: 10.5, weight: .medium))
                    }
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            Divider().opacity(0.4)

            updateSectionView
        }
        .panelCard()
    }

    @ViewBuilder
    private var updateSectionView: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let release = updateService.availableRelease {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.blue)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(l10n.string(
                            vi: "Có bản mới v\(release.version)",
                            en: "Update v\(release.version) available"
                        ))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.primary)

                        Button {
                            updateService.openReleaseNotes()
                        } label: {
                            Text(l10n.string(vi: "Xem thay đổi →", en: "Release notes →"))
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundStyle(.blue)
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    Button {
                        updateService.openDownloadPage()
                    } label: {
                        Text(l10n.string(vi: "Tải về", en: "Download"))
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Color.blue, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.blue.opacity(0.09))
                )
            } else {
                HStack(spacing: 8) {
                    updateStatusLabel

                    Spacer()

                    Button {
                        updateService.checkForUpdates(manual: true)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 9.5, weight: .semibold))
                            Text(l10n.string(vi: "Kiểm tra cập nhật", en: "Check for Updates"))
                                .font(.system(size: 10.5, weight: .medium))
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(updateService.status == .checking)
                }
            }

            HStack(spacing: 8) {
                Text(l10n.string(vi: "Tự động kiểm tra cập nhật", en: "Automatically check for updates"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Spacer()

                Toggle("", isOn: $autoCheckUpdates)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }
        }
    }

    @ViewBuilder
    private var updateStatusLabel: some View {
        switch updateService.status {
        case .checking:
            HStack(spacing: 5) {
                ProgressView()
                    .controlSize(.mini)
                Text(l10n.string(vi: "Đang kiểm tra...", en: "Checking..."))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
        case .upToDate:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.green)
                Text(l10n.string(vi: "Đã là bản mới nhất", en: "Up to date"))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        case .failed:
            HStack(spacing: 4) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                Text(l10n.string(vi: "Không thể kết nối", en: "Could not reach"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
        case .idle, .updateAvailable:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                Text("v\(AppInfo.version)")
                    .font(.system(size: 10.5).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
