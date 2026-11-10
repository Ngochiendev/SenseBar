import AppKit
import ApplicationServices
import Combine

enum PermissionKind: String, CaseIterable, Identifiable {
    case accessibility

    var id: String { rawValue }
    var tccService: String { "Accessibility" }
}

/// Quản lý trạng thái và yêu cầu cấp quyền hệ thống (Accessibility) của SenseBar.
@MainActor
final class PermissionManager: ObservableObject {
    static let shared = PermissionManager()

    /// Trạng thái quyền Trợ năng (Accessibility) đã được cấp hay chưa.
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
        if !accessibilityGranted {
            startMonitoring(interval: 0.8)
        }
    }

    /// Tất cả quyền cần thiết để SenseBar hoạt động trọn vẹn đã được cấp.
    var allRequiredGranted: Bool {
        accessibilityGranted
    }

    /// Kiểm tra quyền tương ứng đã được cấp hay chưa.
    func isGranted(_ kind: PermissionKind) -> Bool {
        accessibilityGranted
    }

    /// Bắt đầu giám sát định kỳ trạng thái cấp quyền trong System Settings.
    /// - Parameter interval: Khoảng thời gian quét lại (giây).
    func startMonitoring(interval: TimeInterval = 0.5) {
        refreshStatus()
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshStatus()
            }
        }
    }

    /// Dừng giám sát định kỳ trạng thái cấp quyền.
    func stopMonitoring() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    /// Cập nhật ngay lập tức trạng thái quyền từ hệ thống macOS.
    func refreshStatus() {
        let axTrusted = AXIsProcessTrusted()
        if Thread.isMainThread {
            handleStatusChange(axTrusted)
        } else {
            DispatchQueue.main.async {
                self.handleStatusChange(axTrusted)
            }
        }
    }

    private func handleStatusChange(_ axTrusted: Bool) {
        let wasGranted = accessibilityGranted
        if accessibilityGranted != axTrusted {
            accessibilityGranted = axTrusted
        }
        // Khi vừa được cấp quyền (người dùng vừa bật toggle trong System Settings)
        if !wasGranted && axTrusted {
            PermissionGuideOverlay.shared.complete()
            DispatchQueue.main.async {
                IslandController.shared.permissionDidGrant()
            }
        }
        if wasGranted && !axTrusted {
            NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: nil)
            IslandController.shared.syncVisibility()
            AudioStudioService.shared.refreshAll()
        }
    }

    /// Yêu cầu cấp quyền Trợ năng: hiển thị hộp thoại hệ thống hoặc mở Cài đặt nếu chưa cấp.
    func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        refreshStatus()

        if !AXIsProcessTrusted() {
            openAccessibilitySettings()
            PermissionGuideOverlay.shared.show(for: .accessibility)
            // Kích hoạt quét nhanh (0.4s) để nhận biết ngay lập tức khi người dùng bật công tắc
            startMonitoring(interval: 0.4)
        }
    }

    /// Mở trực tiếp trang Cài đặt Trợ năng (Privacy & Security > Accessibility) trong System Settings.
    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Đặt lại quyền TCC thông qua lệnh hệ thống `tccutil` phục vụ gỡ lỗi.
    func resetPermission(_ kind: PermissionKind) {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.sensebar.SenseBar"
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
