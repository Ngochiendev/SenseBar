import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItemController: StatusItemController?
    private var welcomeWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        BrandIconResources.applyApplicationIcon()
        NotchDynamicIslandController.shared.start()

        statusItemController = StatusItemController(
            onOpenWelcome: { [weak self] in
                self?.showWelcomeWindow(resetToFirstStep: true)
            }
        )

        let forceWelcome = CommandLine.arguments.contains("--welcome")
        let forceSettings = CommandLine.arguments.contains("--settings")
        let forcePermissions = CommandLine.arguments.contains("--permissions")
        let forcePopover = CommandLine.arguments.contains("--popover")
        let hasOnboarded = UserDefaults.standard.bool(forKey: DefaultsKey.hasOnboarded)

        if forceWelcome || !hasOnboarded {
            showWelcomeWindow(resetToFirstStep: forceWelcome)
        } else if forceSettings || forcePermissions || forcePopover {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.statusItemController?.showPopover()
            }
        }
    }

    // MARK: - Cửa sổ Chào mừng (Welcome / Onboarding)

    func showWelcomeWindow(resetToFirstStep: Bool) {
        if resetToFirstStep {
            UserDefaults.standard.set(0, forKey: DefaultsKey.onboardingStep)
        }

        if let existing = welcomeWindow {
            NSApp.setActivationPolicy(.regular)
            BrandIconResources.applyApplicationIcon()
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let rootView = WelcomeOnboardingView { [weak self] in
            self?.finishOnboardingAndOpenPopover()
        }
        let hostingController = NSHostingController(rootView: rootView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = AppInfo.name
        window.titleVisibility = .hidden
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setContentSize(NSSize(width: 560, height: 640))
        window.center()

        welcomeWindow = window

        NSApp.setActivationPolicy(.regular)
        BrandIconResources.applyApplicationIcon()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func finishOnboardingAndOpenPopover() {
        welcomeWindow?.close()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.statusItemController?.showPopover()
        }
    }

    // MARK: - Quản lý Dock Icon khi đóng cửa sổ

    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let welcomeVisible = self.welcomeWindow?.isVisible == true
            if !welcomeVisible {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}
