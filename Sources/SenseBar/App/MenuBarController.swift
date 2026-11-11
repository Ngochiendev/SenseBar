import AppKit
import SwiftUI

@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()

    override init() {
        super.init()
        setupPopover()
        setupStatusItem()
    }

    private func setupPopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.hasFullSizeContent = PanelSurface.popoverHostsFullSizeContent
        popover.delegate = self
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "SenseBarStatusItem"

        if let button = item.button {
            button.image = BrandIconResources.menuBarTemplateImage()
            button.imagePosition = .imageOnly
            button.toolTip = L10n.shared.s.menuBarTooltip
            button.target = self
            button.action = #selector(handleStatusBarClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        statusItem = item
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

    @objc private func quitAction() {
        NSApplication.shared.terminate(nil)
    }
}
