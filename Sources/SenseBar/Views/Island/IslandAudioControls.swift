import SwiftUI

/// Compact trigger with an on-demand volume and output panel.
struct IslandAudioControls: View {
    @ObservedObject var audio: AudioStudioService
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.pillarAudioStudioEnabled) private var enabled = true
    @State private var presented = false
    @State private var holdingIsland = false

    private var outputs: [AudioOutputDevice] {
        audio.outputDevices.filter { !audio.hiddenOutputUIDs.contains($0.uid) || $0.id == audio.selectedOutputID }
    }
    private var percent: Int { Int((audio.isMasterMuted ? 0 : audio.masterVolume) * 100) }

    var body: some View {
        Button { presented.toggle() } label: {
            HStack(spacing: 4) {
                Image(systemName: audio.isMasterMuted ? "speaker.slash.fill" : audio.selectedOutputSymbol)
                    .foregroundStyle(audio.isMasterMuted ? .orange : .white.opacity(0.7))
                if audio.canAdjustMasterVolume {
                    Text("\(percent)%").monospacedDigit()
                } else {
                    Image(systemName: "chevron.down").font(.system(size: 7, weight: .semibold))
                }
            }
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(.white.opacity(0.8))
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(.white.opacity(presented ? 0.18 : 0.10), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(l10n.string(vi: "Âm lượng và đầu ra âm thanh", en: "Volume and audio output"))
        .accessibilityLabel(l10n.string(vi: "Âm thanh: ", en: "Audio: ") + audio.outputDeviceName)
        .popover(isPresented: $presented, arrowEdge: .bottom) {
            panel.environment(\.colorScheme, .dark)
                .onExitCommand { presented = false }
        }
        .onChange(of: presented) { _, value in
            if value { holdIsland() } else { releaseIsland() }
        }
        .onChange(of: enabled) { _, value in if !value { presented = false } }
        .onDisappear { presented = false; releaseIsland() }
    }

    private var panel: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button { audio.toggleMasterMute() } label: {
                    Image(systemName: audio.isMasterMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(audio.isMasterMuted ? .orange : .white.opacity(0.85))
                        .frame(width: 28, height: 28)
                        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .disabled(audio.isSwitchingOutput || !audio.canMuteMaster)
                .accessibilityLabel(l10n.string(vi: audio.isMasterMuted ? "Bật tiếng" : "Tắt tiếng",
                                                en: audio.isMasterMuted ? "Unmute" : "Mute"))
                if audio.canAdjustMasterVolume {
                    Slider(value: Binding(get: { audio.isMasterMuted ? 0 : audio.masterVolume },
                                          set: { audio.setMasterVolume($0) }), in: 0...1)
                        .controlSize(.small).tint(.cyan)
                        .disabled(audio.isSwitchingOutput)
                        .accessibilityLabel(l10n.string(vi: "Âm lượng đầu ra", en: "Output volume"))
                    Text("\(percent)%").font(.system(size: 11, weight: .medium).monospacedDigit())
                        .frame(width: 34, alignment: .trailing)
                } else {
                    Text(l10n.string(vi: "Chỉnh âm lượng trên thiết bị", en: "Adjust volume on your device"))
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Divider().overlay(.white.opacity(0.08))
            ScrollView {
                VStack(spacing: 3) {
                    ForEach(outputs) { device in
                        Button { audio.selectOutput(device) } label: {
                            HStack(spacing: 10) {
                                Image(systemName: device.kind.symbol).font(.system(size: 17)).frame(width: 25)
                                Text(device.name).font(.system(size: 11, weight: .medium))
                                    .lineLimit(1).truncationMode(.middle)
                                Spacer(minLength: 4)
                                if device.id == audio.selectedOutputID {
                                    Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold))
                                }
                            }
                            .foregroundStyle(.white.opacity(device.id == audio.selectedOutputID ? 1 : 0.75))
                            .padding(.horizontal, 8).frame(height: 36)
                            .background(.white.opacity(device.id == audio.selectedOutputID ? 0.08 : 0),
                                        in: RoundedRectangle(cornerRadius: 8))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).disabled(audio.isSwitchingOutput)
                        .accessibilityAddTraits(device.id == audio.selectedOutputID ? .isSelected : [])
                    }
                    if outputs.isEmpty {
                        Text(l10n.string(vi: "Không có đầu ra âm thanh", en: "No audio outputs"))
                            .font(.system(size: 11)).foregroundStyle(.secondary).padding(8)
                    }
                }
            }
            .frame(height: min(195, max(36, CGFloat(outputs.count) * 39)))
            if audio.isSwitchingOutput {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text(l10n.string(vi: "Đang chuyển đầu ra…", en: "Switching output…"))
                }.font(.system(size: 10)).foregroundStyle(.secondary)
            } else if audio.outputSwitchFailed || audio.masterControlFailed {
                Label(l10n.string(vi: "Chưa thể áp dụng. Vui lòng thử lại.", en: "Could not apply. Please try again."),
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10)).foregroundStyle(.orange)
            }
        }
        .padding(12).frame(width: 270)
        .onAppear { holdIsland(); audio.startMonitoringApps() }
        .onDisappear { releaseIsland(); audio.stopMonitoringApps() }
    }

    private func holdIsland() {
        guard !holdingIsland else { return }
        holdingIsland = true
        IslandController.shared.beginAudioPopover()
    }

    private func releaseIsland() {
        guard holdingIsland else { return }
        holdingIsland = false
        IslandController.shared.endAudioPopover()
    }
}
