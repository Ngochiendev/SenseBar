import AppKit
import SwiftUI

/// Màn hình Cài đặt tích hợp trực tiếp bên trong Menu Bar Popover.
/// Mỗi thẻ cài đặt là một view riêng trong thư mục `Views/Settings`.
struct PopoverSettingsView: View {
    let onBack: () -> Void
    let onQuit: () -> Void

    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var islandController = NotchDynamicIslandController.shared

    var body: some View {
        VStack(spacing: 10) {
            headerBar

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 12) {
                    StartupFeaturesCard()

                    DisplayTargetCard()

                    if islandController.canChooseStyle {
                        NotchStyleCard()
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    FitAdjustmentCard()

                    LiquidGlassCard()

                    AboutUpdateCard()
                }
                .padding(.vertical, 2)
                .animation(.easeInOut(duration: 0.25), value: islandController.canChooseStyle)
            }
            .frame(maxHeight: 450)

            footerBar
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        ZStack {
            Text(l10n.string(vi: "Cài đặt", en: "Settings"))
                .font(.system(size: 13.5, weight: .bold))
                .foregroundStyle(.primary)

            HStack {
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .bold))
                        Text(l10n.string(vi: "Quay lại", en: "Back"))
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(Color.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1), in: Capsule())
                }
                .buttonStyle(.plain)

                Spacer()
            }
        }
        .padding(.horizontal, 2)
        .padding(.bottom, 2)
    }

    // MARK: - Footer Bar

    private var footerBar: some View {
        HStack {
            Button(action: onQuit) {
                HStack(spacing: 5) {
                    Image(systemName: "power")
                        .font(.system(size: 11, weight: .semibold))
                    Text(l10n.string(vi: "Thoát SenseBar", en: "Quit SenseBar"))
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(.red.opacity(0.85))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)

            Spacer()

            Button(action: onBack) {
                Text(l10n.string(vi: "Đóng", en: "Done"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 2)
        .padding(.top, 2)
    }
}
