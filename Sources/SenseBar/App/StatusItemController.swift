import AppKit

final class StatusItemController: NSObject {
    private var statusItem: NSStatusItem?
    private let onOpenWelcome: () -> Void

    init(onOpenWelcome: @escaping () -> Void) {
        self.onOpenWelcome = onOpenWelcome
        super.init()
        setupStatusItem()
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
            showMenu()
        } else {
            onOpenWelcome()
        }
    }

    private func showMenu() {
        guard let statusItem else { return }
        let s = L10n.shared.s
        let menu = NSMenu()

        let welcomeItem = NSMenuItem(
            title: s.menuShowWelcome,
            action: #selector(openWelcomeAction),
            keyEquivalent: ""
        )
        welcomeItem.target = self
        menu.addItem(welcomeItem)

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

    @objc private func openWelcomeAction() {
        onOpenWelcome()
    }

    @objc private func quitAction() {
        NSApplication.shared.terminate(nil)
    }
}

