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
        hosting.frame = NSRect(x: 0, y: 0, width: 340, height: 210)

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
            let x = visible.maxX - 356
            let y = visible.maxY - 226
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
            PermissionManager.shared.refreshStatus()
            if PermissionManager.shared.isGranted(kind) {
                self?.pollTimer?.invalidate()
                self?.pollTimer = nil
                self?.scheduleDismiss(after: 1.4)
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
            panel.orderOut(nil)
        })
        self.panel = nil
    }

    private func scheduleDismiss(after seconds: TimeInterval) {
        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            self?.dismiss()
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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: isGranted ? "checkmark.circle.fill" : "hand.Draw.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isGranted ? .green : .blue)
                Text(l10n.string(vi: "Trợ năng (Accessibility)", en: "Accessibility"))
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider()

            if isGranted {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.green)
                    Text(l10n.string(
                        vi: "Đã cấp quyền thành công! Cửa sổ này sẽ tự đóng.",
                        en: "Permission granted! This card will close automatically."
                    ))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.green)
                }
                .padding(.vertical, 8)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    guideStep(1, l10n.string(
                        vi: "Tìm \"SenseBar\" trong danh sách của Cài đặt Hệ thống.",
                        en: "Find \"SenseBar\" in the System Settings list."
                    ))
                    guideStep(2, l10n.string(
                        vi: "Gạt công tắc sang BẬT (ON) để hoàn tất.",
                        en: "Toggle the switch ON to finish."
                    ))
                }

                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text(l10n.string(vi: "Đang chờ bạn bật công tắc...", en: "Waiting for you to enable..."))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if showResetOption {
                        Button(l10n.string(vi: "Làm mới quyền", en: "Reset TCC"), action: onReset)
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(14)
        .frame(width: 340)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isGranted ? Color.green.opacity(0.45) : Color.primary.opacity(0.14), lineWidth: 1)
        )
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                if !isGranted {
                    withAnimation { showResetOption = true }
                }
            }
        }
    }

    private func guideStep(_ index: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(index)")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 17, height: 17)
                .background(Circle().fill(Color.blue))
            Text(text)
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
