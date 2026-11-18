import AppKit
import SwiftUI

/// Audio Studio: one output surface and a compact, activity-aware app mixer.
struct AudioMixerSection: View {
  @ObservedObject private var l10n = L10n.shared
  @ObservedObject private var audio = AudioStudioService.shared
  @State private var showOutputs = false
  @State private var showInactive = false
  @State private var frozenPrimaryIDs: Set<String>?

  private var primaryApps: [AudioAppEntry] {
    audio.apps.filter {
      frozenPrimaryIDs?.contains($0.id) ?? $0.isPlaying
    }
  }

  private var inactiveApps: [AudioAppEntry] {
    let ids = Set(primaryApps.map(\.id))
    return audio.apps.filter { !ids.contains($0.id) }
  }

  private var listHeight: CGFloat {
    let count = primaryApps.count + (showInactive ? inactiveApps.count : 0)
    return min(
      240, CGFloat(count) * 54 + (inactiveApps.isEmpty ? 0 : 28) + (primaryApps.isEmpty ? 30 : 0))
  }

  var body: some View {
    VStack(spacing: 8) {
      outputCard
      mixerCard
    }
    .onAppear { audio.startMonitoringApps() }
    .onDisappear {
      audio.stopMonitoringApps()
      frozenPrimaryIDs = nil
    }
  }

