import Foundation

/// A low-battery episode ends only after observed recovery, not after a timer or reconnect.
struct PeripheralLowBatteryPolicy: Codable {
    private(set) var lastPresented: [String: Date]
    private(set) var recoveryComponents: [String: [String]]

    init(lastPresented: [String: Date] = [:], recoveryComponents: [String: [String]] = [:]) {
        self.lastPresented = lastPresented
        self.recoveryComponents = recoveryComponents
    }

    func candidate(reading: DeviceBatteryReading, threshold: Int) -> DeviceBatteryReading.Component? {
        guard let component = reading.lowestUnchargedComponent,
              let percent = reading.level(component), percent <= Self.threshold(threshold) else { return nil }
        return component
    }

    func canPresent(id: String) -> Bool { lastPresented[id] == nil }

    @discardableResult
    mutating func observeRecovery(id: String, reading: DeviceBatteryReading, threshold: Int) -> Bool {
        guard lastPresented[id] != nil else { return false }
        // Older histories have no component list; learn it from the first valid observation.
        let parts = recoveryComponents[id]?.compactMap(DeviceBatteryReading.Component.init(rawValue:))
            ?? reading.alertComponents.filter { reading.level($0) != nil }
        guard !parts.isEmpty else { return false }
        if recoveryComponents[id] == nil { recoveryComponents[id] = parts.map(\.rawValue) }
        guard parts.allSatisfy({ (reading.level($0) ?? -1) >= Self.threshold(threshold) + 10 }) else { return false }
        lastPresented.removeValue(forKey: id)
        recoveryComponents.removeValue(forKey: id)
        return true
    }

    mutating func recordPresentation(id: String, reading: DeviceBatteryReading, threshold: Int = 20, now: Date = Date()) {
        if lastPresented.count >= 512, lastPresented[id] == nil,
           let oldest = lastPresented.min(by: { $0.value < $1.value })?.key {
            lastPresented.removeValue(forKey: oldest)
            recoveryComponents.removeValue(forKey: oldest)
        }
        lastPresented[id] = now
        recoveryComponents[id] = reading.alertComponents.filter {
            guard let level = reading.level($0) else { return false }
            return level <= Self.threshold(threshold) && reading.isCharging($0) != true
        }.map(\.rawValue)
    }

    var persistentHistory: Self {
        Self(lastPresented: lastPresented.filter { !$0.key.hasPrefix("hid:") },
             recoveryComponents: recoveryComponents.filter { !$0.key.hasPrefix("hid:") })
    }

    static func threshold(_ value: Int) -> Int { min(50, max(5, value)) }
}
