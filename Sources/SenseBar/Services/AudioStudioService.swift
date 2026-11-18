import AppKit
import AudioToolbox
import Combine
import CoreAudio
import Darwin

struct AudioOutputDevice: Identifiable, Sendable {
  let id: AudioObjectID
  let uid: String
  let name: String
  let canAdjustVolume: Bool
  let kind: AudioOutputKind
}

struct AudioAppEntry: Identifiable, Equatable {
  let id: String
  let pid: pid_t
  let name: String
  let bundleID: String
  let icon: NSImage
  let processObjects: [AudioObjectID]
  let isPlaying: Bool
  let allowsVolumeControl: Bool
  var volume: Double
  var isMuted: Bool
}

/// UI-facing controller for system output and native per-app CoreAudio gain.
/// Process taps are created for adjusted apps and retained across unity while
/// playing. CoreAudio events drive discovery; a slow timer backs up visible UI.
@MainActor
final class AudioStudioService: ObservableObject {
  static let shared = AudioStudioService()

  @Published var masterVolume: Double = 0
  @Published var isMasterMuted = false
  @Published private(set) var outputDeviceName = "Mac"
  @Published private(set) var apps: [AudioAppEntry] = []
  @Published private(set) var needsAudioPermission = false
  @Published private(set) var outputDevices: [AudioOutputDevice] = []
  @Published private(set) var selectedOutputID = AudioObjectID(kAudioObjectUnknown)
  @Published private(set) var canAdjustMasterVolume = false
  @Published private(set) var canMuteMaster = false
  @Published private(set) var isSwitchingOutput = false
  @Published private(set) var outputSwitchFailed = false
  @Published private(set) var masterControlFailed = false
  @Published private(set) var hiddenOutputUIDs = Set(
    UserDefaults.standard.stringArray(forKey: "sensebar.audio.hiddenOutputs") ?? [])

