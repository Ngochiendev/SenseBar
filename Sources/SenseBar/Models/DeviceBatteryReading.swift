import Foundation
import CoreFoundation

/// Charging belongs to a specific battery, never implicitly to an entire headset.
struct DeviceBatteryReading: Equatable, Sendable {
    enum Component: String, CaseIterable, Sendable {
        case main, left, right, batteryCase
    }

    var percent: Int?
    var left: Int?
    var right: Int?
    var casePercent: Int?
    var charging: Bool?
    var leftCharging: Bool?
    var rightCharging: Bool?
    var caseCharging: Bool?

    func level(_ component: Component) -> Int? {
        let value: Int?
        switch component {
        case .main: value = percent
        case .left: value = left
        case .right: value = right
        case .batteryCase: value = casePercent
        }
        return value.flatMap { (0...100).contains($0) ? $0 : nil }
    }

    func isCharging(_ component: Component) -> Bool? {
        switch component {
        case .main: charging
        case .left: leftCharging
        case .right: rightCharging
        case .batteryCase: caseCharging
        }
    }

    var hasComponents: Bool { left != nil || right != nil || casePercent != nil }

    /// An aggregate level cannot identify which earbud is low or charging.
    var alertComponents: [Component] { hasComponents ? [.left, .right, .batteryCase] : [.main] }

    var lowestUnchargedComponent: Component? {
        alertComponents.filter { level($0) != nil && isCharging($0) != true }
            .min { level($0)! < level($1)! }
    }

    var displayedPercent: Int? {
        if hasComponents { return alertComponents.compactMap(level).min() }
        return level(.main)
    }

    /// Merge only observations from the same refresh and physical identity.
    func fillingMissing(from fallback: Self?) -> Self {
        guard let fallback else { return self }
        return Self(percent: percent ?? fallback.percent, left: left ?? fallback.left,
                    right: right ?? fallback.right, casePercent: casePercent ?? fallback.casePercent,
                    charging: charging ?? fallback.charging,
                    leftCharging: leftCharging ?? fallback.leftCharging,
                    rightCharging: rightCharging ?? fallback.rightCharging,
                    caseCharging: caseCharging ?? fallback.caseCharging)
    }

    static func hid(_ values: [String: Any]) -> Self? {
        let percent = validPercent(values["BatteryPercent"])
        let charging = boolean(values["IsCharging"]) ?? boolean(values["Is Charging"])
        guard percent != nil || charging != nil else { return nil }
        return Self(percent: percent, charging: charging)
    }

    static func validPercent(_ value: Any?) -> Int? {
        let number: Double?
        if let text = value as? String {
            number = Double(text.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces))
        } else if let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() {
            number = value.doubleValue
        } else { number = nil }
        guard let number, number.isFinite, (0...100).contains(number) else { return nil }
        return Int(number.rounded())
    }

    static func boolean(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber else { return nil }
        if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue }
        guard number.doubleValue == 0 || number.doubleValue == 1 else { return nil }
        return number.boolValue
    }
}
