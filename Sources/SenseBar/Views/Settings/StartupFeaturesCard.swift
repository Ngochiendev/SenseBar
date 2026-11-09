import AppKit
import SwiftUI

/// Thẻ khởi động cùng máy và bật/tắt 2 tính năng chính.
struct StartupFeaturesCard: View {
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.pillarDynamicIslandEnabled) private var dynamicIslandEnabled: Bool = true
    @AppStorage(DefaultsKey.pillarAudioStudioEnabled) private var audioStudioEnabled: Bool = true
    @State private var launchAtLogin: Bool = LaunchAtLoginManager.isEnabled

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.blue.opacity(0.12))
                        .frame(width: 24, height: 24)
                    Image(systemName: "power")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.blue)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(l10n.s.settingsLaunchAtLogin)
                        .font(.system(size: 12, weight: .semibold))
                    Text(l10n.s.settingsLaunchAtLoginDesc)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { launchAtLogin },
                    set: { newValue in
                        launchAtLogin = newValue
                        LaunchAtLoginManager.setEnabled(newValue)
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
            }

            Divider().opacity(0.4)

            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Theme.iconColor(for: "macbook").opacity(0.15))
                        .frame(width: 24, height: 24)
                    Image(systemName: "macbook")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.iconColor(for: "macbook"))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(l10n.s.pillar1Title)
                        .font(.system(size: 12, weight: .semibold))
                    Text(l10n.s.pillar1Subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Toggle("", isOn: $dynamicIslandEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }

            Divider().opacity(0.4)

            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Theme.iconColor(for: "speaker.wave.2.fill").opacity(0.15))
                        .frame(width: 24, height: 24)
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.iconColor(for: "speaker.wave.2.fill"))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(l10n.s.pillar2Title)
                        .font(.system(size: 12, weight: .semibold))
                    Text(l10n.s.pillar2Subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Toggle("", isOn: $audioStudioEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }
        }
        .panelCard()
    }
}