  private var appVolumes: [String: Double]
  private var lastAudibleVolumes: [String: Double] = [:]
  private var engines: [String: AudioTapEngine] = [:]
  private var engineBuilds = AudioTapBuilds()
  private var sleeping = false
  private var featureEnabled = SensePillar.audioStudio.isEnabled()
  private var refreshTimer: Timer?
  private var workspaceObservers: [NSObjectProtocol] = []
  private var monitoringCount = 0
  private var refreshInFlight = false
  private var refreshPending = false
  private var eventRefresh: Task<Void, Never>?
  private var audioListeners:
    [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
  private var watchedProcesses = Set<AudioObjectID>()
  private var watchedOutput = AudioObjectID(kAudioObjectUnknown)
  private var outputDeviceID = AudioObjectID(kAudioObjectUnknown)
  private var outputDeviceUID: String?
  private var hasNativeMute = false
  private let outputTransactions = AudioOutputTransactions()
  private var pendingMasterWrite: UInt64?
  private var lastAudibleMasterVolumes: [String: Double] = [:]

  private static let volumesKey = "sensebar.audio.appVolumes"

  private init() {
    appVolumes =
      UserDefaults.standard.dictionary(forKey: Self.volumesKey) as? [String: Double] ?? [:]
    let center = NSWorkspace.shared.notificationCenter
    for name in [
      NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
    ] {
      workspaceObservers.append(
        center.addObserver(forName: name, object: nil, queue: .main) {
          [weak self] _ in
          MainActor.assumeIsolated { self?.refreshAll() }
        })
    }
    workspaceObservers.append(center.addObserver(forName: NSWorkspace.willSleepNotification,
                                                 object: nil, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.sleeping = true
        self?.invalidateOutputCommands()
        self?.stopAllEngines()
      }
    })
    workspaceObservers.append(center.addObserver(forName: NSWorkspace.didWakeNotification,
                                                 object: nil, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.sleeping = false
        self?.refreshAll()
      }
    })
    workspaceObservers.append(NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification,
                                                                    object: nil, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self else { return }
        let enabled = SensePillar.audioStudio.isEnabled()
        guard enabled != self.featureEnabled else { return }
        self.featureEnabled = enabled
        if !enabled { self.invalidateOutputCommands() }
        self.refreshAll()
      }
    })
    refreshAll()
    listen(
      object: AudioObjectID(kAudioObjectSystemObject),
      selector: kAudioHardwarePropertyDefaultOutputDevice)
    listen(object: AudioObjectID(kAudioObjectSystemObject), selector: kAudioHardwarePropertyDevices)
    if #available(macOS 14.4, *) {
      listen(
        object: AudioObjectID(kAudioObjectSystemObject),
        selector: kAudioHardwarePropertyProcessObjectList)
    }
  }

  var isPerAppMixerSupported: Bool {
    if #available(macOS 14.4, *) { return true }
    return false
  }

  var selectedOutputSymbol: String {
    outputDevices.first { $0.id == selectedOutputID }?.kind.symbol ?? "speaker.wave.2.fill"
  }

  func startMonitoringApps() {
    monitoringCount += 1
    guard monitoringCount == 1 else { return }
    refreshAll()
    configureRefreshTimer()
  }

  func stopMonitoringApps() {
    monitoringCount = max(0, monitoringCount - 1)
    configureRefreshTimer()
  }

  func refreshAll() {
    guard SensePillar.audioStudio.isEnabled(), !sleeping else {
      stopAllEngines()
      return
    }
    guard !refreshInFlight else {
      refreshPending = true
      return
    }
    refreshInFlight = true
    let revision = engineBuilds.revision
    let outputRevision = outputTransactions.current
    let masterWriteWasPending = pendingMasterWrite != nil
    Task {
      let snapshot = await Task.detached(priority: .utility) {
        Self.readSnapshot()
      }.value
      if engineBuilds.revision == revision, !sleeping {
        if outputTransactions.current == outputRevision {
          apply(snapshot, updateMaster: !masterWriteWasPending && pendingMasterWrite == nil)
        } else {
          refreshPending = true
        }
      }
      refreshInFlight = false
      if refreshPending {
        refreshPending = false
        refreshAll()
      }
    }
  }

  func setMasterVolume(_ value: Double) {
    guard SensePillar.audioStudio.isEnabled() else { return }
    guard !sleeping, !isSwitchingOutput, canAdjustMasterVolume, value.isFinite else { return }
    let clamped = min(1, max(0, value))
    masterVolume = clamped
    isMasterMuted = clamped < 0.005
    if clamped >= 0.005, let uid = outputDeviceUID { lastAudibleMasterVolumes[uid] = clamped }
    writeMasterState()
  }

  func toggleMasterMute() {
    guard SensePillar.audioStudio.isEnabled() else { return }
    guard !sleeping, !isSwitchingOutput, canMuteMaster else { return }
    if !isMasterMuted, masterVolume >= 0.005, let uid = outputDeviceUID {
      lastAudibleMasterVolumes[uid] = masterVolume
    }
    isMasterMuted.toggle()
    if canAdjustMasterVolume {
      if !hasNativeMute && isMasterMuted { masterVolume = 0 }
      else if !isMasterMuted && masterVolume < 0.005 {
        masterVolume = outputDeviceUID.flatMap { lastAudibleMasterVolumes[$0] } ?? 0.5
      }
    }
    writeMasterState()
  }

  private func writeMasterState() {
    guard let uid = outputDeviceUID, outputDeviceID != kAudioObjectUnknown else { refreshAll(); return }
    let device = outputDeviceID
    let volume = masterVolume
    let muted = isMasterMuted
    let writesVolume = canAdjustMasterVolume
    let writesMute = hasNativeMute
    let ticket = outputTransactions.invalidate()
    pendingMasterWrite = ticket
    masterControlFailed = false
    Task {
      let success = await outputTransactions.perform(ticket) {
        guard Self.isCurrentOutput(device, uid: uid) else { return false }
        var success = true
        if writesVolume { success = Self.writeOutputVolume(volume, deviceID: device) }
        // Recheck route identity between native calls, including AudioObjectID reuse.
        if writesMute {
          guard Self.isCurrentOutput(device, uid: uid) else { return false }
          success = Self.writeOutputMute(muted, deviceID: device) && success
        }
        return success
      }
      guard outputTransactions.current == ticket else { return }
      pendingMasterWrite = nil
      masterControlFailed = success != true
      refreshAll()
    }
  }

  private func invalidateOutputCommands() {
    outputTransactions.invalidate()
    pendingMasterWrite = nil
    isSwitchingOutput = false
  }

  func selectOutput(_ device: AudioOutputDevice) {
    guard SensePillar.audioStudio.isEnabled() else { return }
    guard !sleeping, !isSwitchingOutput, device.id != selectedOutputID,
          outputDevices.contains(where: { $0.id == device.id && $0.uid == device.uid }) else { return }
    invalidateOutputCommands()
    let ticket = outputTransactions.current
    isSwitchingOutput = true
    outputSwitchFailed = false
    Task {
      let result = await outputTransactions.perform(ticket) {
        guard Self.stringProperty(device.id, selector: kAudioDevicePropertyDeviceUID) == device.uid else {
          return (false, Self.readSnapshot())
        }
        var id = device.id
        let success = Self.write(
          AudioObjectID(kAudioObjectSystemObject),
          selector: kAudioHardwarePropertyDefaultOutputDevice,
          scope: kAudioObjectPropertyScopeGlobal, value: &id)
        return (success, Self.readSnapshot())
      }
      guard outputTransactions.current == ticket else { return }
      if let result {
        apply(result.1, updateMaster: true)
        outputSwitchFailed = !result.0 || outputDeviceID != device.id || outputDeviceUID != device.uid
      } else { outputSwitchFailed = true }
      isSwitchingOutput = false
      refreshAll()
    }
  }

  func setOutputHidden(_ device: AudioOutputDevice, hidden: Bool) {
    if hidden { hiddenOutputUIDs.insert(device.uid) } else { hiddenOutputUIDs.remove(device.uid) }
    UserDefaults.standard.set(hiddenOutputUIDs.sorted(), forKey: "sensebar.audio.hiddenOutputs")
  }

  func setAppVolume(id: String, volume: Double) {
    guard SensePillar.audioStudio.isEnabled() else { return }
    guard volume.isFinite else { return }
    guard let index = apps.firstIndex(where: { $0.id == id }) else { return }
    guard apps[index].allowsVolumeControl else { return }
    let clamped = min(2, max(0, volume))
    apps[index].volume = clamped
    apps[index].isMuted = clamped < 0.001
    appVolumes[id] = clamped
    if clamped > 0.001 { lastAudibleVolumes[id] = clamped }
    UserDefaults.standard.set(appVolumes, forKey: Self.volumesKey)
    reconcileEngine(for: apps[index])
  }

  func toggleAppMute(id: String) {
    guard let app = apps.first(where: { $0.id == id }) else { return }
    if app.volume > 0.001 {
      lastAudibleVolumes[id] = app.volume
      setAppVolume(id: id, volume: 0)
    } else {
      setAppVolume(id: id, volume: lastAudibleVolumes[id] ?? 1)
    }
  }

  private func apply(_ snapshot: AudioSnapshot, updateMaster: Bool) {
    guard SensePillar.audioStudio.isEnabled(), !sleeping else { return }
    updateProcessListeners(snapshot.processes.flatMap(\.objects))
    let uid = snapshot.outputs.first { $0.id == snapshot.outputDeviceID }?.uid
    let changedRoute = outputDeviceID != snapshot.outputDeviceID || outputDeviceUID != uid
    if changedRoute && !isSwitchingOutput {
      invalidateOutputCommands()
      masterControlFailed = false
      outputSwitchFailed = false
    }
    outputDeviceID = snapshot.outputDeviceID
    outputDeviceUID = uid
    selectedOutputID = snapshot.outputDeviceID
    outputDevices = snapshot.outputs
    canAdjustMasterVolume = snapshot.canAdjustVolume && snapshot.outputVolume != nil && uid != nil
    hasNativeMute = snapshot.canMute
    canMuteMaster = snapshot.canMute || snapshot.canAdjustVolume
    outputDeviceName = snapshot.outputDeviceName
    updateOutputListeners(snapshot.outputDeviceID)
    if updateMaster || changedRoute {
      masterVolume = snapshot.outputVolume ?? 0
      isMasterMuted = snapshot.outputMuted == true || (snapshot.outputVolume.map { $0 < 0.005 } ?? false)
    }
    if outputDeviceID == kAudioObjectUnknown { stopAllEngines() }

    var owned: [pid_t: (app: NSRunningApplication, objects: [AudioObjectID], playing: Bool)] = [:]
    for process in snapshot.processes {
      guard process.pid != ProcessInfo.processInfo.processIdentifier,
        let app = Self.regularOwner(for: process), !app.isTerminated
      else { continue }
      let ownerPID = app.processIdentifier
      var group = owned[ownerPID] ?? (app, [], false)
      group.objects.append(contentsOf: process.objects)
      group.playing = group.playing || process.isPlaying
      owned[ownerPID] = group
    }

    let rows = owned.values.compactMap { group -> AudioAppEntry? in
      let running = group.app
      let bundleID = running.bundleIdentifier ?? ""
      let id = bundleID.isEmpty ? "pid:\(running.processIdentifier)" : bundleID
      let name = running.localizedName ?? bundleID
      guard !name.isEmpty else { return nil }
      let icon =
        running.icon
        ?? running.bundleURL.map { NSWorkspace.shared.icon(forFile: $0.path) }
        ?? NSImage(systemSymbolName: "speaker.wave.2.fill", accessibilityDescription: name)
        ?? NSImage()
      let volume = appVolumes[id] ?? 1
      let allowsVolumeControl = Self.allowsProcessTap(bundleID: bundleID)
      return AudioAppEntry(
        id: id,
        pid: running.processIdentifier,
        name: name,
        bundleID: bundleID,
        icon: icon,
        processObjects: Array(Set(group.objects)).sorted(),
        isPlaying: group.playing,
        allowsVolumeControl: allowsVolumeControl,
        volume: allowsVolumeControl ? volume : 1,
        isMuted: allowsVolumeControl && volume < 0.001
      )
    }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

    apps = rows
    let liveIDs = Set(rows.map(\.id))
    for id in engines.keys where !liveIDs.contains(id) {
      engines.removeValue(forKey: id)?.stop()
    }
    for app in rows where engines[app.id] != nil || abs(app.volume - 1) >= 0.005 {
      reconcileEngine(for: app)
    }
    configureRefreshTimer()
  }

  /// Maps CoreAudio helpers to the nearest visible owning application.
  /// Daemons whose responsibility/parent chain never reaches a regular app
  /// are intentionally absent from the user-facing mixer.
  private static func regularOwner(for process: AudioProcessSnapshot) -> NSRunningApplication? {
    if let app = NSRunningApplication(processIdentifier: process.pid),
      app.processIdentifier > 0, app.activationPolicy == .regular
    {
      return app
    }
    for pid in process.ownerCandidates {
      if let app = NSRunningApplication(processIdentifier: pid),
        app.activationPolicy == .regular
      {
        return app
      }
    }
    guard !process.bundleID.isEmpty else { return nil }
    return NSRunningApplication.runningApplications(withBundleIdentifier: process.bundleID)
      .first { $0.processIdentifier > 0 && $0.activationPolicy == .regular }
  }

  private func reconcileEngine(for app: AudioAppEntry) {
    guard SensePillar.audioStudio.isEnabled(), !sleeping else { return }
    guard isPerAppMixerSupported else { return }
    guard app.allowsVolumeControl else {
      engines.removeValue(forKey: app.id)?.stop()
      return
    }
    guard AudioTapBuilds.needsEngine(volume: app.volume, playing: app.isPlaying,
                                    hasEngine: engines[app.id] != nil) else {
      engines.removeValue(forKey: app.id)?.stop()
      configureRefreshTimer()
      return
    }
    if let engine = engines[app.id],
      engine.processObjects == app.processObjects,
      engine.outputDeviceID == outputDeviceID
    {
      engine.setGain(Self.gain(for: app.volume))
      return
    }
    guard outputDeviceID != kAudioObjectUnknown, let ticket = engineBuilds.begin(app.id) else { return }
    let id = app.id
    let objects = app.processObjects
    let gain = Self.gain(for: app.volume)
    let device = outputDeviceID

    Task {
      let engine = await Task.detached(priority: .userInitiated) {
        if #available(macOS 14.4, *) {
          return AudioTapEngine(processObjects: objects, gain: gain, outputDeviceID: device)
        }
        return nil
      }.value
      guard engineBuilds.finish(id, ticket: ticket) else { engine?.stop(); return }
      guard SensePillar.audioStudio.isEnabled(), !sleeping,
        let latest = apps.first(where: { $0.id == id }),
        latest.allowsVolumeControl,
        outputDeviceID == device,
        AudioTapBuilds.needsEngine(volume: latest.volume, playing: latest.isPlaying,
                                  hasEngine: engines[id] != nil),
        latest.processObjects == objects,
        NSRunningApplication(processIdentifier: latest.pid)?.isTerminated == false
      else {
        engine?.stop()
        if let latest = apps.first(where: { $0.id == id }),
           latest.processObjects != objects || outputDeviceID != device,
           NSRunningApplication(processIdentifier: latest.pid)?.isTerminated == false {
          reconcileEngine(for: latest)
        }
        return
      }
      guard let engine else {
        needsAudioPermission = true
        return
      }
      needsAudioPermission = false
      engine.setGain(Self.gain(for: latest.volume))
      engines.updateValue(engine, forKey: id)?.stop()
      configureRefreshTimer()
    }
  }

  private func configureRefreshTimer() {
    let active = SensePillar.audioStudio.isEnabled() && !sleeping
    let interval: TimeInterval? = active && (monitoringCount > 0 || !engines.isEmpty) ? 15 : nil
    refreshTimer?.invalidate()
    refreshTimer = nil
    guard let interval else { return }
    let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
      Task { @MainActor [weak self] in self?.refreshAll() }
    }
    timer.tolerance = interval * 0.2
    RunLoop.main.add(timer, forMode: .common)
    refreshTimer = timer
  }

  private func stopAllEngines() {
    for engine in engines.values { engine.stop() }
    engines.removeAll()
    engineBuilds.invalidate()
    eventRefresh?.cancel()
    eventRefresh = nil
    configureRefreshTimer()
  }

  private static func gain(for volume: Double) -> Float {
    let level = max(0, min(2, volume))
    return Float(level < 1 ? level * level : level)
  }

  /// Call apps intentionally exclude their own playback from screen sharing.
  /// Replaying their tap from SenseBar would defeat that safety boundary.
  private static func allowsProcessTap(bundleID: String) -> Bool {
    let identifier = bundleID.lowercased()
    return ![
      "com.hnc.discord", "com.hnc.discordptb", "com.hnc.discordcanary",
      "com.microsoft.teams", "com.microsoft.teams2", "us.zoom.xos",
    ].contains {
      identifier == $0 || identifier.hasPrefix($0 + ".")
    }
  }

  private func listen(object: AudioObjectID, selector: AudioObjectPropertySelector,
                      scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) {
    var address = AudioObjectPropertyAddress(
      mSelector: selector,
      mScope: scope, mElement: kAudioObjectPropertyElementMain)
    let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
      Task { @MainActor [weak self] in
        guard let self else { return }
        if selector == kAudioHardwarePropertyDefaultOutputDevice || selector == kAudioHardwarePropertyDevices {
          if !self.isSwitchingOutput { self.invalidateOutputCommands() }
        }
        self.scheduleEventRefresh()
      }
    }
    if AudioObjectAddPropertyListenerBlock(object, &address, .main, block) == noErr {
      audioListeners.append((object, address, block))
    }
  }

  private func updateOutputListeners(_ device: AudioObjectID) {
    guard watchedOutput != device else { return }
    for index in audioListeners.indices.reversed() {
      let item = audioListeners[index]
      if item.0 == watchedOutput && item.1.mScope == kAudioObjectPropertyScopeOutput {
        var address = item.1
        AudioObjectRemovePropertyListenerBlock(item.0, &address, .main, item.2)
        audioListeners.remove(at: index)
      }
    }
    watchedOutput = device
    guard device != kAudioObjectUnknown else { return }
    for selector in Self.volumeSelectors + [kAudioDevicePropertyMute] {
      listen(object: device, selector: selector, scope: kAudioObjectPropertyScopeOutput)
    }
  }

  private func scheduleEventRefresh() {
    eventRefresh?.cancel()
    eventRefresh = Task { [weak self] in
      do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
      self?.refreshAll()
    }
  }

  private func updateProcessListeners(_ objects: [AudioObjectID]) {
    guard #available(macOS 14.4, *) else { return }
    let next = Set(objects)
    for index in audioListeners.indices.reversed() {
      let item = audioListeners[index]
      if watchedProcesses.contains(item.0), !next.contains(item.0) {
        var address = item.1
        AudioObjectRemovePropertyListenerBlock(item.0, &address, .main, item.2)
        audioListeners.remove(at: index)
      }
    }
    for object in next.subtracting(watchedProcesses) {
      listen(object: object, selector: kAudioProcessPropertyIsRunningOutput)
    }
    watchedProcesses = next
  }
}

