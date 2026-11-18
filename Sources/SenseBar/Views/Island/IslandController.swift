import AppKit
import SwiftUI
import QuartzCore

// MARK: - NotchPanel tùy chỉnh (Luôn giữ active appearance cho Liquid Glass & hỗ trợ đa màn hình)

final class IslandPanel: NSPanel {
    static let overlayCollectionBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle
    ]
    static let normalLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
    private(set) var wantsVisible = false
    private var visibilityRevision = 0

    func setVisible(_ visible: Bool, animated: Bool = true, onHidden: (@MainActor () -> Void)? = nil) {
        guard wantsVisible != visible || (!animated && isVisible != visible) else { return }
        wantsVisible = visible
        visibilityRevision += 1
        let revision = visibilityRevision
        if visible && !isVisible {
            alphaValue = 0
            orderFrontRegardless()
        }
        if !visible { ignoresMouseEvents = true }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                ? (visible ? 0.28 : 0.22) : 0
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animator().alphaValue = visible ? 1 : 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.visibilityRevision == revision, !self.wantsVisible else { return }
                self.orderOut(nil)
                onHidden?()
            }
        }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    @objc func _hasActiveAppearanceIgnoringKeyFocus() -> Bool { true }
    override func accessibilitySubrole() -> NSAccessibility.Subrole? { .unknown }
}

@MainActor
final class IslandController: ObservableObject {
    static let shared = IslandController()

    static let canvasWidth: CGFloat = 430
    static let canvasHeight: CGFloat = 210

    @Published private(set) var isExpanded: Bool = false
    @Published private(set) var cameraCutoutWidth: CGFloat = 184
    @Published private(set) var cameraCutoutHeight: CGFloat = 32
    /// `true` khi có ít nhất một màn hình không tai thỏ có thể hiển thị Island.
    @Published private(set) var canChooseStyle: Bool = false
    /// `true` khi đang có màn hình tai thỏ vật lý được kết nối (vd. MacBook).
    @Published private(set) var hasNotchedDisplay: Bool = false

    // Quản lý cửa sổ chính (Active Window) và các cửa sổ phụ trên đa màn hình (Mirror Panels)
    private var mainPanel: IslandPanel?
    private var mirrorPanels: [CGDirectDisplayID: IslandPanel] = [:]

    var hasVisibleNoticeSurface: Bool {
        if let mainPanel, mainPanel.wantsVisible, mainPanel.isVisible { return true }
        return mirrorPanels.values.contains { $0.wantsVisible && $0.isVisible }
    }

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
        refreshStyleAvailability()
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
            DispatchQueue.main.async {
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
        defaults.register(defaults: [
            DefaultsKey.notchStyle: "notch",
            DefaultsKey.notchExpandOnHover: true,
            DefaultsKey.notchShowVisualizer: true,
            DefaultsKey.notchHideInFullscreen: true,
            DefaultsKey.notchDisplayTarget: "all",
            DefaultsKey.notchExpandAllDisplays: false,
            DefaultsKey.notchDeviceNotices: true,
            DefaultsKey.notchLowPeripheralBattery: true,
            DefaultsKey.pillarDynamicIslandEnabled: true,
            DefaultsKey.pillarAudioStudioEnabled: true,
            DefaultsKey.liquidGlassEnabled: true,
            DefaultsKey.liquidGlassIslandEnabled: true,
            DefaultsKey.petEnabled: true,
            DefaultsKey.petStyle: "minimal",
            DefaultsKey.petShape: "ball",
            DefaultsKey.petPalette: "pearl",
            DefaultsKey.petSide: "left",
            DefaultsKey.petVisits: true,
            DefaultsKey.petVisitFrequency: "normal"
        ])
    }

    var targetScreenForActivePanel: NSScreen {
        let mode = UserDefaults.standard.string(forKey: DefaultsKey.notchDisplayTarget) ?? "all"
        return targetScreen(for: mode) ?? NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
    }

    func geometry(for screen: NSScreen? = nil) -> ScreenGeometry {
        let target = screen ?? targetScreenForActivePanel
        return ScreenGeometry(for: target)
    }

