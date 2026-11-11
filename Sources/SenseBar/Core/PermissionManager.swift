import AppKit
import ApplicationServices
import Combine
import CoreBluetooth

/// Quản lý trạng thái và yêu cầu cấp quyền hệ thống (Accessibility) của SenseBar.
@MainActor
final class PermissionManager: NSObject, ObservableObject, CBCentralManagerDelegate {
    static let shared = PermissionManager()

    /// Trạng thái quyền Trợ năng (Accessibility) đã được cấp hay chưa.
    @Published private(set) var accessibilityGranted: Bool = false
    @Published private(set) var bluetoothGranted = CBManager.authorization == .allowedAlways
    private var bluetoothManager: CBCentralManager?

    private var pollTimer: Timer?
    private var appActiveObserver: NSObjectProtocol?
    private var lastSettingsOpen = -Double.infinity

    private override init() {
        super.init()
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

    /// Bắt đầu giám sát định kỳ trạng thái cấp quyền trong System Settings.
    /// - Parameter interval: Khoảng thời gian quét lại (giây).
    func startMonitoring(interval: TimeInterval = 0.5) {
        refreshStatus()
        pollTimer?.invalidate()
        guard !accessibilityGranted else { pollTimer = nil; return }
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
        let bluetoothAllowed = CBManager.authorization == .allowedAlways
        if bluetoothGranted != bluetoothAllowed {
            bluetoothGranted = bluetoothAllowed
            NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: nil)
        }
        let axTrusted = AXIsProcessTrusted()
        if Thread.isMainThread {
            handleStatusChange(axTrusted)
        } else {
            DispatchQueue.main.async {
                self.handleStatusChange(axTrusted)
            }
        }
    }

    /// Xin quyền phụ kiện khi người dùng chủ động bấm, không gắn với nút hoàn tất.
    func requestBluetooth() {
        if CBManager.authorization == .denied || CBManager.authorization == .restricted {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth") {
                NSWorkspace.shared.open(url)
            }
            return
        }
        guard bluetoothManager == nil else { return }
        bluetoothManager = CBCentralManager(delegate: self, queue: .main,
            options: [CBCentralManagerOptionShowPowerAlertKey: false])
    }

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor [weak self] in
            self?.bluetoothGranted = CBManager.authorization == .allowedAlways
            NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: nil)
        }
    }

    private func handleStatusChange(_ axTrusted: Bool) {
        let wasGranted = accessibilityGranted
        if accessibilityGranted != axTrusted {
            accessibilityGranted = axTrusted
        }
        // Khi vừa được cấp quyền (người dùng vừa bật toggle trong System Settings)
        if !wasGranted && axTrusted {
            stopMonitoring()
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

    /// Mở trang cấp quyền trực tiếp, dùng hướng dẫn trong app thay cho các popup trùng lặp.
    func requestAccessibility() {
        refreshStatus()
        if !accessibilityGranted {
            openAccessibilitySettings()
        }
    }

    /// Mở trực tiếp trang Cài đặt Trợ năng (Privacy & Security > Accessibility) trong System Settings.
    func openAccessibilitySettings() {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastSettingsOpen >= 1 else { return }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            lastSettingsOpen = now
            NSWorkspace.shared.open(url)
            startMonitoring(interval: 0.8)
        }
    }
}