private struct AudioProcessSnapshot: Sendable {
  let pid: pid_t
  let bundleID: String
  let ownerCandidates: [pid_t]
  let objects: [AudioObjectID]
  let isPlaying: Bool
}

private struct AudioSnapshot: Sendable {
  let outputs: [AudioOutputDevice]
  let canAdjustVolume: Bool
  let canMute: Bool
  let outputDeviceID: AudioObjectID
  let outputDeviceName: String
  let outputVolume: Double?
  let outputMuted: Bool?
  let processes: [AudioProcessSnapshot]
}

extension AudioStudioService {
  fileprivate nonisolated static func isCurrentOutput(_ id: AudioObjectID, uid: String) -> Bool {
    defaultOutputDeviceID() == id && stringProperty(id, selector: kAudioDevicePropertyDeviceUID) == uid
  }
  fileprivate nonisolated static func readSnapshot() -> AudioSnapshot {
    let device = defaultOutputDeviceID() ?? kAudioObjectUnknown
    return AudioSnapshot(
      outputs: readOutputDevices(),
      canAdjustVolume: volumeSelectors.contains { isSettable(device, selector: $0) },
      canMute: isSettable(device, selector: kAudioDevicePropertyMute),
      outputDeviceID: device,
      outputDeviceName: stringProperty(device, selector: kAudioObjectPropertyName) ?? "Mac",
      outputVolume: readOutputVolume(device).map(Double.init),
      outputMuted: readOutputMute(device),
      processes: readAudioProcesses()
    )
  }