  private var outputCard: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        Image(systemName: audio.selectedOutputSymbol)
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(Color.accentColor)
          .frame(width: 32, height: 32)
          .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
          .overlay {
            RoundedRectangle(cornerRadius: 9)
              .strokeBorder(Color.accentColor.opacity(0.22), lineWidth: 0.75)
          }
          .overlay {
            if audio.isSwitchingOutput {
              ProgressView().controlSize(.small)
                .frame(width: 32, height: 32)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9))
            }
          }

        VStack(alignment: .leading, spacing: 3) {
          Text(l10n.string(vi: "ÂM THANH ĐẦU RA", en: "AUDIO OUTPUT"))
            .font(.system(size: 8.5, weight: .semibold))
            .tracking(0.7)
            .foregroundStyle(.secondary)
          Text(audio.outputDeviceName)
            .font(.system(size: 11.5, weight: .semibold))
            .lineLimit(1)
            .help(audio.outputDeviceName)
        }
        Spacer(minLength: 0)
        Button {
          showOutputs = true
        } label: {
          HStack(spacing: 4) {
            Text(l10n.string(vi: "Đổi", en: "Change"))
            Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .semibold))
          }
          .font(.system(size: 10.5, weight: .medium))
          .padding(.horizontal, 4)
          .padding(.vertical, 2)
          .contentShape(Capsule())
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.mini)
        .popover(isPresented: $showOutputs, arrowEdge: .trailing) {
          AudioOutputPicker(audio: audio)
        }
        .accessibilityLabel(
          l10n.string(vi: "Chọn thiết bị phát âm thanh", en: "Choose audio output"))
      }

      if audio.canAdjustMasterVolume {
        HStack(spacing: 7) {
          Button {
            audio.toggleMasterMute()
          } label: {
            Image(systemName: audio.isMasterMuted ? "speaker.slash.fill" : "speaker.fill")
              .font(.system(size: 11))
              .frame(width: 20, height: 20)
          }
          .buttonStyle(.plain)
          .foregroundStyle(audio.isMasterMuted ? .orange : .secondary)
          .disabled(!audio.canMuteMaster)
          .accessibilityLabel(l10n.string(vi: "Bật hoặc tắt tiếng", en: "Toggle mute"))
          Slider(
            value: Binding(
              get: { audio.isMasterMuted ? 0 : audio.masterVolume },
              set: { audio.setMasterVolume($0) }
            ), in: 0...1
          )
          .controlSize(.small)
          .accessibilityLabel(l10n.string(vi: "Âm lượng đầu ra", en: "Output volume"))
          Text("\(Int((audio.isMasterMuted ? 0 : audio.masterVolume) * 100))%")
            .font(.system(size: 10.5, weight: .medium).monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(width: 33, alignment: .trailing)
        }
        .frame(height: 22)
      } else {
        Label(
          l10n.string(vi: "Chỉnh âm lượng trên thiết bị này", en: "Adjust volume on this device"),
          systemImage: "speaker.badge.exclamationmark"
        )
        .font(.system(size: 10.5)).foregroundStyle(.secondary)
        .lineLimit(1)
        .frame(height: 22)
      }
      if audio.outputSwitchFailed {
        Label(
          l10n.string(
            vi: "Không chuyển được. Kiểm tra kết nối rồi thử lại.",
            en: "Couldn't switch. Check the connection and try again."),
          systemImage: "exclamationmark.circle"
        )
        .font(.system(size: 10.5)).foregroundStyle(.orange)
      }
    }
    .panelCard()
  }

  private var mixerCard: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(l10n.string(vi: "Ứng dụng", en: "Applications"))
          .font(.system(size: 12, weight: .semibold))
        Spacer()
        Text("0–200%")
          .font(.system(size: 9.5).monospacedDigit())
          .foregroundStyle(.tertiary)
      }
      if !audio.isPerAppMixerSupported {
        mixerNotice(
          l10n.string(
            vi: "Cần macOS 14.4 trở lên để chỉnh từng ứng dụng.",
            en: "Per-app volume requires macOS 14.4 or later."))
      } else {
        if audio.needsAudioPermission {
          Label(
            l10n.string(
              vi: "Cho phép Ghi âm hệ thống để sử dụng mixer.",
              en: "Allow System Audio Recording to use the mixer."),
            systemImage: "waveform.badge.exclamationmark"
          )
          .font(.system(size: 10.5)).foregroundStyle(.orange)
        }
        if audio.apps.isEmpty {
          mixerNotice(
            l10n.string(
              vi: "Phát nhạc hoặc video để ứng dụng xuất hiện tại đây.",
              en: "Play music or a video to see its app here."))
        } else {
          ScrollView {
            VStack(spacing: 0) {
              if primaryApps.isEmpty {
                Text(l10n.string(vi: "Chưa có ứng dụng đang phát", en: "No apps playing"))
                  .font(.system(size: 10.5)).foregroundStyle(.secondary)
                  .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
              }
              ForEach(primaryApps) { app in appRow(app) }
              if !inactiveApps.isEmpty {
                DisclosureGroup(isExpanded: $showInactive) {
                  VStack(spacing: 0) {
                    ForEach(inactiveApps) { app in appRow(app) }
                  }
                } label: {
                  Text(l10n.string(vi: "Đang nghỉ", en: "Idle") + " · \(inactiveApps.count)")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
                }
              }
            }
            .padding(.trailing, 7)
            .background(CompactAudioScrollStyle())
          }
          .frame(height: listHeight)
          .scrollIndicators(.automatic)
        }
      }
    }
    .panelCard()
  }

  private func mixerNotice(_ text: String) -> some View {
    Text(text).font(.system(size: 10.5)).foregroundStyle(.secondary)
      .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
  }

  private func appRow(_ app: AudioAppEntry) -> some View {
    AudioStudioAppRow(app: app, audio: audio) { editing in
      frozenPrimaryIDs = editing ? Set(primaryApps.map(\.id)) : nil
    }
  }
}

/// Configures only this mixer's native scroll view, leaving system-wide
/// scrollbar preferences and other SenseBar surfaces untouched.
private struct CompactAudioScrollStyle: NSViewRepresentable {
  func makeNSView(context: Context) -> ScrollProbe { ScrollProbe() }

  func updateNSView(_ view: ScrollProbe, context: Context) { view.configureWhenAttached() }

  final class ScrollProbe: NSView {
    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      configureWhenAttached()
    }

    override func viewDidMoveToSuperview() {
      super.viewDidMoveToSuperview()
      configureWhenAttached()
    }

