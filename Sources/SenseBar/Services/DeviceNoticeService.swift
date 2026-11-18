import AppKit
import CoreBluetooth
import Combine
import IOKit.ps

struct MacPowerState: Equatable, Sendable {
    let external: Bool
    let charging: Bool
    let percent: Int?

    static func read() -> MacPowerState? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }
        for source in sources {
            guard let value = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  value[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            let current = (value[kIOPSCurrentCapacityKey] as? NSNumber)?.doubleValue
            let maximum = (value[kIOPSMaxCapacityKey] as? NSNumber)?.doubleValue
            let percent = current.flatMap { current in
                maximum.flatMap { maximum -> Int? in
                    guard current.isFinite, maximum.isFinite, maximum > 0 else { return nil }
                    return Int((min(1, max(0, current / maximum)) * 100).rounded())
                }
            }
            return MacPowerState(external: value[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue,
                                 charging: (value[kIOPSIsChargingKey] as? NSNumber)?.boolValue ?? false,
                                 percent: percent)
        }
        return nil
    }
}

/// One event-driven power snapshot shared by notices and the pet.
@MainActor
final class MacPowerService: ObservableObject {
    static let shared = MacPowerService()
    @Published private(set) var state: MacPowerState?
    private var source: CFRunLoopSource?

    private init() {
        state = MacPowerState.read()
        source = IOPSNotificationCreateRunLoopSource({ _ in
            Task { @MainActor in MacPowerService.shared.refresh() }
        }, nil)?.takeRetainedValue()
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }
    }

    func refresh() {
        let next = MacPowerState.read()
        if next != state { state = next }
    }
}

struct IslandDeviceNotice: Equatable, Identifiable {
    let id: String
    let title: String
    var detail: String
    let symbol: String
    var percent: Int?
    let created: Date
    var batteryDetail: String? = nil
    var batteryReading: DeviceBatteryReading? = nil
    var batteryComponent: DeviceBatteryReading.Component? = nil
}

/// A Bluetooth link can survive AirPods auto-switching; output activation is
/// another observable event. Initial state is deliberately silent.
struct AudioAccessoryTransitions {
    private var available: Set<String>?
    private var selected: String?

    mutating func consume(available next: Set<String>, selected nextSelected: String?) -> Set<String> {
        defer { available = next; selected = nextSelected }
        guard let available else { return [] }
        var result = next.subtracting(available)
        if let nextSelected, nextSelected != selected { result.insert(nextSelected) }
        return result
    }
}

/// Bounded transient presentation, independent of music's expanded state.
@MainActor
final class DeviceNoticeService: ObservableObject {
    static let shared = DeviceNoticeService()
    @Published private(set) var current: IslandDeviceNotice?
    private var pending: [IslandDeviceNotice] = []
    private var subscriptions = Set<AnyCancellable>()
    private var deadline: Task<Void, Never>?
    private var bluetooth: DeviceConnectionMonitor?
    private var sleeping = false
    private var started = false
    private var devices: [String: (name: String, symbol: String)] = [:]
    private var lowBattery = PeripheralLowBatteryPolicy()
    private var batteryReadings: [String: DeviceBatteryReading] = [:]
    private var lastConnectionNotices: [String: Date] = [:]
    private var audioTransitions = AudioAccessoryTransitions()

    private init() {
        let saved = UserDefaults.standard.dictionary(forKey: DefaultsKey.peripheralBatteryLastPresented)
        let parts = UserDefaults.standard.dictionary(forKey: DefaultsKey.peripheralBatteryRecoveryComponents)
        lowBattery = PeripheralLowBatteryPolicy(lastPresented: saved as? [String: Date] ?? [:],
                                               recoveryComponents: parts as? [String: [String]] ?? [:])
    }

    private var batteryThreshold: Int {
        let value = UserDefaults.standard.object(forKey: DefaultsKey.peripheralBatteryThreshold) as? Int ?? 20
        return PeripheralLowBatteryPolicy.threshold(value)
    }

