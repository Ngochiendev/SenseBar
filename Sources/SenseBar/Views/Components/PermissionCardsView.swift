import AppKit
import SwiftUI

struct PermissionSectionCard: View {
    @ObservedObject var permissions = PermissionManager.shared
    @ObservedObject var l10n = L10n.shared
    var compact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PermissionRow(
                title: l10n.string(vi: "Trợ năng (Accessibility)", en: "Accessibility"),
                description: l10n.string(
                    vi: "Cần thiết để điều khiển Tai thỏ & Dynamic Island, nhận diện cửa sổ toàn màn hình và hỗ trợ phím tắt âm thanh.",
                    en: "Required for Dynamic Island interactions, fullscreen detection, and audio hotkeys."
                ),
                granted: permissions.accessibilityGranted,
                l10n: l10n,
                requestAction: { permissions.requestAccessibility() },
                openAction: { permissions.openAccessibilitySettings() }
            )
        }
        .padding(compact ? 14 : 16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        )
    }
}

struct PermissionRow: View {
    let title: String
    let description: String
    let granted: Bool
    let l10n: L10n
    let requestAction: () -> Void
    let openAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(granted ? .green : .orange)
                Text(title)
                    .font(.system(size: 13.5, weight: .medium))
                Spacer()
                Text(granted
                     ? l10n.string(vi: "Đã cấp quyền", en: "Granted")
                     : l10n.string(vi: "Cần cấp quyền", en: "Not Granted"))
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(granted ? .green : .orange)
            }

            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !granted {
                HStack(spacing: 8) {
                    Button(l10n.string(vi: "Cấp quyền ngay", en: "Request Permission"), action: requestAction)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    Button(l10n.string(vi: "Mở Cài đặt Hệ thống", en: "Open System Settings"), action: openAction)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                .padding(.top, 2)
            }
        }
    }
}

// MARK: - Thẻ nổi hướng dẫn cấp quyền (PermissionGuideOverlay)

@MainActor
final class PermissionGuideOverlay {
    static let shared = PermissionGuideOverlay()

    private var panel: NSPanel?
    private var pollTimer: Timer?
    private var dismissTimer: Timer?
    private init() {}

    func show(for kind: PermissionKind) {
        dismiss()

        let guideView = PermissionGuideCard(
            kind: kind,
            onDismiss: { [weak self] in self?.dismiss() },
            onReset: { [weak self] in
                self?.dismiss()
                PermissionManager.shared.resetPermission(kind)
            }
        )

        let hosting = NSHostingView(rootView: guideView)
        hosting.frame = NSRect(x: 0, y: 0, width: 360, height: 254)

        let panel = NSPanel(
            contentRect: hosting.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.contentView = hosting

        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            let x = visible.maxX - 376
            let y = visible.maxY - 270
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            panel.animator().alphaValue = 1
        }
        self.panel = panel

        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                PermissionManager.shared.refreshStatus()
                if PermissionManager.shared.isGranted(kind) {
                    self?.pollTimer?.invalidate()
                    self?.pollTimer = nil
                    self?.scheduleDismiss(after: 1.6)
                }
            }
        }
    }

    func dismiss() {
        pollTimer?.invalidate()
        pollTimer = nil
        dismissTimer?.invalidate()
        dismissTimer = nil
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            panel.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated {
                panel.orderOut(nil)
            }
        })
        self.panel = nil
    }

    func complete() {
        pollTimer?.invalidate()
        pollTimer = nil
        scheduleDismiss(after: 1.6)
    }

    private func scheduleDismiss(after seconds: TimeInterval) {
        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.dismiss()
            }
        }
    }
}

private struct PermissionGuideCard: View {
    let kind: PermissionKind
    let onDismiss: () -> Void
    let onReset: () -> Void

    @ObservedObject private var permissions = PermissionManager.shared
    @ObservedObject private var l10n = L10n.shared
    @State private var showResetOption = false

    private var isGranted: Bool {
        permissions.isGranted(kind)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if isGranted {
                grantedContent
            } else {
                setupContent
            }
        }
        .padding(16)
        .frame(width: 360)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(isGranted ? Color.green.opacity(0.42) : Color.blue.opacity(0.22), lineWidth: 1)
        )
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                if !isGranted {
                    withAnimation { showResetOption = true }
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: isGranted ? "checkmark" : "hand.raised.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(isGranted ? Color.green : Color.blue, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(l10n.string(vi: "Trợ năng", en: "Accessibility"))
                    .font(.system(size: 13, weight: .bold))
                Text(l10n.string(vi: "Mở khóa tương tác Dynamic Island", en: "Enable Dynamic Island interactions"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Color.primary.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(l10n.string(vi: "Đóng", en: "Close"))
        }
    }

    private var grantedContent: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 27))
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text(l10n.string(vi: "Đã sẵn sàng", en: "Ready to go"))
                    .font(.system(size: 12, weight: .semibold))
                Text(l10n.string(vi: "Quyền đã được cấp. Thẻ này sẽ tự đóng.", en: "Permission granted. This card will close automatically."))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var setupContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text(l10n.string(vi: "Đang chờ xác nhận trong Cài đặt Hệ thống", en: "Waiting for confirmation in System Settings"))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Color.blue.opacity(0.08), in: Capsule())

            VStack(alignment: .leading, spacing: 9) {
                guideStep(1, l10n.string(
                    vi: "Tìm “SenseBar” trong danh sách ứng dụng.",
                    en: "Find “SenseBar” in the app list."
                ))
                guideStep(2, l10n.string(
                    vi: "Bật công tắc bên phải để hoàn tất.",
                    en: "Turn on the switch on the right to finish."
                ))
            }
            .padding(12)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            Button {
                PermissionManager.shared.openAccessibilitySettings()
            } label: {
                Label(l10n.string(vi: "Mở Cài đặt Trợ năng", en: "Open Accessibility Settings"), systemImage: "gearshape")
                    .font(.system(size: 11.5, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)

            if showResetOption {
                Button(l10n.string(vi: "Không thấy SenseBar? Làm mới yêu cầu", en: "Can't find SenseBar? Refresh request"), action: onReset)
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func guideStep(_ index: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(index)")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.blue))
            Text(text)
                .font(.system(size: 11.5))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
