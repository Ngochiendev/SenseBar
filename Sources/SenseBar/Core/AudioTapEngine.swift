import Accelerate
import CoreAudio
import Darwin
import Foundation
import SenseBarAudioBridge

/// Owns one private CoreAudio process tap and renders it to the current output.
/// The realtime callback performs no allocation, locking, or object discovery.
final class AudioTapEngine: @unchecked Sendable {
  let processObjects: [AudioObjectID]
  let outputDeviceID: AudioObjectID
  private(set) var processingSampleRate: Double = 48_000
  private(set) var outputSampleRate: Double = 0
  private var started = false

  var outputFormatMatches: Bool {
    var rate: Double = 0
    return Self.read(outputDeviceID, selector: kAudioDevicePropertyNominalSampleRate, value: &rate)
      && abs(rate - outputSampleRate) < 0.1
  }

  /// The service serializes all publications on MainActor after construction.
  func setConfiguration(gain: Float, equalizer: AppEqualizer) {
    guard let processor else { return }
    let curve = equalizer.normalized
    curve.gains.withUnsafeBufferPointer {
      SBAudioEqualizerPublish(processor, gain * channelCompensation, $0.baseAddress, curve.enabled)
    }
  }

  private var processor: OpaquePointer?
  private let channelCompensation: Float
  private var tapID = AudioObjectID(kAudioObjectUnknown)
  private var aggregateID = AudioObjectID(kAudioObjectUnknown)
  private var ioProc: AudioDeviceIOProcID?

  @available(macOS 14.4, *)
  init?(processObjects: [AudioObjectID], gain: Float, outputDeviceID: AudioObjectID, equalizer: AppEqualizer = AppEqualizer()) {
    guard !processObjects.isEmpty,
      let outputUID = Self.stringProperty(
        outputDeviceID,
        selector: kAudioDevicePropertyDeviceUID
      )
    else { return nil }

    let safeGain = Self.sanitizedGain(gain)
    let compensation = Self.stereoMixdownCompensation(for: outputDeviceID)
    self.processObjects = processObjects
    self.outputDeviceID = outputDeviceID
    self.channelCompensation = compensation
    _ = Self.read(outputDeviceID, selector: kAudioDevicePropertyNominalSampleRate, value: &outputSampleRate)

    var tap = AudioObjectID(kAudioObjectUnknown)
    var uuidReference: Unmanaged<CFString>?
    let created = processObjects.withUnsafeBufferPointer { objects in
      SBAudioCreateStereoProcessTap(
        objects.baseAddress!,
        objects.count,
        &tap,
        &uuidReference
      )
    }
    guard created, let uuidReference else { return nil }
    tapID = tap
    let tapUUID = uuidReference.takeRetainedValue() as String

    let aggregateDescription: [String: Any] = [
      kAudioAggregateDeviceNameKey: "SenseBar Audio Studio",
      kAudioAggregateDeviceUIDKey: "com.sensebar.audio.\(UUID().uuidString)",
      kAudioAggregateDeviceIsPrivateKey: true,
      kAudioAggregateDeviceMainSubDeviceKey: outputUID,
      kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
      kAudioAggregateDeviceTapListKey: [
        [
          kAudioSubTapUIDKey: tapUUID,
          kAudioSubTapDriftCompensationKey: true,
        ]
      ],
      kAudioAggregateDeviceTapAutoStartKey: true,
    ]

    guard
      AudioHardwareCreateAggregateDevice(
        aggregateDescription as CFDictionary,
        &aggregateID
      ) == noErr, aggregateID != kAudioObjectUnknown
    else {
      stop()
      return nil
    }

    var tapFormat = AudioStreamBasicDescription()
    guard Self.read(tapID, selector: kAudioTapPropertyFormat, value: &tapFormat),
      tapFormat.mFormatID == kAudioFormatLinearPCM,
      tapFormat.mFormatFlags & kAudioFormatFlagIsFloat != 0,
      tapFormat.mBitsPerChannel == 32,
      tapFormat.mChannelsPerFrame > 0, tapFormat.mChannelsPerFrame <= 2
    else {
      stop()
      return nil
    }

    processingSampleRate = tapFormat.mSampleRate
    let curve = equalizer.normalized
    let createdProcessor = curve.gains.withUnsafeBufferPointer {
      SBAudioEqualizerCreate(tapFormat.mSampleRate, safeGain * compensation, $0.baseAddress, curve.enabled)
    }
    guard let createdProcessor else { stop(); return nil }
    processor = createdProcessor
    let renderState = AudioRenderHandle(processor: createdProcessor)
    let tapChannels = tapFormat.mChannelsPerFrame
    let renderBlock: AudioDeviceIOBlock = { _, input, _, output, _ in
      SBAudioEqualizerRender(renderState.processor, input, output, tapChannels)
    }
    guard
      AudioDeviceCreateIOProcIDWithBlock(
        &ioProc,
        aggregateID,
        nil,
        renderBlock
      ) == noErr
    else {
      ioProc = nil
      stop()
      return nil
    }
  }

