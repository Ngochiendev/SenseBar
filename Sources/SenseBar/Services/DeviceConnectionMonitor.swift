import Foundation
import IOBluetooth
import IOKit

enum DeviceConnectionEvent: Sendable {
    case observed(id: String, name: String, symbol: String, reading: DeviceBatteryReading?, announce: Bool)
    case connected(id: String, name: String, symbol: String)
    case battery(id: String, reading: DeviceBatteryReading)
    case disconnected(id: String)
}

struct DeviceBatteryReading: Equatable, Sendable {
    var percent: Int?
    var left: Int?
    var right: Int?
    var casePercent: Int?
}

/// Native Bluetooth calls stay on one stable run loop, including observer cleanup.
final class DeviceConnectionMonitor: NSObject, @unchecked Sendable {
    private let lock = NSLock()
    private var desired = false
    private var generation = 0
    private var runLoop: CFRunLoop?
    private var launched = false
    private var workQueue: [() -> Void] = []
    private var draining = false
    private var connectToken: IOBluetoothUserNotification?
    private var disconnectTokens: [String: IOBluetoothUserNotification] = [:]
    private var connected = Set<String>()
    private var connectionEpochs: [String: UUID] = [:]
    private var hid: HIDPeripheralMonitor?
    private var batteryTimer: Timer?
    private var batteryRefreshPending = false
    private var batteryRefreshRequested = false
    private var names: [String: (name: String, symbol: String)] = [:]
    private let deliver: @Sendable (DeviceConnectionEvent) -> Void
    private let batteryQueue = DispatchQueue(label: "SenseBar.device-battery", qos: .utility)

    init(deliver: @escaping @Sendable (DeviceConnectionEvent) -> Void) { self.deliver = deliver }

    func setEnabled(_ enabled: Bool) {
        let action = lock.withLock { () -> (Bool, CFRunLoop?) in
            guard desired != enabled else { return (false, nil) }
            desired = enabled
            generation += 1
            let launch = enabled && !launched
            if launch { launched = true }
            return (launch, runLoop)
        }
        if action.0 {
            let worker = Thread { [self] in
                let loop = CFRunLoopGetCurrent()!
                RunLoop.current.add(NSMachPort(), forMode: .common)
                lock.withLock { runLoop = loop }
                onWorker { [self] in synchronize() }
                CFRunLoopRun()
            }
            worker.name = "SenseBar device events"
            worker.qualityOfService = .utility
            worker.start()
        } else if action.1 != nil {
            onWorker { [self] in synchronize() }
        }
    }

