import Foundation

/// Identifies builds across disable, sleep and restart. An obsolete completion
/// must neither install an engine nor clear a newer build for the same app.
struct AudioTapBuilds {
    private(set) var revision = UUID()
    private var pending: [String: UUID] = [:]

    mutating func begin(_ app: String) -> UUID? {
        guard pending[app] == nil else { return nil }
        let ticket = UUID()
        pending[app] = ticket
        return ticket
    }

    mutating func finish(_ app: String, ticket: UUID) -> Bool {
        guard pending[app] == ticket else { return false }
        pending.removeValue(forKey: app)
        return true
    }

    mutating func invalidate() {
        revision = UUID()
        pending.removeAll()
    }

    static func needsEngine(volume: Double, playing: Bool, hasEngine: Bool, equalizer: Bool = false) -> Bool {
        // Retain adjusted/muted taps even during pause: dropping them would let
        // the first resumed frames escape at the app's original volume.
        equalizer || abs(volume - 1) >= 0.005 || (hasEngine && playing)
    }
}
