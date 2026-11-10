import AppKit
import SwiftUI

/// Tab Loa & Ứng dụng: minh họa bộ trộn âm lượng và danh sách ứng dụng đang phát.
struct AudioMixerSection: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var music = MusicService.shared
    @ObservedObject private var audio = AudioStudioService.shared

    var body: some View {
        VStack(spacing: 8) {
            // Khung Ảnh Example trực quan cho Bộ trộn âm lượng nhiều ứng dụng
            audioMixerExampleCard

            // Khung Loa chính (Master Output)
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Image(systemName: audio.isMasterMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(audio.outputDeviceName)
                        .font(.system(size: 12, weight: .bold))
                        .lineLimit(1)
                    Spacer()
                    Text("\(Int((audio.isMasterMuted ? 0 : audio.masterVolume) * 100))%")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    Button {
                        audio.toggleMasterMute()
                    } label: {
                        Image(systemName: audio.isMasterMuted ? "speaker.slash.fill" : "speaker.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(audio.isMasterMuted ? .orange : .secondary)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Color.primary.opacity(0.06)))
                    }
                    .buttonStyle(.plain)

                    Slider(
                        value: Binding(
                            get: { audio.isMasterMuted ? 0 : audio.masterVolume },
                            set: { audio.setMasterVolume($0) }
                        ),
                        in: 0...1
                    )
                    .controlSize(.small)
                }
            }
            .panelCard()

            // Khung Điều chỉnh âm lượng từng ứng dụng (0% - 200%)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(l10n.string(vi: "Âm lượng từng ứng dụng", en: "Per-App Volume"))
                        .font(.system(size: 12, weight: .bold))
                    Spacer()
                    Text("0% – 200%")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.primary.opacity(0.06)))
                }

                VStack(spacing: 7) {
                    ForEach(audio.apps.prefix(4)) { app in
                        appVolumeRow(app)
                    }
                }
            }
            .panelCard()
        }
    }

    private var audioMixerExampleCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label(
                    l10n.string(vi: "Minh họa Bộ trộn đa ứng dụng", en: "Multi-App Mixer Example"),
                    systemImage: "slider.horizontal.below.rectangle"
                )
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.secondary)

                Spacer()

                Text(l10n.string(vi: "Độc lập từng App", en: "Independent Gain"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            // Hình Example trực quan hiển thị 3 thanh sóng ứng dụng độc lập
            HStack(spacing: 8) {
                exampleAppBar(name: "Music", percent: "140%", ratio: 0.85, symbol: "music.note")
                exampleAppBar(name: "Chrome", percent: "75%", ratio: 0.50, symbol: "globe")
                exampleAppBar(name: "Spotify", percent: "100%", ratio: 0.68, symbol: "waveform")
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
        }
        .panelCard()
    }

    private func exampleAppBar(name: String, percent: String, ratio: CGFloat, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(name)
                    .font(.system(size: 9.5, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(percent)
                    .font(.system(size: 8.5, weight: .bold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.10))
                        .frame(height: 4)
                    Capsule()
                        .fill(Color.primary.opacity(0.65))
                        .frame(width: geo.size.width * ratio, height: 4)
                }
            }
            .frame(height: 4)
        }
        .padding(7)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.7))
        )
    }

    private func appVolumeRow(_ app: AudioAppEntry) -> some View {
        HStack(spacing: 8) {
            Image(nsImage: app.icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 20, height: 20)

            Text(app.name)
                .font(.system(size: 11.5, weight: .medium))
                .lineLimit(1)
                .frame(width: 78, alignment: .leading)

            Button {
                audio.toggleAppMute(id: app.id)
            } label: {
                Image(systemName: app.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 10.5))
                    .foregroundStyle(app.isMuted ? .orange : .secondary)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)

            Slider(
                value: Binding(
                    get: { app.isMuted ? 0 : app.volume },
                    set: { audio.setAppVolume(id: app.id, volume: $0) }
                ),
                in: 0...2.0
            )
            .controlSize(.mini)

            Text("\(Int(((app.isMuted ? 0 : app.volume) * 100).rounded()))%")
                .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)
        }
    }
}
