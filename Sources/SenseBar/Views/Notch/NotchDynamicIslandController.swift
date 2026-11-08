import AppKit
import Combine
import SwiftUI

// MARK: - NotchPanel tùy chỉnh (Luôn giữ active appearance cho Liquid Glass & hỗ trợ đa màn hình)

final class SenseNotchPanel: NSPanel {
    static let overlayCollectionBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle
    ]
    static let normalLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    @objc func _hasActiveAppearanceIgnoringKeyFocus() -> Bool { true }
    override func accessibilitySubrole() -> NSAccessibility.Subrole? { .unknown }
}

@MainActor
final class NotchDynamicIslandController: ObservableObject {
    static let shared = NotchDynamicIslandController()

    static let canvasWidth: CGFloat = 430
    static let canvasHeight: CGFloat = 210

    @Published private(set) var isExpanded: Bool = false
    @Published private(set) var cameraCutoutWidth: CGFloat = 184
    @Published private(set) var cameraCutoutHeight: CGFloat = 32

    // Quản lý cửa sổ chính (Active Window) và các cửa sổ phụ trên đa màn hình (Mirror Panels)
    private var mainPanel: SenseNotchPanel?
    private var mirrorPanels: [CGDirectDisplayID: SenseNotchPanel] = [:]

    private var mouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var defaultsObserver: NSObjectProtocol?
    private var spaceObserver: NSObjectProtocol?
    private var appActivationObserver: NSObjectProtocol?
    private var fullscreenTimer: Timer?
    private var hoverWorkItem: DispatchWorkItem?
    private var collapseWorkItem: DispatchWorkItem?
    private var isPinnedOpen = false

