import AppKit
import ApplicationServices

/// Kết hợp khung cửa sổ đang hiển thị với cờ fullscreen do ứng dụng cung cấp qua AX.
/// Cửa sổ phủ màn hình nhưng chỉ nằm phía sau một ứng dụng khác không làm ẩn Island.
@MainActor
public enum FullscreenDetector {
    struct Surface {
        let owner: pid_t
        let frame: CGRect
        let level: Int
    }

    static func coversDisplay(_ window: CGRect, display: CGRect) -> Bool {
        guard display.width > 0, display.height > 0 else { return false }
        let tolerance: CGFloat = 1
        return window.minX <= display.minX + tolerance
            && window.minY <= display.minY + tolerance
            && window.maxX >= display.maxX - tolerance
            && window.maxY >= display.maxY - tolerance
    }

    static func isFullscreen(surfaces: [Surface], display: CGRect,
                             activePID: pid_t?, axFullscreen: Bool) -> Bool {
        guard let foreground = surfaces.first(where: { $0.level == 0 && $0.frame.intersects(display) }) else {
            return false
        }
        if coversDisplay(foreground.frame, display: display) { return true }
        if foreground.owner == activePID && axFullscreen { return true }
        return surfaces.contains { surface in
            surface.level > 0 && surface.owner == foreground.owner
                && coversDisplay(surface.frame, display: display)
        }
    }

    private static var cachedSurfaces: [Surface] = []
    private static var sampledAt: TimeInterval = -.infinity

    public static func isFullscreen(on displayID: CGDirectDisplayID) -> Bool {
        let display = CGDisplayBounds(displayID)
        let now = ProcessInfo.processInfo.systemUptime
        if now - sampledAt > 0.05 {
        guard let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], 0)
                as? [[String: Any]] else { return false }
        let ownProcess = ProcessInfo.processInfo.processIdentifier
        let surfaces = raw.compactMap { entry -> Surface? in
            guard let owner = entry[kCGWindowOwnerPID as String] as? Int32, owner != ownProcess,
                  (entry[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let bounds = entry[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  let level = entry[kCGWindowLayer as String] as? Int else { return nil }
            return Surface(owner: owner, frame: frame, level: level)
        }
        cachedSurfaces = surfaces
        sampledAt = now
        }
        let surfaces = cachedSurfaces
        if isFullscreen(surfaces: surfaces, display: display, activePID: nil, axFullscreen: false) { return true }
        let active = NSWorkspace.shared.frontmostApplication?.processIdentifier
        return isFullscreen(surfaces: surfaces, display: display, activePID: active,
                            axFullscreen: active.map { accessibilityFullscreen(pid: $0, display: display) } ?? false)
    }

    public static func isFullscreen(on screen: NSScreen) -> Bool {
        isFullscreen(on: screen.displayID)
    }

    private static func accessibilityFullscreen(pid: pid_t, display: CGRect) -> Bool {
        guard AXIsProcessTrusted() else { return false }
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.05)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXFocusedWindowAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return false }
        let window = unsafeDowncast(focused, to: AXUIElement.self)
        var fullscreen: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &fullscreen) == .success,
              (fullscreen as? Bool) == true else { return false }
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else { return false }
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(unsafeDowncast(positionValue, to: AXValue.self), .cgPoint, &origin),
              AXValueGetValue(unsafeDowncast(sizeValue, to: AXValue.self), .cgSize, &size) else { return false }
        let intersection = CGRect(origin: origin, size: size).intersection(display)
        return intersection.width * intersection.height >= display.width * display.height * 0.9
    }
}
