import SwiftUI
import SenseBarAudioBridge

/// Shared per-app EQ editor for Audio Studio and Island.
struct AudioEqualizerEditor: View {
  let app: AudioAppEntry
  @ObservedObject var audio: AudioStudioService
  @ObservedObject private var l10n = L10n.shared

  private var curve: AppEqualizer { audio.equalizer(for: app.id).normalized }
  private var available: Bool { SensePillar.audioStudio.isEnabled() && audio.apps.contains { $0.id == app.id && $0.allowsVolumeControl } }

  private var canAdjust: Bool { available && curve.enabled }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(spacing: 10) {
        Image(nsImage: app.icon).resizable().frame(width: 30, height: 30)
        VStack(alignment: .leading, spacing: 3) {
          Text(app.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
          Text(l10n.string(vi: "EQ RIÊNG ỨNG DỤNG · ±12 dB", en: "PER-APP EQUALIZER · ±12 dB"))
            .font(.system(size: 8.5, weight: .medium)).tracking(1).foregroundStyle(.secondary)
        }
        Spacer()
        Toggle(l10n.string(vi: "Bật EQ", en: "Enable EQ"), isOn: Binding(
          get: { curve.enabled }, set: { value in setEnabled(value) }))
          .accessibilityLabel(l10n.string(vi: "Bật EQ cho ứng dụng", en: "Enable app equalizer"))
          .labelsHidden().toggleStyle(EqualizerSwitchStyle()).controlSize(.small).disabled(!available)
      }
      EqualizerResponseGraph(gains: curve.gains, sampleRate: audio.equalizerSampleRate(for: app.id))
        .equatable()
        .frame(height: 100).opacity(curve.enabled ? 1 : 0.45)
      HStack {
        Menu {
          ForEach(AppEqualizer.presets.indices, id: \.self) { index in
            let preset = AppEqualizer.presets[index]
            Button(l10n.string(vi: preset.vi, en: preset.en)) {
              edit { $0.gains = preset.gains }
            }
          }
        } label: {
          Text(presetName).font(.system(size: 11, weight: .medium))
        }.menuStyle(.borderlessButton).fixedSize().disabled(!canAdjust)
        Spacer()

      }
      HStack(alignment: .top, spacing: 18) {
        ForEach(0..<5, id: \.self) { index in
          VStack(spacing: 8) {
            Text(String(format: "%+.1f", curve.gains[index])).monospacedDigit()
              .font(.system(size: 11, weight: .semibold)).foregroundStyle(.tint)
            EqualizerBandSlider(value: Binding(get: { Double(curve.gains[index]) }, set: { value in
              edit { $0.gains[index] = Float(value) }
            }))
              .frame(width: 30, height: 104)
              .accessibilityLabel("\(AppEqualizer.frequencies[index]) Hz")
              .accessibilityValue("\(curve.gains[index]) dB")
            Text(["60", "250", "1k", "4k", "12k"][index]).font(.system(size: 10)).foregroundStyle(.secondary)
          }.frame(maxWidth: .infinity)
        }
      }.disabled(!canAdjust).opacity(canAdjust ? 1 : 0.45)
      HStack {
        Label(status, systemImage: audio.appProcessing[app.id] == "failed" ? "exclamationmark.circle" : "waveform")
          .font(.system(size: 10)).foregroundStyle(audio.appProcessing[app.id] == "failed" ? .orange : .secondary)
        Spacer()
        Button(l10n.string(vi: "Đặt lại", en: "Reset")) {
          edit { $0.gains = [0, 0, 0, 0, 0] }
        }.buttonStyle(.plain).font(.system(size: 10)).disabled(!canAdjust)
      }
    }
    .padding(18).frame(width: 350)
    // Floating panels stay nonactivating; appearance follows EQ availability,
    // while disabled controls still use SwiftUI's separate isEnabled state.
    .environment(\.controlActiveState, .active)
    .tint(Color.accentColor)
    .onDisappear { audio.flushAudioSettings() }
  }

  private var status: String {
    if !SensePillar.audioStudio.isEnabled() { return l10n.string(vi: "Audio Studio đang tắt", en: "Audio Studio is off") }
    if !available { return l10n.string(vi: "Ứng dụng đã đóng", en: "App closed") }
    if !curve.enabled { return l10n.string(vi: "Bật EQ để điều chỉnh", en: "Enable EQ to adjust") }
    switch audio.appProcessing[app.id] {
    case "failed": return l10n.string(vi: "Chưa áp dụng được · kiểm tra quyền hoặc đầu ra", en: "Not applied · check access or output")
    case "pending": return l10n.string(vi: "Đang chuẩn bị…", en: "Preparing…")
    default: return l10n.string(vi: curve.isEffective ? "EQ + bảo vệ đỉnh âm" : "Âm thanh nguyên bản", en: curve.isEffective ? "EQ + peak protection" : "Original tone")
    }
  }
  private var presetName: String {
    guard let preset = AppEqualizer.presets.first(where: { $0.gains == curve.gains }) else {
      return l10n.string(vi: "Tùy chỉnh", en: "Custom")
    }
    return l10n.string(vi: preset.vi, en: preset.en)
  }
  private func setEnabled(_ enabled: Bool) {
    guard available else { return }
    var settings = curve
    settings.enabled = enabled
    audio.setEqualizer(id: app.id, settings: settings)
  }

  private func edit(_ update: (inout AppEqualizer) -> Void) {
    guard canAdjust else { return }
    var settings = curve
    update(&settings)
    audio.setEqualizer(id: app.id, settings: settings)
  }
}