  fileprivate nonisolated static func readOutputDevices() -> [AudioOutputDevice] {
    objectList(AudioObjectID(kAudioObjectSystemObject), selector: kAudioHardwarePropertyDevices)
      .compactMap { device -> AudioOutputDevice? in
        var alive: UInt32 = 0
        var hidden: UInt32 = 0
        guard read(device, selector: kAudioDevicePropertyDeviceIsAlive, value: &alive), alive != 0,
          let uid = stringProperty(device, selector: kAudioDevicePropertyDeviceUID),
          !uid.hasPrefix("com.sensebar.audio.")
        else { return nil }
        _ = read(device, selector: kAudioDevicePropertyIsHidden, value: &hidden)
        guard hidden == 0 else { return nil }
        var address = AudioObjectPropertyAddress(
          mSelector: kAudioDevicePropertyStreams,
          mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr,
          size >= MemoryLayout<AudioStreamID>.size
        else { return nil }
        let name = stringProperty(device, selector: kAudioObjectPropertyName) ?? uid
        var transport: UInt32 = 0
        _ = read(device, selector: kAudioDevicePropertyTransportType, value: &transport)
        var terminal: UInt32 = 0
        for stream in objectList(device, selector: kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput) {
          var value: UInt32 = 0
          if read(stream, selector: kAudioStreamPropertyTerminalType, value: &value) {
            terminal = value
            if value == kAudioStreamTerminalTypeHeadphones { break }
          }
        }
        return AudioOutputDevice(
          id: device,
          uid: uid,
          name: name,
          canAdjustVolume: volumeSelectors.contains { isSettable(device, selector: $0) },
          kind: .classify(name: name, transport: transport, terminal: terminal)
        )
      }
      .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }

  fileprivate nonisolated static func isSettable(
    _ device: AudioObjectID, selector: AudioObjectPropertySelector
  ) -> Bool {
    var address = AudioObjectPropertyAddress(
      mSelector: selector,
      mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    var settable = DarwinBoolean(false)
    return AudioObjectIsPropertySettable(device, &address, &settable) == noErr && settable.boolValue
  }

  fileprivate nonisolated static func readAudioProcesses() -> [AudioProcessSnapshot] {
    guard #available(macOS 14.4, *) else { return [] }
    let objects = objectList(
      AudioObjectID(kAudioObjectSystemObject),
      selector: kAudioHardwarePropertyProcessObjectList
    )
    var grouped: [pid_t: (bundleID: String, objects: [AudioObjectID], playing: Bool)] = [:]
    for object in objects {
      var pid: pid_t = 0
      guard read(object, selector: kAudioProcessPropertyPID, value: &pid), pid > 0 else { continue }
      var running: UInt32 = 0
      _ = read(object, selector: kAudioProcessPropertyIsRunningOutput, value: &running)
      let bundleID = stringProperty(object, selector: kAudioProcessPropertyBundleID) ?? ""
      var item = grouped[pid] ?? (bundleID, [], false)
      if item.bundleID.isEmpty { item.bundleID = bundleID }
      item.objects.append(object)
      item.playing = item.playing || running != 0
      grouped[pid] = item
    }
    return grouped.map { pid, item in
      AudioProcessSnapshot(
        pid: pid,
        bundleID: item.bundleID,
        ownerCandidates: AudioProcessOwnership.ownerCandidates(for: pid),
        objects: item.objects.sorted(),
        isPlaying: item.playing
      )
    }
  }

  fileprivate nonisolated static func defaultOutputDeviceID() -> AudioObjectID? {
    var device = AudioObjectID(kAudioObjectUnknown)
    guard
      read(
        AudioObjectID(kAudioObjectSystemObject),
        selector: kAudioHardwarePropertyDefaultOutputDevice,
        value: &device
      ), device != kAudioObjectUnknown
    else { return nil }
    return device
  }

  fileprivate nonisolated static var volumeSelectors: [AudioObjectPropertySelector] {
    [kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyVolumeScalar]
  }

  fileprivate nonisolated static func readOutputVolume(_ deviceID: AudioObjectID) -> Float32? {
    for selector in volumeSelectors {
      var value: Float32 = 0
      if read(deviceID, selector: selector, scope: kAudioDevicePropertyScopeOutput, value: &value) {
        return value.isFinite ? min(1, max(0, value)) : nil
      }
    }
    return nil
  }

  fileprivate nonisolated static func writeOutputVolume(_ volume: Double, deviceID: AudioObjectID)
    -> Bool
  {
    var value = Float32(min(1, max(0, volume)))
    for selector in volumeSelectors
    where write(
      deviceID,
      selector: selector,
      scope: kAudioDevicePropertyScopeOutput,
      value: &value
    ) { return true }
    return false
  }

  fileprivate nonisolated static func readOutputMute(_ deviceID: AudioObjectID) -> Bool? {
    for element: AudioObjectPropertyElement in [kAudioObjectPropertyElementMain, 1, 2] {
      var value: UInt32 = 0
      if read(
        deviceID,
        selector: kAudioDevicePropertyMute,
        scope: kAudioDevicePropertyScopeOutput,
        element: element,
        value: &value
      ) {
        return value != 0
      }
    }
    return nil
  }

  fileprivate nonisolated static func writeOutputMute(_ muted: Bool, deviceID: AudioObjectID)
    -> Bool
  {
    var didWrite = false
    for element: AudioObjectPropertyElement in [kAudioObjectPropertyElementMain, 1, 2] {
      var value: UInt32 = muted ? 1 : 0
      didWrite =
        write(
          deviceID,
          selector: kAudioDevicePropertyMute,
          scope: kAudioDevicePropertyScopeOutput,
          element: element,
          value: &value
        ) || didWrite
    }
    return didWrite
  }

  fileprivate nonisolated static func objectList(
    _ object: AudioObjectID,
    selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
  ) -> [AudioObjectID] {
    var address = AudioObjectPropertyAddress(
      mSelector: selector,
      mScope: scope,
      mElement: kAudioObjectPropertyElementMain
    )
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr,
      size >= MemoryLayout<AudioObjectID>.size
    else { return [] }
    var values = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &values) == noErr else {
      return []
    }
    return values.filter { $0 != kAudioObjectUnknown }
  }

  fileprivate nonisolated static func stringProperty(
    _ object: AudioObjectID,
    selector: AudioObjectPropertySelector
  ) -> String? {
    var value: CFString = "" as CFString
    guard read(object, selector: selector, value: &value) else { return nil }
    let string = value as String
    return string.isEmpty ? nil : string
  }

  fileprivate nonisolated static func read<T>(
    _ object: AudioObjectID,
    selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
    element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain,
    value: inout T
  ) -> Bool {
    var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    guard AudioObjectHasProperty(object, &address) else { return false }
    var size = UInt32(MemoryLayout<T>.size)
    return withUnsafeMutablePointer(to: &value) { pointer in
      AudioObjectGetPropertyData(object, &address, 0, nil, &size, pointer) == noErr
    }
  }

  fileprivate nonisolated static func write<T>(
    _ object: AudioObjectID,
    selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope,
    element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain,
    value: inout T
  ) -> Bool {
    var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    guard AudioObjectHasProperty(object, &address) else { return false }
    var settable = DarwinBoolean(false)
    guard AudioObjectIsPropertySettable(object, &address, &settable) == noErr,
      settable.boolValue
    else { return false }
    return withUnsafePointer(to: &value) { pointer in
      AudioObjectSetPropertyData(
        object,
        &address,
        0,
        nil,
        UInt32(MemoryLayout<T>.size),
        pointer
      ) == noErr
    }
  }
}

private enum AudioProcessOwnership {
  private typealias ResponsibilityResolver = @convention(c) (pid_t) -> pid_t

