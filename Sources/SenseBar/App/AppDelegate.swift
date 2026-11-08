import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItemController: StatusItemController?
    private var welcomeWindow: NSWindow?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 1. Gán biểu tượng ứng dụng chính thức (AppIcon.icns)
        BrandIconResources.applyApplicationIcon()

        // 2. Khởi động Dynamic Island Controller & StatusItemController trên thanh Menu Bar
        NotchDynamicIslandController.shared.start()

        statusItemController = StatusItemController(
            onOpenWelcome: { [weak self] in
                self?.showWelcomeWindow(resetToFirstStep: true)
            },
            onOpenSettings: { [weak self] tab in
                self?.showSettingsWindow(tab: tab)
            }
        )

        // 3. Kiểm tra tham số dòng lệnh hoặc trạng thái Onboarding lần đầu
        let forceWelcome = CommandLine.arguments.contains("--welcome")
        let forceSettings = CommandLine.arguments.contains("--settings")
        let forcePermissions = CommandLine.arguments.contains("--permissions")
        let forcePopover = CommandLine.arguments.contains("--popover")
        let hasOnboarded = UserDefaults.standard.bool(forKey: DefaultsKey.hasOnboarded)

        if forcePermissions {
            showSettingsWindow(tab: .permissions)
        } else if forceSettings {
            showSettingsWindow(tab: .general)
        } else if forceWelcome || !hasOnboarded {
            showWelcomeWindow(resetToFirstStep: forceWelcome)
        } else if forcePopover {
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

    // MARK: - Cửa sổ Cài đặt (Settings Window)

    func showSettingsWindow(tab: SettingsTab = .general) {
        UserDefaults.standard.set(tab.rawValue, forKey: DefaultsKey.selectedSettingsTab)

        if let existing = settingsWindow {
            NSApp.setActivationPolicy(.regular)
            BrandIconResources.applyApplicationIcon()
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let rootView = SettingsWindowView { [weak self] in
            self?.settingsWindow?.close()
            self?.showWelcomeWindow(resetToFirstStep: true)
        }
        let hostingController = NSHostingController(rootView: rootView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = L10n.shared.s.settingsWindowTitle
        window.titleVisibility = .hidden
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setContentSize(NSSize(width: 640, height: 480))
        window.center()

        settingsWindow = window

        NSApp.setActivationPolicy(.regular)
        BrandIconResources.applyApplicationIcon()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Quản lý Dock Icon khi đóng cửa sổ

    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let welcomeVisible = self.welcomeWindow?.isVisible == true
            let settingsVisible = self.settingsWindow?.isVisible == true
            if !welcomeVisible && !settingsVisible {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}