    private init() {
        registerDefaultPreferences()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.syncAllDisplays()
            }
        }
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.syncVisibility()
            }
        }
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.syncFullscreenState()
            }
        }
        appActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.syncFullscreenState()
            }
        }
    }

    private func registerDefaultPreferences() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: DefaultsKey.notchStyle) == nil {
            defaults.set("notch", forKey: DefaultsKey.notchStyle)
        }
        if defaults.object(forKey: DefaultsKey.notchExpandOnHover) == nil {
            defaults.set(true, forKey: DefaultsKey.notchExpandOnHover)
        }
        if defaults.object(forKey: DefaultsKey.notchShowVisualizer) == nil {
            defaults.set(true, forKey: DefaultsKey.notchShowVisualizer)
        }
        if defaults.object(forKey: DefaultsKey.notchHideInFullscreen) == nil {
            defaults.set(false, forKey: DefaultsKey.notchHideInFullscreen)
        }
        if defaults.object(forKey: DefaultsKey.notchDisplayTarget) == nil {
            defaults.set("automatic", forKey: DefaultsKey.notchDisplayTarget)
        }
        if defaults.object(forKey: DefaultsKey.notchExpandAllDisplays) == nil {
            defaults.set(false, forKey: DefaultsKey.notchExpandAllDisplays)
        }
    }

    var targetScreenForActivePanel: NSScreen {
        let mode = UserDefaults.standard.string(forKey: DefaultsKey.notchDisplayTarget) ?? "automatic"
        return targetScreen(for: mode) ?? NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
    }

    func geometry(for screen: NSScreen? = nil) -> SenseScreenGeometry {
        let target = screen ?? targetScreenForActivePanel
        return SenseScreenGeometry(for: target)
    }

    func islandSize(for screen: NSScreen? = nil, expanded: Bool? = nil) -> CGSize {
        let geo = geometry(for: screen)
        if expanded ?? isExpanded {
            return geo.expandedSize
        }
        let isPill = UserDefaults.standard.string(forKey: DefaultsKey.notchStyle) == "pill"
        let fitWidth = UserDefaults.standard.double(forKey: DefaultsKey.notchCapsuleFitWidth)
        let fitHeight = UserDefaults.standard.double(forKey: DefaultsKey.notchCapsuleFitHeight)

        if isPill {
            return geo.compactCapsuleSize(customWidth: fitWidth, customHeight: fitHeight)
        }
        return geo.compactNotchSize(customWidth: fitWidth, customHeight: fitHeight)
    }

    var currentGeometry: SenseScreenGeometry {
        geometry()
    }

    var currentIslandSize: CGSize {
        islandSize()
    }

    /// Khởi động hệ thống Dynamic Island, lắng nghe sự kiện chuột, nhạc và màn hình.
    func start() {
        _ = NotchMusicService.shared
        setupPanelIfNeeded()
        syncFullscreenMonitoring()
        syncAllDisplays()
        startMouseTracking()
    }

    /// Đồng bộ trạng thái hiển thị của Dynamic Island theo cài đặt bật/tắt tính năng.
    func syncVisibility() {
        let enabled = SensePillar.dynamicIsland.isEnabled()
        guard enabled else {
            mainPanel?.orderOut(nil)
            closeAllMirrors()
            syncFullscreenMonitoring()
            return
        }
        setupPanelIfNeeded()
        if mouseMonitor == nil {
            startMouseTracking()
        }
        syncFullscreenMonitoring()
        syncAllDisplays()
    }

    /// Được gọi tự động ngay khi macOS vừa cấp quyền Accessibility thành công (1 phát ăn ngay)
    func permissionDidGrant() {
        restartMouseTracking()
        syncVisibility()
        repositionPanel()
    }

    /// Khởi động lại trình giám sát sự kiện chuột toàn cục
    func restartMouseTracking() {
        if let mm = mouseMonitor {
            NSEvent.removeMonitor(mm)
            mouseMonitor = nil
        }
        if let lmm = localMouseMonitor {
            NSEvent.removeMonitor(lmm)
            localMouseMonitor = nil
        }
        startMouseTracking()
    }

    /// Mở rộng Dynamic Island để hiển thị bảng điều khiển nhạc chi tiết.
    /// - Parameter pinned: `true` nếu mở bằng cách nhấp chuột (cần giữ mở cho đến khi bấm ngoài).
    func expand(Pinned pinned: Bool = false) {
        hoverWorkItem?.cancel()
        hoverWorkItem = nil
        collapseWorkItem?.cancel()
        collapseWorkItem = nil
        if pinned { isPinnedOpen = true }
        if !isExpanded {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                isExpanded = true
            }
        }
        mainPanel?.ignoresMouseEvents = false
    }

    /// Thu gọn Dynamic Island về kích thước ban đầu (ôm sát tai thỏ hoặc viên nang).
    func collapse() {
        hoverWorkItem?.cancel()
        hoverWorkItem = nil
        collapseWorkItem?.cancel()
        collapseWorkItem = nil
        isPinnedOpen = false
        if isExpanded {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                isExpanded = false
            }
        }
        let inside = isPointInsideIsland(NSEvent.mouseLocation)
        mainPanel?.ignoresMouseEvents = !inside
    }

    // MARK: - Quản lý Cửa sổ & Đa màn hình (Displays: Automatic, BuiltIn, Main, Pointer, All)

    private func setupPanelIfNeeded() {
        guard mainPanel == nil else { return }

        let activeScreen = targetScreenForActivePanel
        let rootView = NotchDynamicIslandView(controller: self, displayID: activeScreen.displayID, isMirror: false)
        let hostingView = NotchPassthroughHostingView(rootView: rootView, controller: self)
        hostingView.frame = NSRect(x: 0, y: 0, width: Self.canvasWidth, height: Self.canvasHeight)

        let window = SenseNotchPanel(
            contentRect: hostingView.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.level = SenseNotchPanel.normalLevel
        window.collectionBehavior = SenseNotchPanel.overlayCollectionBehavior
        window.contentView = hostingView
        window.ignoresMouseEvents = true
        self.mainPanel = window
    }

    func repositionPanel() {
        syncAllDisplays()
    }

    func syncAllDisplays() {
        guard SensePillar.dynamicIsland.isEnabled() else { return }
        setupPanelIfNeeded()

        let mode = UserDefaults.standard.string(forKey: DefaultsKey.notchDisplayTarget) ?? "automatic"
        let activeScreen = targetScreen(for: mode)
        let hideInFullscreen = UserDefaults.standard.bool(forKey: DefaultsKey.notchHideInFullscreen)

        if let activeScreen, let mainPanel {
            measureCameraNotch(on: activeScreen)
            let frame = NSRect(
                x: (activeScreen.frame.midX - Self.canvasWidth / 2).rounded(),
                y: (activeScreen.frame.maxY - Self.canvasHeight).rounded(),
                width: Self.canvasWidth,
                height: Self.canvasHeight
            )
            mainPanel.setFrame(frame, display: true)

            let isFs = SenseFullscreenDetector.isFullscreen(on: activeScreen)
            if hideInFullscreen && isFs {
                mainPanel.orderOut(nil)
            } else {
                mainPanel.orderFrontRegardless()
            }

            if let hostingView = mainPanel.contentView as? NotchPassthroughHostingView<NotchDynamicIslandView> {
                hostingView.rootView = NotchDynamicIslandView(controller: self, displayID: activeScreen.displayID, isMirror: false)
            }
        }

        // Nếu người dùng chọn "Tất cả màn hình" (All displays)
        if mode == "all" {
            let activeID = activeScreen?.displayID ?? 0
            let allScreens = NSScreen.screens

            // Dọn mirror của màn hình đã rút hoặc màn hình vừa trở thành activeScreen
            for (id, mirror) in mirrorPanels where id == activeID || !allScreens.contains(where: { $0.displayID == id }) {
                mirror.orderOut(nil)
                mirrorPanels[id] = nil
            }

            // Tạo hoặc cập nhật mirror trên các màn hình còn lại
            for screen in allScreens where screen.displayID != activeID {
                let id = screen.displayID
                let mirror = mirrorPanels[id] ?? createMirrorPanel(for: screen)
                mirrorPanels[id] = mirror

                let frame = NSRect(
                    x: (screen.frame.midX - Self.canvasWidth / 2).rounded(),
                    y: (screen.frame.maxY - Self.canvasHeight).rounded(),
                    width: Self.canvasWidth,
                    height: Self.canvasHeight
                )
                mirror.setFrame(frame, display: true)

                if let hostingView = mirror.contentView as? NSHostingView<NotchDynamicIslandView> {
                    hostingView.rootView = NotchDynamicIslandView(controller: self, displayID: id, isMirror: true)
                }

                let isMirrorFs = SenseFullscreenDetector.isFullscreen(on: screen)
                if hideInFullscreen && isMirrorFs {
                    mirror.orderOut(nil)
                } else {
                    mirror.orderFrontRegardless()
                }
            }
        } else {
            closeAllMirrors()
        }
    }

    // MARK: - Quản lý Ẩn khi Fullscreen

    func syncFullscreenMonitoring() {
        let enabled = SensePillar.dynamicIsland.isEnabled()
        let hideInFullscreen = UserDefaults.standard.bool(forKey: DefaultsKey.notchHideInFullscreen)
        guard enabled && hideInFullscreen else {
            fullscreenTimer?.invalidate()
            fullscreenTimer = nil
            return
        }
        guard fullscreenTimer == nil else { return }
        let timer = Timer(timeInterval: 0.6, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.syncFullscreenState()
            }
        }
        timer.tolerance = 0.2
        fullscreenTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func syncFullscreenState() {
        guard SensePillar.dynamicIsland.isEnabled() else { return }
        let hideInFullscreen = UserDefaults.standard.bool(forKey: DefaultsKey.notchHideInFullscreen)

        guard hideInFullscreen else {
            if let mainPanel, !mainPanel.isVisible {
                mainPanel.orderFrontRegardless()
            }
            for (_, mirror) in mirrorPanels where !mirror.isVisible {
                mirror.orderFrontRegardless()
            }
            return
        }

        let activeScreen = targetScreenForActivePanel
        if let mainPanel {
            let isMainFullscreen = SenseFullscreenDetector.isFullscreen(on: activeScreen)
            if isMainFullscreen && mainPanel.isVisible {
                collapse()
                mainPanel.orderOut(nil)
            } else if !isMainFullscreen && !mainPanel.isVisible {
                mainPanel.orderFrontRegardless()
            }
        }

        let mode = UserDefaults.standard.string(forKey: DefaultsKey.notchDisplayTarget) ?? "automatic"
        if mode == "all" {
            for (id, mirror) in mirrorPanels {
                let isMirrorFullscreen = SenseFullscreenDetector.isFullscreen(on: id)
                if isMirrorFullscreen && mirror.isVisible {
                    mirror.orderOut(nil)
                } else if !isMirrorFullscreen && !mirror.isVisible {
                    mirror.orderFrontRegardless()
                }
            }
        }
    }

    private func createMirrorPanel(for screen: NSScreen) -> SenseNotchPanel {
        let rootView = NotchDynamicIslandView(controller: self, displayID: screen.displayID, isMirror: true)
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = NSRect(x: 0, y: 0, width: Self.canvasWidth, height: Self.canvasHeight)

        let window = SenseNotchPanel(
            contentRect: hostingView.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.level = SenseNotchPanel.normalLevel
        window.collectionBehavior = SenseNotchPanel.overlayCollectionBehavior
        window.contentView = hostingView
        window.ignoresMouseEvents = true
        return window
    }

    private func closeAllMirrors() {
        for (_, panel) in mirrorPanels {
            panel.orderOut(nil)
        }
        mirrorPanels.removeAll()
    }

    private func targetScreen(for mode: String) -> NSScreen? {
        switch mode {
        case "builtIn":
            return NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main
        case "main":
            return NSScreen.main ?? NSScreen.screens.first
        case "pointer", "all":
            let mouseLoc = NSEvent.mouseLocation
            if let mouseScreen = NSScreen.screens.first(where: { $0.frame.contains(mouseLoc) }) {
                return mouseScreen
            }
            if let notched = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) {
                return notched
            }
            return NSScreen.main ?? NSScreen.screens.first
        default: // "automatic"
            if let notched = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) {
                return notched
            }
            return NSScreen.main ?? NSScreen.screens.first
        }
    }

    private func measureCameraNotch(on screen: NSScreen) {
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            let gap = right.minX - left.maxX
            cameraCutoutWidth = gap > 80 ? gap : 184
        } else {
            cameraCutoutWidth = 184
        }
        let safeTop = screen.safeAreaInsets.top
        cameraCutoutHeight = safeTop > 0 ? max(SenseScreenGeometry.standardNotchHeight, safeTop) : (SenseScreenGeometry.standardNotchHeight - 2.0)
    }

    // MARK: - Theo dõi chuột (Hover & Click-through & Follow Pointer)

    /// Khung bao chính xác của Island trên màn hình của mainPanel (không cộng bất kỳ phần đệm thừa nào)
    var activeScreenIslandRect: NSRect {
        guard let mainPanel else { return .zero }
        let screen = mainPanel.screen ?? targetScreenForActivePanel
        let size = islandSize(for: screen)
        let geo = geometry(for: screen)
        let isPill = (UserDefaults.standard.string(forKey: DefaultsKey.notchStyle) == "pill")
        let drop = UserDefaults.standard.double(forKey: DefaultsKey.notchCapsuleFitDrop)
        let topOffset = isPill ? (geo.capsuleVerticalCenterOffset + CGFloat(drop)) : 0
        let x = mainPanel.frame.midX - size.width / 2
        let y = mainPanel.frame.maxY - topOffset - size.height
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    /// Kiểm tra chính xác tọa độ con trỏ chuột đã thực sự chạm vào phần hình vẽ (Pixel Silhouette)
    /// của Capsule hoặc Notch hay chưa, loại bỏ hoàn toàn vùng đệm thừa xung quanh vai tai thỏ và góc bo.
    func isPointInsideIsland(_ screenPoint: NSPoint) -> Bool {
        guard let mainPanel, mainPanel.isVisible else { return false }
        let screen = mainPanel.screen ?? targetScreenForActivePanel
        let rect = activeScreenIslandRect
        guard rect.width > 0, rect.height > 0, rect.contains(screenPoint) else { return false }

        // Hệ tọa độ cục bộ từ đỉnh xuống (0,0 tại góc trên bên trái của Island)
        let localPoint = CGPoint(
            x: screenPoint.x - rect.minX,
            y: rect.maxY - screenPoint.y
        )

        let geo = geometry(for: screen)
        let isPill = (UserDefaults.standard.string(forKey: DefaultsKey.notchStyle) == "pill")

        if isPill {
            // Khi đang thu gọn, lùi vào 1.5pt để con trỏ phải thực sự chạm vào thân đen của Capsule
            let inset: CGFloat = isExpanded ? 0.0 : 1.5
            let bodyRect = CGRect(
                x: inset,
                y: inset,
                width: max(0, rect.width - inset * 2),
                height: max(0, rect.height - inset * 2)
            )
            let radius = isExpanded ? 26.0 : bodyRect.height / 2
            return isPoint(localPoint, insideRoundedRect: bodyRect, topRadius: radius, bottomRadius: radius)
        } else {
            let shoulder = isExpanded ? 14.0 : geo.shoulderRadius.shoulder
            let bottom = isExpanded ? 24.0 : geo.shoulderRadius.bottom
            // Phần vai tai thỏ (0 ..< shoulder ở hai bên) là đường cong loe ra mép trên Menu Bar.
            // Chỉ tính là chạm vào Notch khi con trỏ đi vào bên trong vách đứng thực tế của tai thỏ.
            let inset: CGFloat = isExpanded ? 0.0 : 1.5
            let minX = shoulder + inset
            let bodyWidth = max(0, rect.width - (shoulder + inset) * 2)
            let bodyHeight = max(0, rect.height - inset)
            let bodyRect = CGRect(x: minX, y: 0, width: bodyWidth, height: bodyHeight)
            let bottomRadius = max(0, bottom - inset)
            return isPoint(localPoint, insideRoundedRect: bodyRect, topRadius: 0, bottomRadius: bottomRadius)
        }
    }

    private func isPoint(
        _ p: CGPoint,
        insideRoundedRect rect: CGRect,
        topRadius: CGFloat,
        bottomRadius: CGFloat
    ) -> Bool {
        guard rect.width > 0, rect.height > 0, rect.contains(p) else { return false }

        // Kiểm tra 2 góc bo phía trên
        if topRadius > 0 && p.y < rect.minY + topRadius {
            if p.x < rect.minX + topRadius {
                if hypot(p.x - (rect.minX + topRadius), p.y - (rect.minY + topRadius)) > topRadius {
                    return false
                }
            } else if p.x > rect.maxX - topRadius {
                if hypot(p.x - (rect.maxX - topRadius), p.y - (rect.minY + topRadius)) > topRadius {
                    return false
                }
            }
        }

        // Kiểm tra 2 góc bo phía dưới
        if bottomRadius > 0 && p.y > rect.maxY - bottomRadius {
            if p.x < rect.minX + bottomRadius {
                if hypot(p.x - (rect.minX + bottomRadius), p.y - (rect.maxY - bottomRadius)) > bottomRadius {
                    return false
                }
            } else if p.x > rect.maxX - bottomRadius {
                if hypot(p.x - (rect.maxX - bottomRadius), p.y - (rect.maxY - bottomRadius)) > bottomRadius {
                    return false
                }
            }
        }

        return true
    }

    private func startMouseTracking() {
        if mouseMonitor == nil {
            mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .leftMouseDragged]) { [weak self] event in
                self?.handleMouseEvent(type: event.type)
            }
        }
        if localMouseMonitor == nil {
            localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .leftMouseDragged]) { [weak self] event in
                self?.handleMouseEvent(type: event.type)
                return event
            }
        }
    }

    private func handleMouseEvent(type: NSEvent.EventType) {
        guard SensePillar.dynamicIsland.isEnabled(), let mainPanel, mainPanel.isVisible else { return }
        let mouse = NSEvent.mouseLocation

        // Follow Pointer: Nếu bật chế độ "pointer" hoặc "all", khi con trỏ chuyển màn hình thì island chuyển theo ngay lập tức
        let mode = UserDefaults.standard.string(forKey: DefaultsKey.notchDisplayTarget) ?? "automatic"
        if (mode == "pointer" || mode == "all") && !isExpanded {
            if let mouseScreen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }),
               mouseScreen.displayID != mainPanel.screen?.displayID {
                syncAllDisplays()
            }
        }

        let inside = isPointInsideIsland(mouse)

        if mainPanel.ignoresMouseEvents == inside {
            mainPanel.ignoresMouseEvents = !inside
        }

        let expandOnHover = UserDefaults.standard.bool(forKey: DefaultsKey.notchExpandOnHover)
        if inside {
            collapseWorkItem?.cancel()
            collapseWorkItem = nil
            if expandOnHover && !isExpanded {
                scheduleHoverExpand(after: 0.06)
            }
        } else {
            hoverWorkItem?.cancel()
            hoverWorkItem = nil
            if isExpanded {
                if type == .leftMouseDown {
                    collapse()
                } else if !isPinnedOpen {
                    scheduleCollapse(after: 0.28)
                }
            }
        }
    }

    private func scheduleHoverExpand(after delay: TimeInterval) {
        guard hoverWorkItem == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.hoverWorkItem = nil
            guard SensePillar.dynamicIsland.isEnabled(),
                  !self.isExpanded,
                  UserDefaults.standard.bool(forKey: DefaultsKey.notchExpandOnHover),
                  self.isPointInsideIsland(NSEvent.mouseLocation) else {
                return
            }
            self.expand(Pinned: false)
        }
        hoverWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func scheduleCollapse(after delay: TimeInterval) {
        guard collapseWorkItem == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.collapseWorkItem = nil
            let mouse = NSEvent.mouseLocation
            if !self.isPointInsideIsland(mouse) {
                self.collapse()
            }
        }
        collapseWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (deviceDescription[key] as? NSNumber)?.uint32Value ?? 0
    }
}

private final class NotchPassthroughHostingView<Content: View>: NSHostingView<Content> {
    weak var controller: NotchDynamicIslandController?

    init(rootView: Content, controller: NotchDynamicIslandController) {
        self.controller = controller
        super.init(rootView: rootView)
    }

    @MainActor required init(rootView: Content) {
        super.init(rootView: rootView)
    }

    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let controller, let window else { return nil }
        let screenPoint = window.convertPoint(toScreen: point)
        guard controller.isPointInsideIsland(screenPoint) else {
            return nil
        }
        return super.hitTest(point)
    }
}
