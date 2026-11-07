import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItemController: StatusItemController?
    private var welcomeWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // (AppIcon.icns)
        BrandIconResources.applyApplicationIcon()

        // Khởi tạo biểu tượng Sense Star trên thanh Menu Bar
        statusItemController = StatusItemController { [weak self] in
            self?.showWelcomeWindow(resetToFirstStep: false)
        }

        // Mở màn hình Onboarding khi chưa hoàn tất hoặc khi có cờ --welcome
        let forceWelcome = CommandLine.arguments.contains("--welcome")
        let hasOnboarded = UserDefaults.standard.bool(forKey: DefaultsKey.hasOnboarded)
        if forceWelcome || !hasOnboarded {
            showWelcomeWindow(resetToFirstStep: forceWelcome)
        }
    }

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
            self?.closeWelcomeWindow()
        }
        let hostingController = NSHostingController(rootView: rootView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = AppInfo.brandSignature
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

    private func closeWelcomeWindow() {
        welcomeWindow?.close()
    }

    func windowWillClose(_ notification: Notification) {
        if let closedWindow = notification.object as? NSWindow, closedWindow === welcomeWindow {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