    private var batteryAlertsEnabled: Bool {
        UserDefaults.standard.object(forKey: DefaultsKey.notchLowPeripheralBattery) as? Bool ?? true
    }

    enum Preview: CaseIterable {
        case airpods, keyboard, charging, unplugged, lowBattery

        @MainActor var title: String {
            let l10n = L10n.shared
            switch self {
            case .airpods: return "AirPods"
            case .keyboard: return l10n.string(vi: "Bàn phím kết nối", en: "Keyboard connected")
            case .charging: return l10n.string(vi: "Cắm sạc MacBook", en: "MacBook charging")
            case .unplugged: return l10n.string(vi: "Rút sạc MacBook", en: "MacBook unplugged")
            case .lowBattery: return l10n.string(vi: "Phụ kiện pin yếu", en: "Accessory low battery")
            }
        }
    }

    /// Presentation-only preview; never changes connections, charge or battery episodes.
    func preview(_ kind: Preview) {
        guard enabled, !sleeping, !IslandController.shared.isExpanded else { return }
        let l10n = L10n.shared
        let connected = l10n.string(vi: "Đã kết nối", en: "Connected")
        let notice: IslandDeviceNotice
        switch kind {
        case .airpods:
            notice = IslandDeviceNotice(id: "preview-airpods", title: "AirPods Pro", detail: connected,
                symbol: "airpodspro", percent: 88, created: Date(),
                batteryReading: DeviceBatteryReading(left: 88, right: 92, casePercent: 64))
        case .keyboard:
            notice = IslandDeviceNotice(id: "preview-keyboard", title: "Flow84@Lofree", detail: connected,
                symbol: "keyboard", percent: 50, created: Date())
        case .charging, .unplugged:
            notice = IslandDeviceNotice(id: "mac-power", title: "MacBook",
                detail: l10n.string(vi: kind == .charging ? "Đang sạc" : "Đã rút sạc",
                                    en: kind == .charging ? "Charging" : "Power disconnected"),
                symbol: kind == .charging ? "powerplug.fill" : "battery.100percent",
                percent: 67, created: Date())
        case .lowBattery:
            notice = IslandDeviceNotice(id: "low:preview-mouse", title: "MX Anywhere 3S",
                detail: l10n.string(vi: "Pin yếu", en: "Low battery"),
                symbol: "computermouse", percent: 20, created: Date())
        }
        current = notice
        scheduleDismissal()
    }

