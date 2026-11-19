import SwiftUI

/// Edits a pinned app identity while the media source or its activity changes.
struct IslandEqualizerControls: View {
  @ObservedObject var audio: AudioStudioService
  let preferredAppID: String?
  @Binding var presented: Bool
  @ObservedObject private var l10n = L10n.shared
  @AppStorage(DefaultsKey.pillarAudioStudioEnabled) private var enabled = true
  @State private var selectedAppID: String?
  @State private var holdingIsland = false

  private var eligibleApps: [AudioAppEntry] { audio.apps.filter(\.allowsVolumeControl) }
  private var selectedApp: AudioAppEntry? { eligibleApps.first { $0.id == selectedAppID } }
  private var sourceApp: AudioAppEntry? {
    let id = AudioEqualizerTarget.resolve(preferredID: preferredAppID,
      eligibleIDs: eligibleApps.map(\.id), playingIDs: eligibleApps.filter(\.isPlaying).map(\.id))
    return eligibleApps.first { $0.id == id }
  }

  var body: some View {
    Button { presented.toggle() } label: {
      Text("EQ").font(.system(size: 8.5, weight: .bold))
        .foregroundStyle(presented || sourceApp.map { audio.equalizer(for: $0.id).isEffective } == true
                         ? .cyan : .white.opacity(0.75))
        .frame(width: 27, height: 25)
        .background(.white.opacity(presented ? 0.18 : 0.10), in: Capsule())
    }
    .buttonStyle(.plain)
    .disabled(!enabled || !audio.isPerAppMixerSupported)
    .help(l10n.string(vi: "Chỉnh EQ ứng dụng đang phát", en: "Adjust the playing app's EQ"))
    .accessibilityLabel(l10n.string(vi: "Bộ chỉnh âm ứng dụng", en: "App equalizer"))
    .popover(isPresented: $presented, arrowEdge: .bottom) {
      content.environment(\.colorScheme, .dark)
        .onExitCommand { presented = false }
    }
    .onChange(of: presented) { _, open in
      if open { selectedAppID = sourceApp?.id; holdIsland() }
      else { releaseIsland() }
    }
    .onChange(of: enabled) { _, active in if !active { presented = false } }
    .onDisappear { presented = false; releaseIsland() }
  }

  private var content: some View {
    VStack(spacing: 0) {
      if !eligibleApps.isEmpty {
        Menu {
          ForEach(eligibleApps) { app in
            Button { selectedAppID = app.id } label: {
              if selectedAppID == app.id { Label(app.name, systemImage: "checkmark") }
              else { Text(app.name) }
            }
          }
        } label: {
          HStack {
            Text(l10n.string(vi: "Ứng dụng", en: "Application")).foregroundStyle(.secondary)
            Spacer()
            Text(selectedApp?.name ?? l10n.string(vi: "Chọn ứng dụng", en: "Choose app")).lineLimit(1)
          }.font(.system(size: 10.5))
        }
        .menuStyle(.borderlessButton)
        .padding(.horizontal, 18).padding(.top, 12)
      }
      if let app = selectedApp {
        AudioEqualizerEditor(app: app, audio: audio).id(app.id)
      } else {
        VStack(spacing: 10) {
          Image(systemName: "slider.vertical.3").font(.system(size: 22)).foregroundStyle(.cyan)
          Text(l10n.string(vi: "Chọn ứng dụng để chỉnh EQ", en: "Choose an app to adjust EQ"))
            .font(.system(size: 12, weight: .semibold))
          Text(l10n.string(
            vi: "Nguồn đang chọn chưa có trong mixer hoặc không hỗ trợ EQ. Phát âm thanh rồi chọn ứng dụng ở trên.",
            en: "The selected source isn't in the mixer or doesn't support EQ. Play audio, then choose an app above."))
            .font(.system(size: 10.5)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.padding(22)
      }
    }
    .frame(width: 350)
    .onAppear {
      holdIsland()
      audio.startMonitoringApps()
      if selectedAppID == nil { selectedAppID = sourceApp?.id }
    }
    .onChange(of: audio.apps) { _, _ in
      if selectedAppID == nil { selectedAppID = sourceApp?.id }
    }
    .onDisappear { audio.stopMonitoringApps(); releaseIsland() }
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
