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
        let hasOnboarded = UserDefaults.standard.bool(forKey: DefaultsKey.hasOnboarded)

        if forceWelcome || !hasOnboarded {
            showWelcomeWindow(resetToFirstStep: forceWelcome)
        } else {
            // Khi người dùng bấm mở app (hoặc ấn "Mở" từ Gatekeeper), tự động hiển thị Popover
            // trên Menu Bar để người dùng thấy ngay ứng dụng đã mở thành công
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.statusItemController?.showPopover()
            }
        }

        // Kiểm tra xem ứng dụng có đang chạy trực tiếp từ đĩa ảo DMG hay không
        checkAndPromptMoveToApplicationsIfNeeded()
    }

    // MARK: - Xử lý khi người dùng bấm lại vào App trong Applications / Spotlight / Launchpad

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        let hasOnboarded = UserDefaults.standard.bool(forKey: DefaultsKey.hasOnboarded)
        if !hasOnboarded {
            showWelcomeWindow(resetToFirstStep: false)
        } else {
            statusItemController?.showPopover()
        }
        return true
    }

    // MARK: - Kiểm tra chạy từ DMG và hỗ trợ chuyển vào Applications

    private func checkAndPromptMoveToApplicationsIfNeeded() {
        let bundlePath = Bundle.main.bundlePath
        let inApps = bundlePath.hasPrefix("/Applications") || bundlePath.hasPrefix("/Users/\(NSUserName())/Applications")
        if inApps { return }

        let isDiskImage = bundlePath.hasPrefix("/Volumes/") || bundlePath.contains("/AppTranslocation/")
        guard isDiskImage else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            let alert = NSAlert()
            alert.messageText = "Cài đặt SenseBar vào thư mục Applications"
            alert.informativeText = "SenseBar đang chạy trực tiếp từ đĩa cài đặt DMG. Bạn nên chuyển ứng dụng vào thư mục Applications để dùng lâu dài và không bị mất khi tháo ổ đĩa."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Chuyển vào Applications")
            alert.addButton(withTitle: "Để sau")

            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn {
                self.moveToApplicationsAndRelaunch()
            }
        }
    }

    private func moveToApplicationsAndRelaunch() {
        let sourceURL = Bundle.main.bundleURL
        let targetURL = URL(fileURLWithPath: "/Applications/SenseBar.app")
        let fm = FileManager.default

        do {
            if fm.fileExists(atPath: targetURL.path) {
                _ = try fm.removeItem(at: targetURL)
            }
            try fm.copyItem(at: sourceURL, to: targetURL)

            // Gỡ thuộc tính quarantine
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
            proc.arguments = ["-cr", targetURL.path]
            try? proc.run()
            proc.waitUntilExit()

            // Khởi chạy bản mới trong Applications và đóng bản cũ
            NSWorkspace.shared.open(targetURL)
            NSApp.terminate(nil)
        } catch {
            // Nếu không có quyền ghi trực tiếp, mở thư mục Applications cho người dùng kéo thả
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: "/Applications")
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