  /// Start only after the service accepts the build and installs its latest intent.
  func start(gain: Float, equalizer: AppEqualizer) -> Bool {
    guard !started, let processor, let ioProc else { return false }
    let curve = equalizer.normalized
    curve.gains.withUnsafeBufferPointer {
      SBAudioEqualizerPrepare(processor, gain * channelCompensation, $0.baseAddress, curve.enabled)
    }
    guard AudioDeviceStart(aggregateID, ioProc) == noErr else { return false }
    started = true
    return true
  }

  func stop() {
    let tap = tapID
    let aggregate = aggregateID
    let proc = ioProc
    tapID = kAudioObjectUnknown
    aggregateID = kAudioObjectUnknown
    ioProc = nil

    if let proc, aggregate != kAudioObjectUnknown {
      if started { AudioDeviceStop(aggregate, proc) }
      AudioDeviceDestroyIOProcID(aggregate, proc)
    }
    if aggregate != kAudioObjectUnknown {
      AudioHardwareDestroyAggregateDevice(aggregate)
    }
    started = false
    if let processor { SBAudioEqualizerDestroy(processor); self.processor = nil }
    if tap != kAudioObjectUnknown {
      _ = SBAudioDestroyProcessTap(tap)
    }
  }

  deinit { stop() }

  /// Exercises the production renderer without opening a device or a tap.
  static func validateRender() -> Bool {
    let count = 128
    let source = UnsafeMutablePointer<Float>.allocate(capacity: count)
    let destination = UnsafeMutablePointer<Float>.allocate(capacity: count)
    defer {
      source.deallocate()
      destination.deallocate()
    }
    source.initialize(repeating: 0.75, count: count)
    destination.initialize(repeating: 0, count: count)
    var input = AudioBufferList(
      mNumberBuffers: 1,
      mBuffers: AudioBuffer(
        mNumberChannels: 2, mDataByteSize: UInt32(count * 4), mData: source))
    var output = AudioBufferList(
      mNumberBuffers: 1,
      mBuffers: AudioBuffer(
        mNumberChannels: 2, mDataByteSize: UInt32(count * 4), mData: destination))
    guard let processor = SBAudioEqualizerCreate(48_000, 2, nil, false) else { return false }
    defer { SBAudioEqualizerDestroy(processor) }
    return withUnsafeMutablePointer(to: &input) { inputPointer in
      withUnsafeMutablePointer(to: &output) { outputPointer in
        func run(_ gain: Float) {
          SBAudioEqualizerPublish(processor, gain, nil, false)
          SBAudioEqualizerRender(processor, inputPointer, outputPointer, 2)
        }
        run(2)
        for frame in 0..<(count / 2) {
          let left = destination[frame * 2]
          guard left.isFinite, abs(left) <= 0.98001,
            left == destination[frame * 2 + 1]
          else { return false }
        }
        for _ in 0..<32 { run(0) }
        guard (0..<count).allSatisfy({ destination[$0] == 0 }) else { return false }
        guard let unity = SBAudioEqualizerCreate(48_000, 1, nil, false) else { return false }
        defer { SBAudioEqualizerDestroy(unity) }
        SBAudioEqualizerRender(unity, inputPointer, outputPointer, 2)
        guard (0..<count).allSatisfy({ destination[$0] == source[$0] }) else { return false }
        let bands: [Float] = [3, 2, 0, -1, -2]
        var response = [Float](repeating: 0, count: 129)
        let headroom = bands.withUnsafeBufferPointer { bands in
          response.withUnsafeMutableBufferPointer {
            SBAudioEqualizerCurve(48_000, bands.baseAddress!, $0.baseAddress!, 129)
          }
        }
        let equalizer = bands.withUnsafeBufferPointer {
          SBAudioEqualizerCreate(48_000, 1, $0.baseAddress, true)
        }
        guard let equalizer else { return false }
        defer { SBAudioEqualizerDestroy(equalizer) }
        let frequency = 20 * pow(1_000.0, 0.5)
        var inputEnergy = 0.0
        var outputEnergy = 0.0
        for block in 0..<400 {
          for frame in 0..<(count / 2) {
            source[frame * 2] = Float(0.1 * sin(2 * .pi * frequency * Double(block * count / 2 + frame) / 48_000))
            source[frame * 2 + 1] = 0
          }
          SBAudioEqualizerRender(equalizer, inputPointer, outputPointer, 2)
          for frame in 0..<(count / 2) {
            let sample = destination[frame * 2]
            guard sample.isFinite, abs(sample) <= 0.98001,
              destination[frame * 2 + 1] == 0 else { return false }
            if block > 100 {
              inputEnergy += Double(source[frame * 2]) * Double(source[frame * 2])
              outputEnergy += Double(sample) * Double(sample)
            }
          }
        }
        let measured = 10 * log10(outputEnergy / inputEnergy)
        return abs(measured - Double(response[64] + headroom)) < 0.05
      }
    }
  }

