import AppKit
import SwiftUI

enum OnboardingStep: Int, CaseIterable {
    case welcome, pillars, permissions, done
}

struct WelcomeOnboardingView: View {
    var onFinish: () -> Void
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = PermissionManager.shared
    @AppStorage(DefaultsKey.onboardingStep) private var stepIndex = 0
    @AppStorage(DefaultsKey.pillarDynamicIslandEnabled) private var island = true
    @AppStorage(DefaultsKey.pillarAudioStudioEnabled) private var audio = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var step: OnboardingStep { OnboardingStep(rawValue: stepIndex) ?? .welcome }
    private func t(_ vi: String, _ en: String) -> String { l10n.string(vi: vi, en: en) }
    private var canContinue: Bool {
        switch step {
        case .welcome: return true
        case .pillars: return island || audio
        case .permissions, .done: return permissions.accessibilityGranted
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                BrandBadge(size: 26)
                Text("SenseBar").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(t("THIẾT LẬP", "SETUP"))
                    .font(.system(size: 9, weight: .bold)).tracking(1.8).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 28).padding(.vertical, 18)
            HStack(spacing: 6) {
                ForEach(OnboardingStep.allCases, id: \.rawValue) { item in
                    Capsule().fill(item.rawValue <= stepIndex ? Color.blue : Color.primary.opacity(0.08))
                        .frame(height: 3)
                }
            }.padding(.horizontal, 28)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(t("BƯỚC", "STEP") + " \(stepIndex + 1)")
                            .font(.system(size: 9, weight: .bold)).tracking(1.5).foregroundStyle(.blue)
                        Text(title).font(.system(size: 28, weight: .bold)).tracking(-0.6)
                        Text(subtitle).font(.system(size: 12.5)).foregroundStyle(.secondary)
                            .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                    }
                    content
                }.padding(28).frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
            Divider().opacity(0.4)
            HStack {
                Button(t("Quay lại", "Back")) { move(to: max(0, stepIndex - 1)) }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .disabled(step == .welcome).opacity(step == .welcome ? 0 : 1)
                Spacer()
                Text("\(stepIndex + 1) / 4").font(.system(size: 10)).monospacedDigit().foregroundStyle(.tertiary)
                Spacer()
                Button(action: advance) {
                    HStack(spacing: 8) {
                        Text(step == .done ? t("Bắt đầu sử dụng", "Get started") : t("Tiếp tục", "Continue"))
                        Image(systemName: "arrow.right")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                }
                .buttonStyle(.borderedProminent).disabled(!canContinue)
                .keyboardShortcut(.defaultAction)
            }.padding(.horizontal, 28).padding(.vertical, 18)
        }
        .frame(width: 560, height: 600)
        .background(Color(nsColor: .textBackgroundColor))
        .onAppear {
            stepIndex = min(max(stepIndex, 0), 3)
            permissions.startMonitoring(interval: 0.8)
            if step == .done && !permissions.accessibilityGranted { stepIndex = 2 }
        }
        .onChange(of: permissions.accessibilityGranted) { _, granted in
            if !granted && step == .done { stepIndex = 2 }
        }
    }

    private var title: String {
        switch step {
        case .welcome: return t("Một góc nhỏ. Nhiều tiện ích.", "A little space. A lot to love.")
        case .pillars: return t("SenseBar theo cách của bạn.", "Make SenseBar yours.")
        case .permissions: return t("Một quyền để bắt đầu.", "One permission to get started.")
        case .done: return t("Mọi thứ đã sẵn sàng.", "You're all set.")
        }
    }

    private var subtitle: String {
        switch step {
        case .welcome: return t("Nhạc, âm thanh và những tương tác nhỏ — ngay trên thanh Menu Bar của máy Mac.", "Music, audio and everyday interactions, right in your Mac's menu bar.")
        case .pillars: return t("Bật ít nhất một tính năng. Bạn có thể thay đổi bất cứ lúc nào trong Cài đặt.", "Choose at least one feature. You can change these in Settings at any time.")
        case .permissions: return t("Bật Trợ năng cho SenseBar trong Cài đặt Hệ thống. Nút Tiếp tục sẽ mở khóa khi quyền được cấp.", "Enable Accessibility for SenseBar in System Settings. Continue unlocks once access is granted.")
        case .done: return t("Bấm biểu tượng SenseBar trên thanh Menu Bar để mở bảng điều khiển.", "Click SenseBar in your menu bar to open your controls.")
        }
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .welcome:
            VStack(spacing: 18) {
                ZStack {
                    RoundedRectangle(cornerRadius: 20).fill(Theme.spaceGradient)
                    VStack(spacing: 16) {
                        BrandBadge(size: 52)
                        HStack(spacing: 12) {
                            Image(systemName: "music.note").foregroundStyle(.blue)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(t("Âm nhạc luôn trong tầm tay", "Your music, always close"))
                                    .font(.system(size: 12, weight: .semibold))
                                Text("SenseBar · Dynamic Island").font(.system(size: 10)).foregroundStyle(.white.opacity(0.55))
                            }
                            Spacer()
                            Image(systemName: "waveform").foregroundStyle(.blue)
                        }
                        .foregroundStyle(.white).padding(14)
                        .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 16))
                    }.padding(24)
                }.frame(height: 180)
                summary("macbook", "Dynamic Island", t("Điều khiển nhạc tại tai thỏ hoặc capsule.", "Music controls in your notch or capsule."), .purple)
                summary("slider.horizontal.3", "Audio Studio", t("Chỉnh âm lượng riêng cho từng ứng dụng.", "Fine-tune the volume of each app."), .blue)
            }
        case .pillars:
            VStack(spacing: 12) {
                choice("macbook", "Dynamic Island", t("Nhạc đang phát, thú cưng và thông báo phụ kiện.", "Now Playing, companions and accessory alerts."), .purple, $island)
                choice("slider.horizontal.3", "Audio Studio", t("Đổi loa đầu ra và chỉnh âm lượng từng ứng dụng từ 0–200%.", "Switch outputs and adjust each app's volume from 0–200%."), .blue, $audio)
                Label(t("Bluetooth và thu âm thanh chỉ được yêu cầu khi dùng tính năng liên quan.", "Bluetooth and audio capture are requested when using related features."), systemImage: "hand.raised")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 8)
            }
        case .permissions:
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    Image(systemName: permissions.accessibilityGranted ? "checkmark.shield.fill" : "hand.raised.fill")
                        .font(.system(size: 27)).foregroundStyle(permissions.accessibilityGranted ? Color.green : Color.blue)
                        .frame(width: 48, height: 48)
                        .background(Color.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 13))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(t("Trợ năng", "Accessibility")).font(.system(size: 14, weight: .semibold))
                        Text(permissions.accessibilityGranted ? t("Đã cấp quyền thành công", "Access granted") : t("Bắt buộc để tiếp tục", "Required to continue"))
                            .font(.system(size: 11)).foregroundStyle(permissions.accessibilityGranted ? Color.green : Color.secondary)
                    }
                    Spacer()
                }
                Divider()
                Text(t("Cho phép SenseBar nhận tương tác chuột toàn cục để điều khiển Dynamic Island.", "Allow SenseBar to receive global mouse interactions for Dynamic Island controls."))
                    .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3)
                if permissions.accessibilityGranted {
                    Label(t("Bạn có thể tiếp tục thiết lập.", "You can now continue setup."), systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(.green)
                } else {
                    Text(t("1. Mở Cài đặt Trợ năng.\n2. Tìm SenseBar và bật công tắc bên phải.", "1. Open Accessibility Settings.\n2. Find SenseBar and enable its switch."))
                        .font(.system(size: 12)).lineSpacing(7)
                    Button(t("Mở Cài đặt Trợ năng", "Open Accessibility Settings")) { permissions.requestAccessibility() }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                }
            }
            .padding(20).background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(permissions.accessibilityGranted ? Color.green.opacity(0.3) : Color.primary.opacity(0.08)))
        case .done:
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 48)).foregroundStyle(.green)
                if island { summary("macbook", "Dynamic Island", t("Đã bật", "Enabled"), .purple) }
                if audio { summary("slider.horizontal.3", "Audio Studio", t("Đã bật", "Enabled"), .blue) }
                Label(t("Trợ năng đã được cấp", "Accessibility access granted"), systemImage: "checkmark.shield")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.green.opacity(0.045), in: RoundedRectangle(cornerRadius: 18))
        }
    }

    private func summary(_ icon: String, _ title: String, _ detail: String, _ color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 18, weight: .medium))
                .foregroundStyle(color).frame(width: 40, height: 40)
                .background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private func choice(_ icon: String, _ title: String, _ detail: String, _ color: Color, _ value: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            summary(icon, title, detail, color)
            Toggle(title, isOn: value).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
        .padding(18)
        .background(value.wrappedValue ? color.opacity(0.045) : Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(value.wrappedValue ? color.opacity(0.3) : Color.primary.opacity(0.08)))
    }

    private func move(to index: Int) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { stepIndex = index }
    }

    private func advance() {
        permissions.refreshStatus()
        guard canContinue else { return }
        if step == .done {
            UserDefaults.standard.set(true, forKey: DefaultsKey.hasOnboarded)
            stepIndex = 0
            onFinish()
        } else { move(to: stepIndex + 1) }
    }
}
