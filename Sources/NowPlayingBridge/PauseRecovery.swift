import Foundation

/// A transition opens one bounded recovery window; repeated pause samples do not extend it.
struct PauseRecovery {
    private var wasPlaying = false
    private var expiresAt: TimeInterval?

    mutating func observe(playing: Bool, now: TimeInterval) -> [TimeInterval] {
        defer { wasPlaying = playing }
        if playing { expiresAt = nil; return [] }
        guard wasPlaying else { return [] }
        expiresAt = now + 1.2
        // The final read occurs after expiry so the UI always leaves recovery.
        return [0.15, 0.5, 1.25]
    }

    func isActive(at now: TimeInterval) -> Bool {
        expiresAt.map { now < $0 } == true
    }
}
