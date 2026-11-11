import Foundation
import IOKit

/// Registry notifications cover BLE keyboards/mice without opening their input streams.
/// Owned exclusively by DeviceConnectionMonitor's worker run loop.
final class HIDPeripheralMonitor: @unchecked Sendable {
    private struct Entry {
        let service: io_service_t
        let id: String
        let name: String
        let symbol: String
    }
    private var port: IONotificationPortRef?
    private var iterators: [io_iterator_t] = []
    private var entries: [UInt64: Entry] = [:]
    private var timer: Timer?
    private let deliver: (DeviceConnectionEvent) -> Void

    init(deliver: @escaping (DeviceConnectionEvent) -> Void) { self.deliver = deliver }

    func start() {
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        self.port = port
        if let source = IONotificationPortGetRunLoopSource(port)?.takeUnretainedValue() {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        for name in ["IOHIDDevice", "AppleDeviceManagementHIDEventService"] {
            for added in [true, false] {
                var iterator: io_iterator_t = 0
                let addedCallback: IOServiceMatchingCallback = { context, iterator in
                    guard let context else { return }
                    let owner = Unmanaged<HIDPeripheralMonitor>.fromOpaque(context).takeUnretainedValue()
                    owner.consume(iterator, initial: false)
                }
                let removedCallback: IOServiceMatchingCallback = { context, iterator in
                    guard let context else { return }
                    Unmanaged<HIDPeripheralMonitor>.fromOpaque(context).takeUnretainedValue()
                        .consume(iterator, initial: false, removed: true)
                }
                guard let matching = IOServiceMatching(name),
                      IOServiceAddMatchingNotification(port,
                        added ? kIOFirstMatchNotification : kIOTerminatedNotification,
                        matching, added ? addedCallback : removedCallback,
                        Unmanaged.passUnretained(self).toOpaque(), &iterator) == KERN_SUCCESS
                else { continue }
                iterators.append(iterator)
                consume(iterator, initial: true, removed: !added)
            }
        }
    }

    func stop() {
        timer?.invalidate(); timer = nil
        iterators.forEach { IOObjectRelease($0) }; iterators.removeAll()
        if let port { IONotificationPortDestroy(port) }; port = nil
        entries.values.forEach { IOObjectRelease($0.service) }; entries.removeAll()
    }

    private func consume(_ iterator: io_iterator_t, initial: Bool, removed: Bool = false) {
        // Terminated services remain identifiable but are no longer registered.
        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            var registryID: UInt64 = 0
            IORegistryEntryGetRegistryEntryID(service, &registryID)
            if let existing = entries[registryID] {
                if removed {
                    entries.removeValue(forKey: registryID)
                    IOObjectRelease(existing.service)
                    if !entries.values.contains(where: { $0.id == existing.id }) {
                        deliver(.disconnected(id: existing.id))
                    }
                }
                IOObjectRelease(service)
                continue
            }
            guard !removed,
                  let values = properties(service),
                  (values["Transport"] as? String)?.lowercased().contains("bluetooth") == true,
                  let name = values["Product"] as? String, !name.isEmpty else {
                IOObjectRelease(service); continue
            }
            let address = ["DeviceAddress", "BluetoothAddress", "BD_ADDR", "SerialNumber"]
                .compactMap { values[$0] as? String }
                .first { Self.address($0) != nil }
            let id = address.flatMap(Self.address) ?? "hid:\(registryID)"
            let usage = (values["PrimaryUsage"] as? NSNumber)?.intValue
            let pairs = values["DeviceUsagePairs"] as? [[String: Any]] ?? []
            let isKeyboard = usage == 6 || pairs.contains {
                ($0["DeviceUsagePage"] as? NSNumber)?.intValue == 1
                    && ($0["DeviceUsage"] as? NSNumber)?.intValue == 6
            }
            let lower = name.lowercased()
            let symbol = isKeyboard || lower.contains("keyboard")
                ? "keyboard" : lower.contains("trackpad") ? "rectangle.and.hand.point.up.left" : "computermouse"
            let first = !entries.values.contains { $0.id == id }
            entries[registryID] = Entry(service: service, id: id, name: name, symbol: symbol)
            if first || Self.battery(values) != nil {
                deliver(.observed(id: id, name: name, symbol: symbol,
                    reading: Self.battery(values), announce: first && !initial))
            }
        }
        if entries.isEmpty { timer?.invalidate(); timer = nil }
        else if timer == nil {
            let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in self?.refresh() }
            timer.tolerance = 10
            self.timer = timer
            RunLoop.current.add(timer, forMode: .common)
        }
    }

    private func refresh() {
        var seen = Set<String>()
        for entry in entries.values where !seen.contains(entry.id) {
            guard let values = properties(entry.service), let reading = Self.battery(values) else { continue }
            seen.insert(entry.id)
            deliver(.observed(id: entry.id, name: entry.name, symbol: entry.symbol,
                              reading: reading, announce: false))
        }
    }

    private func properties(_ service: io_service_t) -> [String: Any]? {
        var value: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &value, kCFAllocatorDefault, 0) == KERN_SUCCESS else { return nil }
        return value?.takeRetainedValue() as? [String: Any]
    }

    static func address(_ value: String) -> String? {
        let hex = value.lowercased().filter { $0.isHexDigit }
        guard hex.count == 12 else { return nil }
        let chars = Array(hex)
        return stride(from: 0, to: 12, by: 2).map { String(chars[$0...($0 + 1)]) }.joined(separator: "-")
    }

    private static func battery(_ values: [String: Any]) -> DeviceBatteryReading? {
        guard let percent = (values["BatteryPercent"] as? NSNumber)?.doubleValue,
              percent.isFinite, (0...100).contains(percent) else { return nil }
        return DeviceBatteryReading(percent: Int(percent.rounded()))
    }
}

/// One alert per low-battery episode, with recovery hysteresis and a critical escalation.
struct PeripheralLowBatteryPolicy {
    private var announced: [String: Int] = [:]
    mutating func consume(id: String, reading: DeviceBatteryReading) -> Int? {
        let levels = [reading.percent, reading.left, reading.right, reading.casePercent]
            .compactMap { $0 }.filter { (0...100).contains($0) }
        guard let percent = levels.min() else { return nil }
        if percent >= 25 { announced.removeValue(forKey: id); return nil }
        guard percent <= 20 else { return nil }
        let stage = percent <= 10 ? 10 : 20
        guard announced[id].map({ stage < $0 }) ?? true else { return nil }
        if announced.count >= 128, announced[id] == nil { announced.removeAll() }
        announced[id] = stage
        return percent
    }
}
