import AppKit
import ApplicationServices
import CoreGraphics

/// Đếm cả cửa sổ ngoài màn hình/thu nhỏ; không đọc tiêu đề hoặc nội dung trang.
enum BrowserWindowSnapshot {
    static func closedBundles() -> Set<String> {
        guard let windows = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return [] }
        let owners = Set(windows.compactMap(browserWindowOwner))
        let trusted = AXIsProcessTrusted()
        return Set(NSWorkspace.shared.runningApplications.compactMap { app in
            guard let bundle = app.bundleIdentifier, isBrowser(bundle), !app.isTerminated else { return nil }
            if trusted, let count = accessibilityWindowCount(pid: app.processIdentifier) {
                return count == 0 ? bundle : nil
            }
            return owners.contains(app.processIdentifier) ? nil : bundle
        })
    }

    /// Safari giữ các cửa sổ menu/helper ở layer 0 sau khi đóng cửa sổ cuối cùng.
    /// Đây chỉ là dự phòng khi AX không khả dụng; không dùng trạng thái onscreen để loại cửa sổ thu nhỏ.
    static func browserWindowOwner(_ window: [String: Any]) -> Int32? {
        guard (window[kCGWindowLayer as String] as? Int) == 0,
              let bounds = window[kCGWindowBounds as String] as? [String: Any],
              let width = bounds["Width"] as? NSNumber, let height = bounds["Height"] as? NSNumber,
              width.doubleValue >= 100, height.doubleValue >= 100 else { return nil }
        return (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
    }

    private static func accessibilityWindowCount(pid: Int32) -> Int? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.15)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return nil }
        return windows.count
    }

    static func isBrowser(_ bundle: String) -> Bool {
        let id = bundle.lowercased()
        return ["com.apple.safari", "com.apple.safaritechnologypreview", "com.google.chrome",
                "com.google.chrome.canary", "com.google.chrome.beta", "com.brave.browser",
                "com.microsoft.edgemac", "company.thebrowser.browser", "com.vivaldi.vivaldi",
                "com.operasoftware.opera", "org.chromium.chromium", "org.mozilla.firefox",
                "app.zen-browser.zen"].contains(id)
    }
}
