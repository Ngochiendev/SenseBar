import AppKit
import Sparkle
import SwiftUI

/// Giữ luồng cài đặt chuẩn của Sparkle, tùy biến thông báo đã cập nhật.
@MainActor
final class SenseBarUpdateUserDriver: SPUStandardUserDriver {
#if DEBUG
    static func previewNotes(version: String, data: Data) throws -> String {
        let versions = try JSONDecoder().decode([String: String].self, from: data)
        guard let notes = versions[version],
              notes.contains("<meta name=\"sensebar-version\" content=\"\(version)\">"),
              !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NSError(domain: "SenseBar.UpdatePreview", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "changelog.yaml chưa có release notes hợp lệ cho \(version). Hãy kiểm tra version và build lại với --debug --preview-updates."
            ])
        }
        return notes
    }

    /// Notes dùng đúng HTML định dạng của CI; URL .invalid không tải gói thật.
    static func previewFixture(version: String, releaseNotes notes: String) throws -> (SUAppcastItem, SPUUserUpdateState) {
        // Debug-only fixture using Sparkle 2.10.1's secure archive format.
        // Keep these keys in sync with SUAppcastItem when upgrading Sparkle.
        let itemArchive = NSKeyedArchiver(requiringSecureCoding: true)
        for key in ["deltaUpdates", "SUAppcastItemDeltaFromSparkleExecutableSize",
                    "SUAppcastItemDeltaFromSparkleLocales", "signatures", "releaseNotesSignatures",
                    "infoURL", "SUAppcastItemState", "maximumSystemVersion", "minimumSystemVersion",
                    "sparkle:minimumAutoupdateVersion", "hardwareRequirements", "sparkle:minimumUpdateVersion",
                    "sparkle:ignoreSkippedUpgradesBelowVersion", "releaseNotesURL", "fullReleaseNotesURL",
                    "sparkle:phasedRolloutInterval", "sparkle:channel"] {
            itemArchive.encode(nil as NSObject?, forKey: key)
        }
        itemArchive.encode("SenseBar \(version)", forKey: "title")
        itemArchive.encode("999999", forKey: "versionString")
        itemArchive.encode(version, forKey: "displayVersionString")
        itemArchive.encode(notes, forKey: "itemDescription")
        itemArchive.encode("html", forKey: "itemDescriptionFormat")
        itemArchive.encode(URL(string: "https://preview.invalid/SenseBar-preview.zip")! as NSURL, forKey: "fileURL")
        itemArchive.encode(Int64(5_608_223), forKey: "contentLength")
        itemArchive.encode(Int64(0), forKey: "linkLength")
        itemArchive.encode("application", forKey: "SUAppcastItemInstallationType")
        itemArchive.encode("macos", forKey: "sparkle:os")
        itemArchive.encode([String: String]() as NSDictionary, forKey: "propertiesDictionary")
        itemArchive.encode(0, forKey: "SUAppcastItemSigningValidationStatus")
        itemArchive.finishEncoding()
        let itemDecoder = try NSKeyedUnarchiver(forReadingFrom: itemArchive.encodedData)
        defer { itemDecoder.finishDecoding() }
        guard let item = SUAppcastItem(coder: itemDecoder) else { throw CocoaError(.coderInvalidValue) }

        // SPUUserUpdateState exposes NSSecureCoding, but no public memberwise
        // initializer. Fixture keys match the pinned Sparkle 2.10.1 archive format.
        let archive = NSKeyedArchiver(requiringSecureCoding: true)
        archive.encode(SPUUserUpdateStage.notDownloaded.rawValue, forKey: "SPUUserUpdateStateStage")
        archive.encode(true, forKey: "SPUUserUpdateStateUserInitiated")
        archive.finishEncoding()
        let decoder = try NSKeyedUnarchiver(forReadingFrom: archive.encodedData)
        defer { decoder.finishDecoding() }
        guard let state = SPUUserUpdateState(coder: decoder) else { throw CocoaError(.coderInvalidValue) }
        return (item, state)
    }

    func showUpdatePreview(version: String, completion: @escaping () -> Void) {
        do {
            guard let url = Bundle.main.url(forResource: "UpdatePreviewNotes", withExtension: "json") else {
                throw NSError(domain: "SenseBar.UpdatePreview", code: 2, userInfo: [
                    NSLocalizedDescriptionKey: "Chưa đóng gói changelog cho preview. Hãy build bằng ./build-app.sh --debug --preview-updates rồi mở lại app."
                ])
            }
            let notes = try Self.previewNotes(version: version, data: Data(contentsOf: url))
            let (item, state) = try Self.previewFixture(version: version, releaseNotes: notes)
            NSApp.activate(ignoringOtherApps: true)
            showUpdateFound(with: item, state: state) { [weak self] choice in
                self?.dismissUpdateInstallation()
                if choice == .install {
                    let alert = NSAlert()
                    alert.messageText = L10n.shared.string(vi: "Đây là bản xem thử", en: "This is a preview")
                    alert.informativeText = L10n.shared.string(
                        vi: "Trong bản phát hành thật, Sparkle sẽ tải và cài bản cập nhật ở bước này. Không có file nào được tải trong chế độ xem thử.",
                        en: "In a real release, Sparkle would download and install the update here. No files are downloaded in preview mode."
                    )
                    alert.runModal()
                }
                completion()
            }
        } catch {
            completion()
            let alert = NSAlert()
            alert.messageText = L10n.shared.string(vi: "Không thể mở bản xem thử", en: "Could not open update preview")
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
#endif

    override func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        guard let reason = ((error as NSError).userInfo[SPUNoUpdateFoundReasonKey] as? NSNumber)?.int32Value,
              reason == SPUNoUpdateFoundReason.onLatestVersion.rawValue ||
              reason == SPUNoUpdateFoundReason.onNewerThanLatestVersion.rawValue else {
            super.showUpdateNotFoundWithError(error, acknowledgement: acknowledgement)
            return
        }

        // Close Sparkle's checking window before presenting our confirmation.
        super.dismissUpdateInstallation()
        let panel = UpdateConfirmationPanel(
            contentRect: NSRect(x: 0, y: 0, width: 288, height: 220),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        panel.title = L10n.shared.string(vi: "Cập nhật SenseBar", en: "SenseBar Updates")
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        let content = NSHostingView(rootView: UpdateConfirmationView {
            NSApp.stopModal()
        })
        panel.contentView = content
        panel.setContentSize(content.fittingSize)
        panel.center()
        NSApp.activate(ignoringOtherApps: true)
        NSApp.runModal(for: panel)
        panel.orderOut(nil)
        acknowledgement()
    }
}

@MainActor
private final class UpdateConfirmationPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        NSApp.stopModal()
    }
}

private struct UpdateConfirmationView: View {
    @ObservedObject private var l10n = L10n.shared
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: BrandIconResources.appIconImage())
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 56, height: 56)
                .accessibilityHidden(true)
                .padding(.bottom, 12)

            Text(l10n.string(vi: "Bạn đang dùng bản mới nhất", en: "You're up to date"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 6)

            Text(l10n.string(
                vi: "Phiên bản \(AppInfo.version)",
                en: "Version \(AppInfo.version)"
            ))
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 20)

            buttonLabel
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 18)
        .frame(width: 288)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.primary.opacity(0.1), lineWidth: 0.5)
                .allowsHitTesting(false)
        }
    }

    private var buttonLabel: some View {
        Button(action: dismiss) {
            Text(l10n.string(vi: "Xong", en: "Done"))
                .font(.system(size: 12, weight: .medium))
                .frame(maxWidth: .infinity)
        }
        .keyboardShortcut(.defaultAction)
    }
}