    func start() {
        guard !started else { return }
        started = true
        MacPowerService.shared.$state.removeDuplicates().scan((nil as MacPowerState?, nil as MacPowerState?)) {
            ($0.1, $1)
        }.sink { [weak self] before, next in
            guard let before, let next, before.external != next.external else { return }
            let l10n = L10n.shared
            self?.enqueue(IslandDeviceNotice(id: "mac-power",
                title: l10n.string(vi: "MacBook", en: "MacBook"),
                detail: next.external
                    ? (next.charging ? l10n.string(vi: "Đang sạc", en: "Charging")
                       : l10n.string(vi: "Đã kết nối nguồn", en: "Power connected"))
                    : l10n.string(vi: "Đã rút sạc", en: "Power disconnected"),
                symbol: next.external ? "powerplug.fill" : "battery.100percent",
                percent: next.percent, created: Date()))
        }.store(in: &subscriptions)
        IslandController.shared.$isExpanded.removeDuplicates().receive(on: RunLoop.main).sink { [weak self] expanded in
            if expanded { self?.dismissCurrent() }
            else { self?.presentNext() }
        }.store(in: &subscriptions)
        let center = NSWorkspace.shared.notificationCenter
        center.publisher(for: NSWorkspace.willSleepNotification)
            .merge(with: center.publisher(for: NSWorkspace.sessionDidResignActiveNotification))
            .receive(on: RunLoop.main).sink { [weak self] _ in
            self?.sleeping = true
            self?.pending.removeAll()
            self?.devices.removeAll()
            self?.batteryReadings.removeAll()
            self?.dismissCurrent()
            self?.bluetooth?.setEnabled(false)
        }.store(in: &subscriptions)
        center.publisher(for: NSWorkspace.didWakeNotification)
            .merge(with: center.publisher(for: NSWorkspace.sessionDidBecomeActiveNotification))
            .receive(on: RunLoop.main).sink { [weak self] _ in
            self?.sleeping = false
            self?.bluetooth?.setEnabled(self?.canMonitorBluetooth == true)
        }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main).sink { [weak self] _ in
            guard let self else { return }
            self.bluetooth?.setEnabled(self.canMonitorBluetooth && !self.sleeping)
            if !self.enabled {
                self.pending.removeAll(); self.devices.removeAll(); self.batteryReadings.removeAll(); self.dismissCurrent()
            } else {
                self.pending.removeAll { $0.id.hasPrefix("low:") }
                if let current = self.current, current.id.hasPrefix("low:") {
                    let id = String(current.id.dropFirst(4))
                    if !self.batteryAlertsEnabled || self.batteryReadings[id].flatMap({
                        self.lowBattery.candidate(reading: $0, threshold: self.batteryThreshold)
                    }) == nil { self.dismissCurrent() }
                }
                self.presentNext()
            }
        }.store(in: &subscriptions)
        bluetooth = DeviceConnectionMonitor { [weak self] event in
            Task { @MainActor in self?.receive(event) }
        }
        bluetooth?.setEnabled(canMonitorBluetooth)
        AudioStudioService.shared.$outputDevices
            .combineLatest(AudioStudioService.shared.$selectedOutputID)
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { [weak self] outputs, selected in
                guard let self, !outputs.isEmpty, selected != 0 else { return }
                let airpods = outputs.filter { $0.name.localizedCaseInsensitiveContains("airpods") }
                let ids = Set(airpods.map(\.uid))
                let chosen = airpods.first { $0.id == selected }
                let changed = self.audioTransitions.consume(available: ids, selected: chosen?.uid)
                guard self.enabled, !self.sleeping else { return }
                for device in airpods where changed.contains(device.uid) {
                    let existing = self.devices.first { $0.value.name == device.name }?.key
                    let id = existing ?? "audio:" + device.uid
                    let symbol = device.name.localizedCaseInsensitiveContains("pro") ? "airpodspro"
                        : device.name.localizedCaseInsensitiveContains("max") ? "airpodsmax" : "airpods"
                    self.announceConnection(id: id, name: device.name, symbol: symbol)
                    self.bluetooth?.refreshBatteryReadings()
                }
            }.store(in: &subscriptions)
    }

    private var canMonitorBluetooth: Bool {
        enabled && CBManager.authorization == .allowedAlways
    }

    private var enabled: Bool {
        SensePillar.dynamicIsland.isEnabled()
            // Hoàn tất onboarding và giữ tùy chọn bật mới bắt đầu nhận diện phụ kiện.
            && (UserDefaults.standard.object(forKey: DefaultsKey.notchDeviceNotices) as? Bool ?? true)
    }

    private func receive(_ event: DeviceConnectionEvent) {
        guard enabled, !sleeping else { return }
        switch event {
        case let .observed(id, name, symbol, reading, announce):
            if announce { receive(.connected(id: id, name: name, symbol: symbol)) }
            else { devices[id] = (name, symbol) }
            if let reading { receive(.battery(id: id, reading: reading)) }
        case let .connected(id, name, symbol):
            announceConnection(id: id, name: name, symbol: symbol)
        case let .battery(id, reading):
            batteryReadings[id] = reading
            if lowBattery.observeRecovery(id: id, reading: reading, threshold: batteryThreshold) {
                saveBatteryHistory()
            }
            pending.removeAll { $0.id == "low:" + id }
            if current?.id == "low:" + id {
                if let updated = lowBatteryNotice(id: id, reading: reading) { current = updated }
                else { dismissCurrent(); presentNext() }
            } else if batteryAlertsEnabled, lowBattery.canPresent(id: id),
                      let notice = lowBatteryNotice(id: id, reading: reading) {
                enqueue(notice)
            }
            if current?.id == id || (current?.id.hasPrefix("audio:") == true && current?.title == devices[id]?.name) {
                current?.percent = reading.displayedPercent
                current?.batteryReading = reading
            }
            if let index = pending.firstIndex(where: { $0.id == id
                || ($0.id.hasPrefix("audio:") && $0.title == devices[id]?.name) }) {
                pending[index].percent = reading.displayedPercent
                pending[index].batteryReading = reading
            }
        case let .disconnected(id):
            devices.removeValue(forKey: id)
            batteryReadings.removeValue(forKey: id)
            pending.removeAll { $0.id == id || $0.id == "low:" + id }
            if current?.id == id || current?.id == "low:" + id { dismissCurrent(); presentNext() }
        }
    }

    private func lowBatteryNotice(id: String, reading: DeviceBatteryReading) -> IslandDeviceNotice? {
        guard batteryAlertsEnabled,
              let component = lowBattery.candidate(reading: reading, threshold: batteryThreshold),
              let percent = reading.level(component), let device = devices[id] else { return nil }
        let l10n = L10n.shared
        return IslandDeviceNotice(id: "low:" + id, title: device.name,
            detail: l10n.string(vi: percent <= 10 ? "Pin rất yếu" : "Pin yếu",
                                en: percent <= 10 ? "Battery very low" : "Low battery"),
            symbol: device.symbol, percent: percent, created: Date(),
            batteryReading: reading, batteryComponent: component)
    }

    private func announceConnection(id: String, name: String, symbol: String) {
        devices[id] = (name, symbol)
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let now = Date()
        lastConnectionNotices = lastConnectionNotices.filter { now.timeIntervalSince($0.value) < 3 }
        guard lastConnectionNotices[key] == nil else { return }
        lastConnectionNotices[key] = now
        enqueue(IslandDeviceNotice(id: id, title: name,
            detail: L10n.shared.string(vi: "Đã kết nối", en: "Connected"),
            symbol: symbol, percent: nil, created: now))
    }

    private func enqueue(_ notice: IslandDeviceNotice) {
        guard enabled, !sleeping else { return }
        if current?.id == notice.id { current = notice; scheduleDismissal(); return }
        pending.removeAll { $0.id == notice.id || Date().timeIntervalSince($0.created) > 12 }
        if pending.count >= 4 { pending.removeFirst() }
        pending.append(notice)
        presentNext()
    }

    private func presentNext() {
        guard enabled, !sleeping, current == nil, !IslandController.shared.isExpanded else { return }
        pending.removeAll { Date().timeIntervalSince($0.created) > 12 }
        guard !pending.isEmpty else { return }
        while !pending.isEmpty {
            var next = pending.removeFirst()
            if next.id.hasPrefix("low:") {
                guard IslandController.shared.hasVisibleNoticeSurface else {
                    pending.insert(next, at: 0)
                    return
                }
                let id = String(next.id.dropFirst(4))
                guard lowBattery.canPresent(id: id), let reading = batteryReadings[id],
                      let refreshed = lowBatteryNotice(id: id, reading: reading) else { continue }
                next = refreshed
                lowBattery.recordPresentation(id: id, reading: reading)
                saveBatteryHistory()
            }
            current = next
            break
        }
        guard current != nil else { return }
        scheduleDismissal()
    }

    private func scheduleDismissal() {
        deadline?.cancel()
        deadline = Task { [weak self] in
            let duration: Double = self?.current?.id.hasPrefix("low:") == true ? 4 : 3
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            self?.current = nil
            self?.presentNext()
        }
    }

    private func saveBatteryHistory() {
        UserDefaults.standard.set(lowBattery.lastPresented.filter { !$0.key.hasPrefix("hid:") },
                                  forKey: DefaultsKey.peripheralBatteryLastPresented)
        UserDefaults.standard.set(lowBattery.recoveryComponents.filter { !$0.key.hasPrefix("hid:") },
                                  forKey: DefaultsKey.peripheralBatteryRecoveryComponents)
    }

    private func dismissCurrent() {
        deadline?.cancel()
        deadline = nil
        current = nil
    }
}
