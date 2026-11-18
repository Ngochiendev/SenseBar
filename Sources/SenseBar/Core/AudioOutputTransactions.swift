import Foundation

/// Serializes HAL operations and skips superseded commands before they touch a device.
final class AudioOutputTransactions: @unchecked Sendable {
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "SenseBar.output-controls", qos: .userInitiated)
    private var revision: UInt64 = 0

    var current: UInt64 { lock.withLock { revision } }

    @discardableResult
    func invalidate() -> UInt64 {
        lock.withLock { revision &+= 1; return revision }
    }

    func perform<T: Sendable>(_ ticket: UInt64, operation: @escaping @Sendable () -> T) async -> T? {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                guard current == ticket else { continuation.resume(returning: nil); return }
                continuation.resume(returning: operation())
            }
        }
    }
}