    func islandSize(for screen: NSScreen? = nil, expanded: Bool? = nil) -> CGSize {
        let geo = geometry(for: screen)
        if expanded ?? isExpanded {
            return geo.expandedSize
        }
        if DeviceNoticeService.shared.current != nil {
            return CGSize(width: geo.isNotched ? min(Self.canvasWidth, max(320, geo.cameraWidth + 150)) : 296,
                          height: geo.isNotched ? geo.cameraHeight + 34 : usesCapsule(on: screen) ? 48 : 50)
        }
        let fitWidth = UserDefaults.standard.double(forKey: DefaultsKey.notchCapsuleFitWidth)
        let fitHeight = UserDefaults.standard.double(forKey: DefaultsKey.notchCapsuleFitHeight)
        let isPlaying = MusicService.shared.hasMediaPresentation
        let hasPet = PetService.shared.isEnabled

        if usesCapsule(on: screen) {
            return geo.compactCapsuleSize(
                customWidth: fitWidth,
                customHeight: fitHeight
            )
        }
        return geo.compactNotchSize(
            isPlaying: isPlaying,
            hasPet: hasPet,
            customWidth: fitWidth,
            customHeight: fitHeight
        )
    }

    // MARK: - Kiểu dáng theo phần cứng

    /// Capsule chỉ áp dụng cho màn hình không có tai thỏ.
    /// Màn hình có tai thỏ vật lý luôn dùng Notch để không vẽ đè lên camera.
    func usesCapsule(on screen: NSScreen? = nil) -> Bool {
        let prefersCapsule = UserDefaults.standard.string(forKey: DefaultsKey.notchStyle) == "pill"
        return prefersCapsule && !geometry(for: screen).isNotched
    }

    /// Chỉ hiện bộ chọn Capsule / Notch khi Island có thể xuất hiện trên màn hình không tai thỏ.
    private func refreshStyleAvailability() {
        let mode = UserDefaults.standard.string(forKey: DefaultsKey.notchDisplayTarget) ?? "all"
        let candidates: [NSScreen] = (mode == "pointer" || mode == "all")
            ? NSScreen.screens
            : [targetScreen(for: mode)].compactMap { $0 }
        let available = candidates.contains { !ScreenGeometry(for: $0).isNotched }
        if canChooseStyle != available {
            canChooseStyle = available
        }
        let notched = NSScreen.screens.contains { ScreenGeometry(for: $0).isNotched }
        if hasNotchedDisplay != notched {
            hasNotchedDisplay = notched
        }
    }

    /// Khởi động hệ thống Dynamic Island, lắng nghe sự kiện chuột, nhạc và màn hình.
    func start() {
        guard SensePillar.dynamicIsland.isEnabled() else { return }
        _ = MusicService.shared
        setupPanelIfNeeded()
        syncFullscreenMonitoring()
        syncAllDisplays()
        startMouseTracking()
    }

