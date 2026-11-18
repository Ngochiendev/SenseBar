import Foundation
import IOKit.ps
import Darwin

/// Optional powerd telemetry. No name/percentage matching and no charging inference.
/// API/keys verified against Apple's IOKitUser ps.subproj sources; this symbol is not public API.
enum AccessoryPowerSourceReader {
    private typealias CopySources = @convention(c) (Int32) -> Unmanaged<CFTypeRef>?

    static func read() -> [[String: Any]] {
        guard let handle = dlopen(nil, RTLD_LAZY) else { return [] }
        defer { dlclose(handle) }
        guard let symbol = dlsym(handle, "IOPSCopyPowerSourcesByType") else { return [] }
        let copySources = unsafeBitCast(symbol, to: CopySources.self)
        guard let snapshot = copySources(0)?.takeRetainedValue(),
              CFGetTypeID(snapshot) == CFArrayGetTypeID(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else { return [] }
        return sources.compactMap {
            IOPSGetPowerSourceDescription(snapshot, $0)?.takeUnretainedValue() as? [String: Any]
        }
    }

    /// Group Identifier relates parts; Part Identifier supplies Left/Right/Case semantics.
    /// Accept an address or a UUID obtained from that native device, never one inferred from its name.
    static func battery(in descriptions: [[String: Any]], address: String,
                        identifier: String? = nil) -> DeviceBatteryReading? {
        guard let addressIdentity = bluetoothAddress(address) else { return nil }
        var identities: Set<String> = [addressIdentity]
        if let identifier, let uuid = UUID(uuidString: identifier) { identities.insert(uuid.uuidString) }
        var records: [DeviceBatteryReading.Component: [[String: Any]]] = [:]
        for value in descriptions {
            guard value[kIOPSTypeKey] as? String == "Accessory Source",
                  DeviceBatteryReading.boolean(value[kIOPSIsPresentKey]) != false else { continue }
            let group = (value["Group Identifier"] as? String).flatMap(sourceIdentity)
            let accessory = (value["Accessory Identifier"] as? String).flatMap(sourceIdentity)
            guard let identity = group ?? accessory, identities.contains(identity) else { continue }
            let component: DeviceBatteryReading.Component
            switch value["Part Identifier"] as? String {
            case "Left": component = .left
            case "Right": component = .right
            case "Case": component = .batteryCase
            case "Single", nil: component = .main
            default: continue
            }
            records[component, default: []].append(value)
        }
        var result = DeviceBatteryReading()
        var found = false
        for (component, values) in records where values.count == 1 {
            let value = values[0]
            let current = value[kIOPSCurrentCapacityKey] as? NSNumber
            let maximum = value[kIOPSMaxCapacityKey] as? NSNumber
            var percent: Int?
            if let current, CFGetTypeID(current) != CFBooleanGetTypeID(),
               let maximum, CFGetTypeID(maximum) != CFBooleanGetTypeID(),
               current.doubleValue.isFinite, maximum.doubleValue.isFinite,
               maximum.doubleValue > 0, current.doubleValue >= 0,
               current.doubleValue <= maximum.doubleValue {
                percent = Int((current.doubleValue / maximum.doubleValue * 100).rounded())
            }
            let charging = DeviceBatteryReading.boolean(value[kIOPSIsChargingKey])
            found = found || percent != nil || charging != nil
            switch component {
            case .main: result.percent = percent; result.charging = charging
            case .left: result.left = percent; result.leftCharging = charging
            case .right: result.right = percent; result.rightCharging = charging
            case .batteryCase: result.casePercent = percent; result.caseCharging = charging
            }
        }
        return found ? result : nil
    }

    private static func bluetoothAddress(_ value: String) -> String? {
        let compact = value.lowercased().replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
        guard compact.count == 12, compact.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return nil }
        return compact
    }

    private static func sourceIdentity(_ value: String) -> String? {
        bluetoothAddress(value) ?? UUID(uuidString: value)?.uuidString
    }
}