  private static func stereoMixdownCompensation(for device: AudioObjectID) -> Float {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyStreamConfiguration,
      mScope: kAudioDevicePropertyScopeOutput,
      mElement: kAudioObjectPropertyElementMain
    )
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr,
      size >= UInt32(MemoryLayout<AudioBufferList>.size)
    else { return 1 }
    let raw = UnsafeMutableRawPointer.allocate(
      byteCount: Int(size),
      alignment: MemoryLayout<AudioBufferList>.alignment
    )
    defer { raw.deallocate() }
    guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, raw) == noErr else {
      return 1
    }
    let buffers = UnsafeMutableAudioBufferListPointer(
      raw.assumingMemoryBound(to: AudioBufferList.self)
    )
    let channels = buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
    return Float(min(4, max(1, channels / 2)))
  }

  private static func sanitizedGain(_ value: Float) -> Float {
    value.isFinite ? min(max(value, 0), 2) : 1
  }

  private static func stringProperty(
    _ object: AudioObjectID,
    selector: AudioObjectPropertySelector
  ) -> String? {
    var value: CFString = "" as CFString
    guard read(object, selector: selector, value: &value) else { return nil }
    let string = value as String
    return string.isEmpty ? nil : string
  }

  private static func read<T>(
    _ object: AudioObjectID,
    selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
    value: inout T
  ) -> Bool {
    var address = AudioObjectPropertyAddress(
      mSelector: selector,
      mScope: scope,
      mElement: kAudioObjectPropertyElementMain
    )
    var size = UInt32(MemoryLayout<T>.size)
    return withUnsafeMutablePointer(to: &value) { pointer in
      AudioObjectGetPropertyData(object, &address, 0, nil, &size, pointer) == noErr
    }
  }
}

/// Lifetime belongs to AudioTapEngine; HAL is stopped before the C state is freed.
private struct AudioRenderHandle: @unchecked Sendable {
  let processor: OpaquePointer
}