  private static let resolver: ResponsibilityResolver? = {
    guard
      let symbol = dlsym(
        UnsafeMutableRawPointer(bitPattern: -2),
        "responsibility_get_pid_responsible_for_pid")
    else { return nil }
    return unsafeBitCast(symbol, to: ResponsibilityResolver.self)
  }()

  /// Returns responsibility and BSD-parent candidates in nearest-first order.
  /// A small depth cap prevents malformed or recycled process chains looping.
  static func ownerCandidates(for pid: pid_t) -> [pid_t] {
    guard pid > 0 else { return [] }
    let responsible = resolver?(pid) ?? pid
    var result: [pid_t] = []
    appendChain(startingAt: responsible > 0 ? responsible : pid, to: &result)
    if responsible != pid { appendChain(startingAt: pid, to: &result) }
    return result
  }

  private static func appendChain(startingAt pid: pid_t, to result: inout [pid_t]) {
    var current = pid
    for _ in 0..<7 {
      guard current > 1 else { return }
      if !result.contains(current) { result.append(current) }
      current = parentPID(of: current)
    }
  }

  private static func parentPID(of pid: pid_t) -> pid_t {
    var info = proc_bsdinfo()
    let expected = Int32(MemoryLayout<proc_bsdinfo>.size)
    guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, expected) == expected else { return 0 }
    return pid_t(info.pbi_ppid)
  }
}