    func configureWhenAttached() {
      DispatchQueue.main.async { [weak self] in
        guard let scroll = self?.enclosingScrollView else { return }
        scroll.scrollerStyle = .overlay
        scroll.verticalScroller?.controlSize = .small
        scroll.autohidesScrollers = true
        scroll.hasHorizontalScroller = false
      }
    }
  }
}

private struct AudioOutputPicker: View {
  @ObservedObject var audio: AudioStudioService
  @ObservedObject private var l10n = L10n.shared
  @Environment(\.dismiss) private var dismiss
  @State private var managing = false

  private var devices: [AudioOutputDevice] {
    audio.outputDevices.filter {
      managing || !audio.hiddenOutputUIDs.contains($0.uid) || $0.id == audio.selectedOutputID
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text(l10n.string(vi: "Chọn đầu ra", en: "Choose output"))
          .font(.system(size: 12, weight: .semibold))
        Spacer()
        Button(l10n.string(vi: managing ? "Xong" : "Sửa", en: managing ? "Done" : "Edit")) {
          managing.toggle()
        }
        .font(.system(size: 10.5)).buttonStyle(.plain).foregroundStyle(.tint)
      }
      if devices.isEmpty {
        Text(l10n.string(vi: "Chưa có thiết bị kết nối", en: "No outputs connected"))
          .font(.system(size: 11)).foregroundStyle(.secondary)
      }
      ScrollView {
        VStack(spacing: 4) {
          ForEach(devices) { device in deviceRow(device) }
        }
      }
      .frame(height: min(280, CGFloat(devices.count) * 52))
      if managing {
        Text(
          l10n.string(
            vi: "Ẩn chỉ dọn danh sách SenseBar. Thiết bị vẫn kết nối với macOS.",
            en: "Hiding only changes this list. Devices stay connected to macOS.")
        )
        .font(.system(size: 10)).foregroundStyle(.secondary)
      }
    }
    .padding(14)
    .frame(width: 280)
  }

  private func deviceRow(_ device: AudioOutputDevice) -> some View {
    let selected = device.id == audio.selectedOutputID
    let hidden = audio.hiddenOutputUIDs.contains(device.uid)
    return HStack(spacing: 4) {
      Button {
        if !selected { audio.selectOutput(device) }
        dismiss()
      } label: {
        HStack(spacing: 10) {
          Image(systemName: device.kind.symbol)
            .font(.system(size: 17)).frame(width: 26)
          VStack(alignment: .leading, spacing: 3) {
            Text(device.name).font(.system(size: 11.5, weight: selected ? .semibold : .regular))
              .lineLimit(1)
            Text(
              selected
                ? l10n.string(vi: "Đang sử dụng", en: "Selected")
                : hidden
                  ? l10n.string(vi: "Đã ẩn", en: "Hidden")
                  : device.canAdjustVolume
                    ? l10n.string(vi: "Sẵn sàng", en: "Available")
                    : l10n.string(vi: "Âm lượng cố định", en: "Fixed volume")
            )
            .font(.system(size: 9.5)).foregroundStyle(.secondary)
          }
          Spacer(minLength: 4)
          if selected {
            Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
              .foregroundStyle(.tint)
          }
        }
        .padding(9)
        .background(
          selected ? Color.accentColor.opacity(0.09) : Color.clear,
          in: RoundedRectangle(cornerRadius: 10)
        )
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .disabled(audio.isSwitchingOutput)
      .accessibilityAddTraits(selected ? .isSelected : [])
      if managing && !selected {
        Button {
          audio.setOutputHidden(device, hidden: !hidden)
        } label: {
          Image(systemName: hidden ? "eye.slash" : "eye")
            .font(.system(size: 11)).frame(width: 26, height: 30)
        }
        .buttonStyle(.plain).foregroundStyle(.secondary)
        .help(
          l10n.string(
            vi: hidden ? "Hiện thiết bị" : "Ẩn thiết bị",
            en: hidden ? "Show output" : "Hide output"))
      }
    }
  }
}

