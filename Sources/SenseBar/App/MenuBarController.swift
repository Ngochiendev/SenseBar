import AppKit
import Combine
import SwiftUI

@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate {
    private var statusItem: NSStatusItem?
    private var badgeDotView: NSView?
    private var statusCancellable: AnyCancellable?
    private let popover = NSPopover()

    override init() {
        super.init()
        setupPopover()
        setupStatusItem()
        observeUpdateStatus()
    }

    private func setupPopover() {
        popover.behavior = .transient
        popover.animates = true
        // Extend the background into the arrow; controls retain their safe area.
        popover.hasFullSizeContent = true
        popover.delegate = self
    }

    private func setupStatusItem() {
        let autosaveName = "SenseBarStatusItem"
        let preferredPositionKey = "NSStatusItem Preferred Position \(autosaveName)"
        let defaults = UserDefaults.standard
        // AppKit's undocumented autosave preference places zero near the right edge.
        // Seed it before creation, while preserving any position the user has saved.
        if defaults.object(forKey: preferredPositionKey) == nil {
            defaults.set(0, forKey: preferredPositionKey)
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = autosaveName

        if let button = item.button {
            button.image = BrandIconResources.menuBarTemplateImage()
            button.imagePosition = .imageOnly
            button.toolTip = L10n.shared.s.menuBarTooltip
            button.target = self
            button.action = #selector(handleStatusBarClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])

            let dot = MenuBarUpdateBadgeView()
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.isHidden = true
            button.addSubview(dot)
            NSLayoutConstraint.activate([
                dot.widthAnchor.constraint(equalToConstant: 7),
                dot.heightAnchor.constraint(equalToConstant: 7),
                dot.topAnchor.constraint(equalTo: button.topAnchor, constant: 2.5),
                dot.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -3.5)
            ])
            badgeDotView = dot
        }

        statusItem = item
        syncUpdateBadge(status: UpdateService.shared.status)
    }

    private func observeUpdateStatus() {
        statusCancellable = UpdateService.shared.$status
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                self?.syncUpdateBadge(status: status)
            }
    }

    func resetStatusItemPosition() {
        closePopover()
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
        badgeDotView = nil
        UserDefaults.standard.set(0, forKey: "NSStatusItem Preferred Position SenseBarStatusItem")
        setupStatusItem()
    }

    private func syncUpdateBadge(status: UpdateService.Status) {
        let release: UpdateService.ReleaseInfo?
        if case .updateAvailable(let info) = status {
            release = info
        } else {
            release = nil
        }

        badgeDotView?.isHidden = (release == nil)
        if let button = statusItem?.button {
            if let release {
                button.toolTip = L10n.shared.string(
                    vi: "SenseBar — Có bản cập nhật v\(release.version)",
                    en: "SenseBar — Update v\(release.version) available"
                )
            } else {
                button.toolTip = L10n.shared.s.menuBarTooltip
            }
        }
    }

    @objc private func handleStatusBarClick(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    func togglePopover() {
        if popover.isShown {
            closePopover()
        } else {
            showPopover()
        }
    }

    func showPopover() {
        guard let button = statusItem?.button else { return }
        if popover.contentViewController == nil {
            let panelView = MenuPanelView(
                onQuit: {
                    NSApplication.shared.terminate(nil)
                }
            )
            let host = NSHostingController(rootView: panelView)
            host.sizingOptions = .preferredContentSize
            popover.contentViewController = host
        }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        UpdateService.shared.probeForUpdateIfNeeded()
    }

    func closePopover() {
        if popover.isShown {
            popover.performClose(nil)
        }
    }

    // MARK: - NSPopoverDelegate

    nonisolated func popoverDidClose(_ notification: Notification) {
        Task { @MainActor in
            self.popover.contentViewController = nil
        }
    }

    private func showContextMenu() {
        guard let statusItem else { return }
        closePopover()

        let s = L10n.shared.s
        let menu = NSMenu()

        if let release = UpdateService.shared.availableRelease {
            let updateItem = NSMenuItem(
                title: L10n.shared.string(
                    vi: "Cập nhật lên v\(release.version)...",
                    en: "Update to v\(release.version)..."
                ),
                action: #selector(installUpdateAction),
                keyEquivalent: ""
            )
            updateItem.target = self
            menu.addItem(updateItem)
            menu.addItem(.separator())
        }

        let panelItem = NSMenuItem(
            title: s.menuOpenPanel,
            action: #selector(openPanelAction),
            keyEquivalent: ""
        )
        panelItem.target = self
        menu.addItem(panelItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: s.menuSettings,
            action: #selector(openSettingsAction),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        let aboutItem = NSMenuItem(
            title: s.menuAbout,
            action: #selector(openAboutAction),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: s.menuQuit,
            action: #selector(quitAction),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openPanelAction() {
        showPopover()
    }

    @objc private func openSettingsAction() {
        showPopover()
    }

    @objc private func openAboutAction() {
        showPopover()
    }

    @objc private func installUpdateAction() {
        UpdateService.shared.openDownloadPage()
    }

    @objc private func quitAction() {
        NSApplication.shared.terminate(nil)
    }
}

/// Chấm tròn thông báo có bản cập nhật mới gắn ở góc trên-phải của biểu tượng Menu Bar.
private final class MenuBarUpdateBadgeView: NSView {
    override var allowsVibrancy: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let dotRect = bounds.insetBy(dx: 0.75, dy: 0.75)
        let path = NSBezierPath(ovalIn: dotRect)
        NSColor.systemBlue.setFill()
        path.fill()
    }
}