private struct EqualizerResponseGraph: View, Equatable {
  let gains: [Float]
  let sampleRate: Double
  var body: some View {
    let response = responseData
    Canvas { context, size in
      let baseline = size.height / 2
      for db in [-12.0, 0, 12] {
        let y = baseline - db / 18 * baseline
        var line = Path(); line.move(to: CGPoint(x: 0, y: y)); line.addLine(to: CGPoint(x: size.width, y: y))
        context.stroke(line, with: .color(.secondary.opacity(db == 0 ? 0.3 : 0.12)), lineWidth: 0.5)
      }
      var path = Path()
      for (index, gain) in response.values.enumerated() {
        let point = CGPoint(x: CGFloat(index) / CGFloat(response.values.count - 1) * size.width,
                            y: baseline - CGFloat(gain) / 18 * baseline)
        if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
      }
      context.stroke(path, with: .color(.accentColor), style: StrokeStyle(lineWidth: 2, lineCap: .round))
    }
    .padding(10).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    .overlay(alignment: .bottomTrailing) {
      Text(String(format: "%+.1f dB headroom", response.headroom))
        .font(.system(size: 8).monospacedDigit()).foregroundStyle(.secondary).padding(7)
    }
    .accessibilityLabel("EQ frequency response · 20 Hz–\(Int(min(20_000, sampleRate * 0.49))) Hz")
  }
  private var responseData: (values: [Float], headroom: Float) {
    var values = [Float](repeating: 0, count: 128)
    let headroom = gains.withUnsafeBufferPointer { bands in
      values.withUnsafeMutableBufferPointer { output in
        SBAudioEqualizerCurve(sampleRate, bands.baseAddress!, output.baseAddress!, UInt32(output.count))
      }
    }
    return (values, headroom)
  }
}

/// Draws the state independently of NSWindow focus, without activating the panel.
private struct EqualizerSwitchStyle: ToggleStyle {
  @Environment(\.isEnabled) private var enabled

  func makeBody(configuration: Configuration) -> some View {
    Button { configuration.isOn.toggle() } label: {
      ZStack(alignment: .leading) {
        Capsule().fill(configuration.isOn ? Color.accentColor : Color.secondary.opacity(0.35))
        Circle().fill(.white).frame(width: 16, height: 16)
          .padding(3).offset(x: configuration.isOn ? 18 : 0)
      }.frame(width: 40, height: 22)
        .opacity(enabled ? 1 : 0.45).contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .accessibilityRepresentation {
      Toggle(isOn: configuration.$isOn) { configuration.label }.toggleStyle(.switch)
    }
  }
}

/// Retains a real adjustable accessibility control while drawing a stable tint.
private struct EqualizerBandSlider: View {
  @Binding var value: Double
  @Environment(\.isEnabled) private var enabled
  @FocusState private var focused: Bool
  private let range = -12.0...12.0
  private let step = 0.5

  var body: some View {
    GeometryReader { geometry in
      let travel = max(1, geometry.size.height - 14)
      let fraction = min(1, max(0, (value - range.lowerBound) / (range.upperBound - range.lowerBound)))
      ZStack {
        Capsule().fill(Color.secondary.opacity(0.35)).frame(width: 4, height: travel)
        Capsule().fill(Color.accentColor).frame(width: 4, height: travel * fraction)
          .offset(y: travel * (1 - fraction) / 2)
        Circle().fill(.white).frame(width: 14, height: 14)
          .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
          .offset(y: travel * (0.5 - fraction))
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
      .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
        guard enabled else { return }
        focused = true
        let fraction = min(1, max(0, (geometry.size.height - 7 - drag.location.y) / travel))
        setValue(range.lowerBound + fraction * (range.upperBound - range.lowerBound))
      })
    }
    .focusable(enabled).focused($focused)
    .onKeyPress(.upArrow) { adjust(by: step) }
    .onKeyPress(.downArrow) { adjust(by: -step) }
    .onKeyPress(.rightArrow) { adjust(by: step) }
    .onKeyPress(.leftArrow) { adjust(by: -step) }
    .accessibilityRepresentation {
      Slider(value: $value, in: range, step: step)
    }
  }

  private func setValue(_ next: Double) {
    guard enabled, next.isFinite else { return }
    value = min(range.upperBound, max(range.lowerBound, (next / step).rounded() * step))
  }

  private func adjust(by delta: Double) -> KeyPress.Result {
    guard enabled else { return .ignored }
    setValue(value + delta)
    return .handled
  }
}