private struct AudioStudioAppRow: View {
  let app: AudioAppEntry
  @ObservedObject var audio: AudioStudioService
  let onEditing: (Bool) -> Void
  @ObservedObject private var l10n = L10n.shared
  @State private var editing = false
  @State private var percent = ""
  @FocusState private var focused: Bool

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      Image(nsImage: app.icon).resizable().aspectRatio(contentMode: .fit)
        .frame(width: 24, height: 24).padding(.top, 2)
      VStack(alignment: .leading, spacing: 3) {
        HStack(spacing: 6) {
          Text(app.name).font(.system(size: 11.5, weight: .medium)).lineLimit(1)
            .help(app.name)
          if app.isPlaying {
            Circle().fill(.green).frame(width: 4, height: 4)
              .accessibilityLabel(l10n.string(vi: "Đang phát", en: "Playing"))
          }
          Spacer(minLength: 2)
          if app.allowsVolumeControl { percentageControl }
        }
        if app.allowsVolumeControl {
          HStack(spacing: 6) {
            Button {
              audio.toggleAppMute(id: app.id)
            } label: {
              Image(systemName: app.isMuted ? "speaker.slash.fill" : "speaker.fill")
                .font(.system(size: 10)).frame(width: 16, height: 20)
            }
            .buttonStyle(.plain).foregroundStyle(app.isMuted ? .orange : .secondary)
            .accessibilityLabel(l10n.string(vi: "Bật hoặc tắt tiếng", en: "Toggle mute"))
            Slider(
              value: Binding(
                get: { app.volume },
                set: { audio.setAppVolume(id: app.id, volume: $0) }),
              in: 0...2, onEditingChanged: onEditing
            )
            .controlSize(.mini).tint(app.volume > 1 ? .orange : .accentColor)
            .accessibilityLabel(app.name)
            Button {
              audio.setAppVolume(id: app.id, volume: 1)
            } label: {
              Image(systemName: "arrow.counterclockwise").font(.system(size: 9))
                .frame(width: 18, height: 20)
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
            .disabled(abs(app.volume - 1) < 0.005)
            .help(l10n.string(vi: "Đặt lại 100%", en: "Reset to 100%"))
          }
        } else {
          Label(
            l10n.string(vi: "Bảo vệ âm thanh cuộc gọi", en: "Call audio protected"),
            systemImage: "checkmark.shield"
          )
          .font(.system(size: 9.5)).foregroundStyle(.secondary)
          .frame(height: 20)
        }
      }
    }
    .padding(.vertical, 6)
    .onDisappear {
      if editing { onEditing(false) }
    }
  }

  @ViewBuilder private var percentageControl: some View {
    if editing {
      TextField("%", text: $percent).textFieldStyle(.plain)
        .font(.system(size: 11).monospacedDigit()).multilineTextAlignment(.trailing)
        .frame(width: 40).focused($focused)
        .onSubmit { commitPercent() }
        .onExitCommand {
          editing = false
          onEditing(false)
        }
        .onChange(of: focused) { _, value in if !value { commitPercent() } }
        .accessibilityLabel(l10n.string(vi: "Phần trăm âm lượng", en: "Volume percent"))
    } else {
      Button {
        percent = String(Int((app.volume * 100).rounded()))
        editing = true
        onEditing(true)
        focused = true
      } label: {
        HStack(spacing: 4) {
          if app.volume > 1 {
            Text(String(format: "+%.1f dB", 20 * log10(app.volume)))
              .font(.system(size: 8.5))
          }
          Text("\(Int((app.volume * 100).rounded()))%")
            .font(.system(size: 11, weight: .medium))
        }
        .monospacedDigit().foregroundStyle(app.volume > 1 ? .orange : .secondary)
      }
      .buttonStyle(.plain)
      .help(l10n.string(vi: "Nhập âm lượng chính xác", en: "Enter exact volume"))
    }
  }

  private func commitPercent() {
    guard editing else { return }
    editing = false
    onEditing(false)
    if let value = Double(percent.replacingOccurrences(of: "%", with: "")), value.isFinite {
      audio.setAppVolume(id: app.id, volume: min(200, max(0, value)) / 100)
    }
  }
}
