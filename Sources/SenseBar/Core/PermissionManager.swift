import AppKit
import ApplicationServices
import Combine

enum PermissionKind: String, CaseIterable, Identifiable {
    case accessibility

    var id: String { rawValue }
    var tccService: String { "Accessibility" }
}

@MainActor
final class PermissionManager: ObservableObject {
    static let shared = PermissionManager()

    @Published private(set) var accessibilityGranted: Bool = false

    private var pollTimer: Timer?
    private var appActiveObserver: NSObjectProtocol?

    private init() {
        refreshStatus()
        appActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshStatus()
            }
        }
    }

    var allRequiredGranted: Bool {
        accessibilityGranted
    }

    func isGranted(_ kind: PermissionKind) -> Bool {
        accessibilityGranted
    }

    func startMonitoring(interval: TimeInterval = 1.0) {
        refreshStatus()
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshStatus()
            }
        }
    }

    func stopMonitoring() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func refreshStatus() {
        let axTrusted = AXIsProcessTrusted()
        if Thread.isMainThread {
            if accessibilityGranted != axTrusted { accessibilityGranted = axTrusted }
        } else {
            DispatchQueue.main.async {
                if self.accessibilityGranted != axTrusted { self.accessibilityGranted = axTrusted }
            }
        }
    }

    func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        refreshStatus()

        if !AXIsProcessTrusted() {
            openAccessibilitySettings()
            PermissionGuideOverlay.shared.show(for: .accessibility)
        }
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func resetPermission(_ kind: PermissionKind) {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.ngochiendev.sensebar"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", kind.tccService, bundleID]
        try? process.run()
        process.waitUntilExit()
        refreshStatus()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.requestAccessibility()
        }
    }
}
