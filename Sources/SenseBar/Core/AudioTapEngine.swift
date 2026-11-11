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

  func setGain(_ gain: Float) {
    renderedGain.value = Self.sanitizedGain(gain) * channelCompensation
  }

  private let renderedGain: AtomicFloat
  private let channelCompensation: Float
  private var tapID = AudioObjectID(kAudioObjectUnknown)
  private var aggregateID = AudioObjectID(kAudioObjectUnknown)
  private var ioProc: AudioDeviceIOProcID?

  @available(macOS 14.4, *)
  init?(processObjects: [AudioObjectID], gain: Float, outputDeviceID: AudioObjectID) {
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
    self.renderedGain = AtomicFloat(safeGain * compensation)

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
      tapFormat.mChannelsPerFrame > 0
    else {
      stop()
      return nil
    }

    let targetGain = renderedGain
    let renderState = RenderState(initialGain: targetGain.value)
    let sampleRate = tapFormat.mSampleRate
    let tapChannels = Int(tapFormat.mChannelsPerFrame)
    let renderBlock: AudioDeviceIOBlock = { _, input, _, output, _ in
      Self.render(
        inputs: UnsafeMutableAudioBufferListPointer(
          UnsafeMutablePointer(mutating: input)
        ),
        outputs: UnsafeMutableAudioBufferListPointer(output),
        tapChannels: tapChannels,
        targetGain: targetGain.value,
        sampleRate: sampleRate,
        state: renderState
      )
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

    guard let ioProc, AudioDeviceStart(aggregateID, ioProc) == noErr else {
      stop()
      return nil
    }
  }

  func stop() {
    let tap = tapID
    let aggregate = aggregateID
    let proc = ioProc
    tapID = kAudioObjectUnknown
    aggregateID = kAudioObjectUnknown
    ioProc = nil

    if let proc, aggregate != kAudioObjectUnknown {
      AudioDeviceStop(aggregate, proc)
      AudioDeviceDestroyIOProcID(aggregate, proc)
    }
    if aggregate != kAudioObjectUnknown {
      AudioHardwareDestroyAggregateDevice(aggregate)
    }
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
    let state = RenderState(initialGain: 2)
    return withUnsafeMutablePointer(to: &input) { inputPointer in
      withUnsafeMutablePointer(to: &output) { outputPointer in
        func run(_ gain: Float) {
          render(
            inputs: UnsafeMutableAudioBufferListPointer(inputPointer),
            outputs: UnsafeMutableAudioBufferListPointer(outputPointer),
            tapChannels: 2, targetGain: gain, sampleRate: 48_000, state: state)
        }
        run(2)
        for frame in 0..<(count / 2) {
          let left = destination[frame * 2]
          guard left.isFinite, abs(left) <= 0.98001,
            left == destination[frame * 2 + 1]
          else { return false }
        }
        run(0)
        run(0)
        guard (0..<count).allSatisfy({ destination[$0] == 0 }) else { return false }
        let unity = RenderState(initialGain: 1)
        render(
          inputs: UnsafeMutableAudioBufferListPointer(inputPointer),
          outputs: UnsafeMutableAudioBufferListPointer(outputPointer),
          tapChannels: 2, targetGain: 1, sampleRate: 48_000, state: unity)
        return (0..<count).allSatisfy { destination[$0] == source[$0] }
      }
    }
  }

  private static func render(
    inputs: UnsafeMutableAudioBufferListPointer,
    outputs: UnsafeMutableAudioBufferListPointer,
    tapChannels: Int,
    targetGain: Float,
    sampleRate: Double,
    state: RenderState
  ) {
    for output in outputs where output.mData != nil {
      memset(output.mData, 0, Int(output.mDataByteSize))
    }
    guard
      let source = inputs.reversed().first(where: {
        Int($0.mNumberChannels) == tapChannels && $0.mData != nil
      }), let sourceData = source.mData?.assumingMemoryBound(to: Float.self)
    else { return }

    let sourceFrames = Int(source.mDataByteSize) / (MemoryLayout<Float>.size * tapChannels)
    guard sourceFrames > 0 else { return }
    let requested = targetGain.isFinite ? min(max(targetGain, 0), 8) : 1
    var peak: Float = 0
    vDSP_maxmgv(sourceData, 1, &peak, vDSP_Length(sourceFrames * tapChannels))
    guard peak.isFinite else { return }
    // A linked block-peak guard preserves stereo balance. Attenuation is
    // immediate; recovery takes 120 ms and never increases a quiet block
    // past the user's requested gain. No lookahead buffer is allocated.
    let demand = peak > 0 ? min(1, 0.98 / (peak * max(requested, state.appliedGain, 0.0001))) : 1
    let release = Float(exp(-Double(sourceFrames) / (max(sampleRate, 1) * 0.12)))
    let reduction =
      demand < state.reduction ? demand : demand + release * (state.reduction - demand)
    state.reduction = reduction
    let safeTarget = requested * reduction
    let startGain = min(
      state.appliedGain.isFinite ? state.appliedGain : safeTarget,
      peak > 0 ? 0.98 / peak : safeTarget)
    let step = (safeTarget - startGain) / Float(sourceFrames)
    var low: Float = -1
    var high: Float = 1
    var firstOutputChannel = 0

    for output in outputs {
      let outputChannels = Int(output.mNumberChannels)
      defer { firstOutputChannel += outputChannels }
      guard outputChannels > 0,
        let destination = output.mData?.assumingMemoryBound(to: Float.self)
      else { continue }
      let frames = min(
        sourceFrames,
        Int(output.mDataByteSize) / (MemoryLayout<Float>.size * outputChannels)
      )
      for channel in 0..<outputChannels {
        let sourceChannel = tapChannels == 1 ? 0 : firstOutputChannel + channel
        guard sourceChannel < tapChannels else { continue }
        var channelStart = startGain
        var channelStep = step
        vDSP_vrampmul(
          sourceData + sourceChannel,
          vDSP_Stride(tapChannels),
          &channelStart,
          &channelStep,
          destination + channel,
          vDSP_Stride(outputChannels),
          vDSP_Length(frames)
        )
        vDSP_vclip(
          destination + channel,
          vDSP_Stride(outputChannels),
          &low,
          &high,
          destination + channel,
          vDSP_Stride(outputChannels),
          vDSP_Length(frames)
        )
      }
    }
    state.appliedGain = safeTarget
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

private final class RenderState: @unchecked Sendable {
  var appliedGain: Float
  var reduction: Float = 1

  init(initialGain: Float) {
    appliedGain = initialGain
  }
}

private final class AtomicFloat: @unchecked Sendable {
  private var bits: Int32

  init(_ value: Float) {
    bits = Int32(bitPattern: value.bitPattern)
  }

  var value: Float {
    get {
      Float(bitPattern: UInt32(bitPattern: OSAtomicAdd32Barrier(0, &bits)))
    }
    set {
      let next = Int32(bitPattern: newValue.bitPattern)
      while true {
        let current = OSAtomicAdd32Barrier(0, &bits)
        if OSAtomicCompareAndSwap32Barrier(current, next, &bits) { return }
      }
    }
  }
}