    private func synchronize() {
        hid?.stop(); hid = nil
        batteryTimer?.invalidate(); batteryTimer = nil
        connectToken?.unregister()
        connectToken = nil
        disconnectTokens.values.forEach { $0.unregister() }
        disconnectTokens.removeAll()
        connected.removeAll()
        connectionEpochs.removeAll()
        names.removeAll()
        guard lock.withLock({ desired }) else { return }
        let epoch = lock.withLock { generation }
        for device in IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? [] {
            guard isActive(epoch) else { return }
            if device.isConnected(), let raw = device.addressString, let id = HIDPeripheralMonitor.address(raw) {
                connected.insert(id)
                observeDisconnect(device, id: id)
                let major = UInt32(device.deviceClassMajor)
                if !(1...3).contains(major), let name = device.name {
                    let symbol = name.lowercased().contains("airpods") ? "airpods" : major == 5 ? "computermouse" : "headphones"
                    names[id] = (name, symbol)
                    connectionEpochs[id] = UUID()
                    deliver(.observed(id: id, name: name, symbol: symbol, reading: nil, announce: false))
                }
            }
        }
        guard isActive(epoch) else { return }
        connectToken = IOBluetoothDevice.register(forConnectNotifications: self,
            selector: #selector(didConnect(_:device:)))
        hid = HIDPeripheralMonitor { [weak self] event in
            guard let self, self.isActive(epoch) else { return }
            self.deliver(event)
        }
        hid?.start()
        refreshBatteries()
    }

    private func isActive(_ epoch: Int) -> Bool { lock.withLock { desired && generation == epoch } }

    private func observeDisconnect(_ device: IOBluetoothDevice, id: String) {
        guard disconnectTokens[id] == nil else { return }
        disconnectTokens[id] = device.register(forDisconnectNotification: self,
            selector: #selector(didDisconnect(_:device:)))
    }

    @objc private func didConnect(_ token: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        onWorker { [self] in handleConnect(token, device: device) }
    }

    private func onWorker(_ work: @escaping () -> Void) {
        let loop = lock.withLock { () -> CFRunLoop? in
            workQueue.append(work)
            guard !draining, let runLoop else { return nil }
            draining = true
            return runLoop
        }
        guard let loop else { return }
        CFRunLoopPerformBlock(loop, CFRunLoopMode.commonModes.rawValue) { [self] in
            // Reserve the drain across native calls: their nested run loops must
            // not interleave observer teardown with registration or device reads.
            while let action = lock.withLock({ () -> (() -> Void)? in
                guard !workQueue.isEmpty else { draining = false; return nil }
                return workQueue.removeFirst()
            }) {
                autoreleasepool(invoking: action)
            }
        }
        CFRunLoopWakeUp(loop)
    }

    private func handleConnect(_ token: IOBluetoothUserNotification, device: IOBluetoothDevice, attempt: Int = 0) {
        let epoch = lock.withLock { generation }
        guard isActive(epoch), token === connectToken,
              let raw = device.addressString, let id = HIDPeripheralMonitor.address(raw),
              !connected.contains(id) else { return }
        guard device.isConnected(), let name = device.name, !name.isEmpty else {
            if attempt < 2 {
                let retry = DispatchWorkItem { [weak self] in
                    self?.onWorker { [weak self] in
                        guard self?.isActive(epoch) == true else { return }
                        self?.handleConnect(token, device: device, attempt: attempt + 1)
                    }
                }
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.4, execute: retry)
            }
            return
        }
        observeDisconnect(device, id: id)
        let major = UInt32(device.deviceClassMajor)
        guard !(1...3).contains(major) else { return }
        connected.insert(id)
        let minor = UInt32(device.deviceClassMinor)
        let lower = name.lowercased()
        let symbol = lower.contains("airpods pro") ? "airpodspro"
            : lower.contains("airpods max") ? "airpodsmax"
            : lower.contains("airpods") ? "airpods"
            : major == 4 ? "headphones"
            : major == 5 && minor & 0x10 != 0 ? "keyboard"
            : major == 5 ? "computermouse" : "dot.radiowaves.left.and.right"
        deliver(.connected(id: id, name: name, symbol: symbol))
        names[id] = (name, symbol)
        let connectionEpoch = UUID()
        connectionEpochs[id] = connectionEpoch
        refreshBatteries()
    }

    func refreshBatteryReadings() {
        onWorker { [weak self] in self?.refreshBatteries() }
    }

    @objc private func didDisconnect(_ token: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        onWorker { [self] in handleDisconnect(token, device: device) }
    }

    private func handleDisconnect(_ token: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        guard let raw = device.addressString, let id = HIDPeripheralMonitor.address(raw),
              disconnectTokens[id] === token else { return }
        disconnectTokens.removeValue(forKey: id)?.unregister()
        connected.remove(id)
        connectionEpochs.removeValue(forKey: id)
        names.removeValue(forKey: id)
        if names.isEmpty { batteryTimer?.invalidate(); batteryTimer = nil }
        if lock.withLock({ desired }) { deliver(.disconnected(id: id)) }
    }

    private func refreshBatteries() {
        guard !names.isEmpty, lock.withLock({ desired }) else { return }
        guard !batteryRefreshPending else { batteryRefreshRequested = true; return }
        batteryRefreshRequested = false
        if batteryTimer == nil {
            let timer = Timer(timeInterval: 300, repeats: true) { [weak self] _ in self?.refreshBatteries() }
            timer.tolerance = 30
            batteryTimer = timer
            RunLoop.current.add(timer, forMode: .common)
        }
        let epoch = lock.withLock { generation }
        let devices = names
        let epochs = connectionEpochs
        batteryRefreshPending = true
        batteryQueue.async { [self] in
            let data = isActive(epoch) ? Self.readBluetoothData() : nil
            let readings = devices.keys.reduce(into: [String: DeviceBatteryReading]()) { result, id in
                result[id] = Self.readHIDBattery(address: id).map { DeviceBatteryReading(percent: $0) }
                    ?? data.flatMap { Self.battery(in: $0, address: id) }
            }
            onWorker { [self] in
                batteryRefreshPending = false
                guard isActive(epoch) else { refreshBatteries(); return }
                for (id, reading) in readings where connectionEpochs[id] == epochs[id] {
                    guard let device = names[id] else { continue }
                    deliver(.observed(id: id, name: device.name, symbol: device.symbol,
                                      reading: reading, announce: false))
                }
                if batteryRefreshRequested { refreshBatteries() }
            }
        }
    }

    /// Bounded metadata query on the battery worker, with a timeout and output cap.
    private static func readBluetoothData() -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2, execute: timeout)
        var data = Data()
        while let part = try? pipe.fileHandleForReading.read(upToCount: 16_384), !part.isEmpty {
            guard data.count + part.count <= 1_048_576 else { process.terminate(); timeout.cancel(); return nil }
            data.append(part)
        }
        timeout.cancel()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return data
    }

    static func battery(in data: Data, address: String) -> DeviceBatteryReading? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let controllers = root["SPBluetoothDataType"] as? [[String: Any]] else { return nil }
        func normalized(_ value: String) -> String { value.lowercased().replacingOccurrences(of: "-", with: ":") }
        for controller in controllers {
            for entry in controller["device_connected"] as? [[String: Any]] ?? [] {
                for value in entry.values {
                    guard let properties = value as? [String: Any],
                          let candidate = properties["device_address"] as? String,
                          normalized(candidate) == normalized(address) else { continue }
                    let reading = DeviceBatteryReading(
                        percent: validPercent(properties["device_batteryLevelMain"])
                            ?? validPercent(properties["device_batteryLevel"]),
                        left: validPercent(properties["device_batteryLevelLeft"]),
                        right: validPercent(properties["device_batteryLevelRight"]),
                        casePercent: validPercent(properties["device_batteryLevelCase"]))
                    if reading != DeviceBatteryReading() { return reading }
                }
            }
        }
        return nil
    }

    private static func validPercent(_ value: Any?) -> Int? {
        let number: Double?
        if let raw = value as? String {
            number = Double(raw.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces))
        } else { number = (value as? NSNumber)?.doubleValue }
        guard let number, number.isFinite, (0...100).contains(number) else { return nil }
        return Int(number.rounded())
    }

    private static func readHIDBattery(address: String) -> Int? {
        func normalized(_ value: String) -> String {
            value.lowercased().filter { $0.isHexDigit }
        }
        for className in ["AppleDeviceManagementHIDEventService", "IOHIDDevice"] {
            guard let matching = IOServiceMatching(className) else { continue }
            var iterator: io_iterator_t = 0
            guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { continue }
            defer { IOObjectRelease(iterator) }
            var service = IOIteratorNext(iterator)
            while service != 0 {
                let entry = service
                service = IOIteratorNext(iterator)
                defer { IOObjectRelease(entry) }
                var properties: Unmanaged<CFMutableDictionary>?
                guard IORegistryEntryCreateCFProperties(entry, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                      let values = properties?.takeRetainedValue() as? [String: Any] else { continue }
                let ids = [values["DeviceAddress"], values["BluetoothAddress"], values["SerialNumber"]]
                guard ids.contains(where: { ($0 as? String).map { normalized($0) == normalized(address) } ?? false }) else { continue }
                if let percent = validPercent(values["BatteryPercent"]) { return percent }
            }
        }
        return nil
    }
}