    /// Đồng bộ trạng thái hiển thị của Dynamic Island theo cài đặt bật/tắt tính năng.
    func syncVisibility() {
        let enabled = SensePillar.dynamicIsland.isEnabled()
        guard enabled else {
            if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor); self.mouseMonitor = nil }
            if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor); self.localMouseMonitor = nil }
            hoverWorkItem?.cancel()
            collapseWorkItem?.cancel()
            mainPanel?.setVisible(false, animated: false)
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

    /// Được gọi khi macOS cấp quyền Accessibility.
    func permissionDidGrant() {
        MusicService.shared.refreshNowPlaying()
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
        if !isExpanded { MusicService.shared.refreshNowPlaying() }
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
        guard SensePillar.dynamicIsland.isEnabled() else { return }
        guard mainPanel == nil else { return }

        let activeScreen = targetScreenForActivePanel
        let rootView = IslandView(controller: self, displayID: activeScreen.displayID, isMirror: false)
        let hostingView = IslandHostingView(rootView: rootView, controller: self)
        hostingView.frame = NSRect(x: 0, y: 0, width: Self.canvasWidth, height: Self.canvasHeight)

        let window = IslandPanel(
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
        window.level = IslandPanel.normalLevel
        window.collectionBehavior = IslandPanel.overlayCollectionBehavior
        window.contentView = hostingView
        window.ignoresMouseEvents = true
        self.mainPanel = window
    }

    func repositionPanel() {
        syncAllDisplays()
    }

    func syncAllDisplays() {
        refreshStyleAvailability()
        guard SensePillar.dynamicIsland.isEnabled() else { return }
        setupPanelIfNeeded()

        let mode = UserDefaults.standard.string(forKey: DefaultsKey.notchDisplayTarget) ?? "all"
        let activeScreen = targetScreen(for: mode)
        let hideInFullscreen = UserDefaults.standard.bool(forKey: DefaultsKey.notchHideInFullscreen)

        // Keep each display's window alive when the pointer changes displays.
        if mode == "all", let activeScreen, let previous = mainPanel,
           let previousScreen = previous.screen,
           previousScreen.displayID != activeScreen.displayID,
           let next = mirrorPanels.removeValue(forKey: activeScreen.displayID) {
            previous.ignoresMouseEvents = true
            mirrorPanels[previousScreen.displayID] = previous
            mainPanel = next
            hoverWorkItem?.cancel()
            hoverWorkItem = nil
        }

        if let activeScreen, let mainPanel {
            measureCameraNotch(on: activeScreen)
            let frame = NSRect(
                x: (activeScreen.frame.midX - Self.canvasWidth / 2).rounded(),
                y: (activeScreen.frame.maxY - Self.canvasHeight).rounded(),
                width: Self.canvasWidth,
                height: Self.canvasHeight
            )
            if mainPanel.frame != frame { mainPanel.setFrame(frame, display: true) }

            let isFs = hideInFullscreen && FullscreenDetector.isFullscreen(on: activeScreen)
            if let hostingView = mainPanel.contentView as? IslandHostingView<IslandView> {
                hostingView.rootView = IslandView(controller: self, displayID: activeScreen.displayID, isMirror: false)
            }
            setPanelVisible(mainPanel, !(hideInFullscreen && isFs))
        }

        // Nếu người dùng chọn "Tất cả màn hình" (All displays)
        if mode == "all" {
            let activeID = activeScreen?.displayID ?? 0
            let allScreens = NSScreen.screens

            // Dọn mirror của màn hình đã rút hoặc màn hình vừa trở thành activeScreen
            for (id, mirror) in mirrorPanels where id == activeID || !allScreens.contains(where: { $0.displayID == id }) {
                mirror.setVisible(false, animated: false)
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
                if mirror.frame != frame { mirror.setFrame(frame, display: true) }

                if let hostingView = mirror.contentView as? NSHostingView<IslandView> {
                    hostingView.rootView = IslandView(controller: self, displayID: id, isMirror: true)
                }

                let isMirrorFs = hideInFullscreen && FullscreenDetector.isFullscreen(on: screen)
                setPanelVisible(mirror, !(hideInFullscreen && isMirrorFs))
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
        let timer = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.syncFullscreenState()
            }
        }
        timer.tolerance = 0.08
        fullscreenTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func syncFullscreenState() {
        guard SensePillar.dynamicIsland.isEnabled() else { return }
        let hideInFullscreen = UserDefaults.standard.bool(forKey: DefaultsKey.notchHideInFullscreen)

        guard hideInFullscreen else {
            if let mainPanel {
                setPanelVisible(mainPanel, true)
            }
            for (_, mirror) in mirrorPanels {
                setPanelVisible(mirror, true)
            }
            return
        }

        let activeScreen = targetScreenForActivePanel
        if let mainPanel {
            let isMainFullscreen = FullscreenDetector.isFullscreen(on: activeScreen)
            setPanelVisible(mainPanel, !isMainFullscreen)
        }

        let mode = UserDefaults.standard.string(forKey: DefaultsKey.notchDisplayTarget) ?? "all"
        if mode == "all" {
            for (id, mirror) in mirrorPanels {
                let isMirrorFullscreen = FullscreenDetector.isFullscreen(on: id)
                setPanelVisible(mirror, !isMirrorFullscreen)
            }
        }
    }

    private func setPanelVisible(_ panel: IslandPanel, _ visible: Bool) {
        if panel === mainPanel && !visible && panel.wantsVisible {
            hoverWorkItem?.cancel()
            hoverWorkItem = nil
            collapseWorkItem?.cancel()
            collapseWorkItem = nil
            isPinnedOpen = false
        }
        panel.setVisible(visible) { [weak self, weak panel] in
            guard let self, let panel, panel === self.mainPanel else { return }
            // Reset expansion only after fading out, so the two animations do not compete.
            self.collapse()
        }
    }

    private func createMirrorPanel(for screen: NSScreen) -> IslandPanel {
        let rootView = IslandView(controller: self, displayID: screen.displayID, isMirror: true)
        let hostingView = IslandHostingView(rootView: rootView, controller: self)
        hostingView.frame = NSRect(x: 0, y: 0, width: Self.canvasWidth, height: Self.canvasHeight)

        let window = IslandPanel(
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
        window.level = IslandPanel.normalLevel
        window.collectionBehavior = IslandPanel.overlayCollectionBehavior
        window.contentView = hostingView
        window.ignoresMouseEvents = true
        return window
    }

    private func closeAllMirrors() {
        for (_, panel) in mirrorPanels {
            panel.setVisible(false, animated: false)
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
            return NSScreen.main ?? NSScreen.screens.first
        default: // "automatic"
            // Tự động: Ưu tiên màn hình đang có con trỏ chuột thao tác, hoặc màn hình chính (Main Screen)
            let mouseLoc = NSEvent.mouseLocation
            if let mouseScreen = NSScreen.screens.first(where: { $0.frame.contains(mouseLoc) }) {
                return mouseScreen
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
        cameraCutoutHeight = safeTop > 0 ? max(ScreenGeometry.standardNotchHeight, safeTop) : (ScreenGeometry.standardNotchHeight - 2.0)
    }

    // MARK: - Theo dõi chuột (Hover & Click-through & Follow Pointer)

    /// Khung bao chính xác của Island trên màn hình của mainPanel (không cộng bất kỳ phần đệm thừa nào)
    var activeScreenIslandRect: NSRect {
        guard let mainPanel else { return .zero }
        let screen = mainPanel.screen ?? targetScreenForActivePanel
        let size = islandSize(for: screen)
        let geo = geometry(for: screen)
        let drop = UserDefaults.standard.double(forKey: DefaultsKey.notchCapsuleFitDrop)
        let topOffset = usesCapsule(on: screen) ? (geo.capsuleVerticalCenterOffset + CGFloat(drop)) : 0
        let x = mainPanel.frame.midX - size.width / 2
        let y = mainPanel.frame.maxY - topOffset - size.height
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    /// Kiểm tra chính xác tọa độ con trỏ chuột đã thực sự chạm vào phần hình vẽ (Pixel Silhouette)
    /// của Capsule hoặc Notch hay chưa, loại bỏ hoàn toàn vùng đệm thừa xung quanh vai tai thỏ và góc bo.
    func isPointInsideIsland(_ screenPoint: NSPoint) -> Bool {
        guard let mainPanel, mainPanel.wantsVisible, mainPanel.isVisible else { return false }
        let screen = mainPanel.screen ?? targetScreenForActivePanel
        let rect = activeScreenIslandRect
        guard rect.width > 0, rect.height > 0, rect.contains(screenPoint) else { return false }

        // Hệ tọa độ cục bộ từ đỉnh xuống (0,0 tại góc trên bên trái của Island)
        let localPoint = CGPoint(
            x: screenPoint.x - rect.minX,
            y: rect.maxY - screenPoint.y
        )

        let geo = geometry(for: screen)
        if usesCapsule(on: screen) {
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
        guard SensePillar.dynamicIsland.isEnabled() else { return }
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
        guard SensePillar.dynamicIsland.isEnabled(), let mainPanel, mainPanel.wantsVisible, mainPanel.isVisible else { return }
        let mouse = NSEvent.mouseLocation
        let currentScreen = mainPanel.screen ?? targetScreenForActivePanel

        // Tối ưu Fast Path: Island nằm sát cạnh trên màn hình. Nếu chuột ở phía dưới xa (> 65pt) và đang thu gọn,
        // bỏ qua toàn bộ phép tính hình học phức tạp để tiết kiệm triệt để CPU khi người dùng rê chuột làm việc.
        let nearTopThreshold: CGFloat = isExpanded ? 200 : 65
        let isNearTop = mouse.y >= (currentScreen.frame.maxY - nearTopThreshold)

        if !isNearTop && !isExpanded {
            if !mainPanel.ignoresMouseEvents {
                mainPanel.ignoresMouseEvents = true
            }
            // Chỉ tra cứu màn hình nếu con trỏ chuột đã vượt khỏi biên màn hình hiện tại
            let mode = UserDefaults.standard.string(forKey: DefaultsKey.notchDisplayTarget) ?? "all"
            if (mode == "pointer" || mode == "all" || mode == "automatic") && !currentScreen.frame.contains(mouse) {
                if let mouseScreen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }),
                   mouseScreen.displayID != currentScreen.displayID {
                    syncAllDisplays()
                }
            }
            return
        }

        // Khi con trỏ chuyển màn hình thì island chuyển theo ngay lập tức
        let mode = UserDefaults.standard.string(forKey: DefaultsKey.notchDisplayTarget) ?? "all"
        if (mode == "pointer" || mode == "all" || mode == "automatic") && !isExpanded {
            if !currentScreen.frame.contains(mouse),
               let mouseScreen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }),
               mouseScreen.displayID != currentScreen.displayID {
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
            if type == .leftMouseDown && DeviceNoticeService.shared.current == nil {
                expand(Pinned: true)
            }
            if expandOnHover && !isExpanded && DeviceNoticeService.shared.current == nil {
                scheduleHoverExpand(after: 0.08)
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
                  DeviceNoticeService.shared.current == nil,
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

private final class IslandHostingView<Content: View>: NSHostingView<Content> {
    weak var controller: IslandController?

    init(rootView: Content, controller: IslandController) {
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
