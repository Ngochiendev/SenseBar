import AppKit
import SwiftUI

@MainActor
final class StatusItemController: NSObject {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private let onOpenWelcome: () -> Void
    private let onOpenSettings: (SettingsTab) -> Void

    init(
        onOpenWelcome: @escaping () -> Void,
        onOpenSettings: @escaping (SettingsTab) -> Void
    ) {
        self.onOpenWelcome = onOpenWelcome
        self.onOpenSettings = onOpenSettings
        super.init()
        setupPopover()
        setupStatusItem()
    }

    private func setupPopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.hasFullSizeContent = PanelSurface.popoverHostsFullSizeContent

        let panelView = MenuPanelView(
            onOpenSettings: { [weak self] in
                self?.closePopover()
                self?.onOpenSettings(.general)
            },
            onOpenPermissions: { [weak self] in
                self?.closePopover()
                self?.onOpenSettings(.permissions)
            },
            onQuit: {
                NSApplication.shared.terminate(nil)
            }
        )
        let host = NSHostingController(rootView: panelView)
        host.view.wantsLayer = true
        host.view.layer?.backgroundColor = NSColor.clear.cgColor
        if #available(macOS 13.0, *) {
            host.sizingOptions = .preferredContentSize
        }
        popover.contentViewController = host
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
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func closePopover() {
        if popover.isShown {
            popover.performClose(nil)
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

        let welcomeItem = NSMenuItem(
            title: s.menuShowWelcome,
            action: #selector(openWelcomeAction),
            keyEquivalent: ""
        )
        welcomeItem.target = self
        menu.addItem(welcomeItem)

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
        onOpenSettings(.general)
    }

    @objc private func openWelcomeAction() {
        onOpenWelcome()
    }

    @objc private func openAboutAction() {
        onOpenSettings(.about)
    }

    @objc private func quitAction() {
        NSApplication.shared.terminate(nil)
    }
}
