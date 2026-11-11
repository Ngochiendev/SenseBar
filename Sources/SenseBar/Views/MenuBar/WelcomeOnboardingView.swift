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
    @AppStorage(DefaultsKey.notchDeviceNotices) private var deviceNotices = true
    @AppStorage(DefaultsKey.notchLowPeripheralBattery) private var lowBattery = true
    @AppStorage(DefaultsKey.petEnabled) private var petEnabled = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var step: OnboardingStep { OnboardingStep(rawValue: stepIndex) ?? .welcome }
    private func t(_ vi: String, _ en: String) -> String { l10n.string(vi: vi, en: en) }
    private var needsBluetooth: Bool { island && deviceNotices }
    private var canContinue: Bool {
        switch step {
        case .welcome: return true
        case .pillars: return island || audio
        case .permissions, .done:
            return permissions.accessibilityGranted && (!needsBluetooth || permissions.bluetoothGranted)
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            navigationSidebar
            VStack(spacing: 0) {
                pageHeader
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        content
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 28).padding(.bottom, 24).padding(.top, 4)
                }
                .id(step)
                .frame(maxHeight: .infinity)
                pageFooter
            }
            .frame(maxWidth: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
        }
        .font(.system(size: 13, weight: .regular, design: .default))
        .fontDesign(.default)
        .frame(width: 820, height: 720)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            stepIndex = min(max(stepIndex, 0), 3)
            permissions.startMonitoring(interval: 0.8)
            if step == .done && !canContinue { stepIndex = OnboardingStep.permissions.rawValue }
        }
        .onChange(of: permissions.accessibilityGranted) { _, granted in
            if !granted && step == .done { stepIndex = OnboardingStep.permissions.rawValue }
        }
        .onChange(of: permissions.bluetoothGranted) { _, granted in
            if needsBluetooth && !granted && step == .done {
                stepIndex = OnboardingStep.permissions.rawValue
            }
        }
    }

    private var navigationSidebar: some View {
        VStack(alignment: .leading, spacing: 32) {
            HStack(spacing: 10) {
                BrandBadge(size: 32)
                Text("SenseBar").font(.system(size: 16, weight: .semibold))
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(OnboardingStep.allCases, id: \.rawValue) { item in
                    HStack(spacing: 10) {
                        ZStack {
                            Circle().fill(item.rawValue == stepIndex ? Color.blue : Color.primary.opacity(0.055))
                            if item.rawValue < stepIndex {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold)).foregroundStyle(.blue)
                            } else {
                                Text("\(item.rawValue + 1)")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(item.rawValue == stepIndex ? Color.white : Color.secondary)
                            }
                        }
                        .frame(width: 26, height: 26)
                        Text(stepName(item)).font(.system(size: 12, weight: item.rawValue == stepIndex ? .semibold : .regular))
                            .foregroundStyle(item.rawValue == stepIndex ? Color.primary : Color.secondary)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 10)
                    .background(item.rawValue == stepIndex ? Color.blue.opacity(0.075) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityLabel(stepName(item) + (item.rawValue == stepIndex ? t(", bước hiện tại", ", current step") : ""))
                }
            }
            Spacer()
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "sparkles").font(.system(size: 18)).foregroundStyle(.blue.opacity(0.65))
                Text(t("Một chút tiện lợi.\nMỗi ngày trên Mac.", "A little convenience.\nEvery day on your Mac."))
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 30)
        .frame(width: 180)
        .frame(maxHeight: .infinity)
        .background(Color.primary.opacity(0.025))
        .overlay(alignment: .trailing) { Rectangle().fill(Color.primary.opacity(0.06)).frame(width: 1) }
    }

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(stepName(step)).font(.system(size: 11, weight: .medium)).foregroundStyle(.blue)
                Spacer()
                Text("\(stepIndex + 1) / \(OnboardingStep.allCases.count)")
                    .font(.system(size: 11)).monospacedDigit().foregroundStyle(.tertiary)
            }
            Text(title).font(.system(size: 27, weight: .bold)).tracking(-0.6)
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
                .lineSpacing(4).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 28).padding(.top, 30).padding(.bottom, 24)
    }

    private var pageFooter: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1)
            HStack(spacing: 12) {
                Button { move(to: max(0, stepIndex - 1)) } label: {
                    Label(t("Quay lại", "Back"), systemImage: "chevron.left")
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 14).frame(height: 42)
                        .background(Color.primary.opacity(0.04), in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .disabled(step == .welcome).opacity(step == .welcome ? 0 : 1)
                Spacer(minLength: 8)
                if !canContinue {
                    Text(step == .pillars ? t("Chọn ít nhất một tính năng", "Choose a feature")
                         : t("Cấp đủ quyền để tiếp tục", "Allow access to continue"))
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button(action: advance) {
                    HStack(spacing: 9) {
                        Text(step == .done ? t("Bắt đầu sử dụng", "Get started") : t("Tiếp tục", "Continue"))
                        Image(systemName: "arrow.right").font(.system(size: 11, weight: .semibold))
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 22).frame(minHeight: 42)
                }
                .buttonStyle(OnboardingPrimaryButtonStyle()).disabled(!canContinue)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 28).padding(.vertical, 18)
        }
    }

    private func stepName(_ step: OnboardingStep) -> String {
        switch step {
        case .welcome: t("Chào mừng", "Welcome")
        case .pillars: t("Cá nhân hóa", "Make it yours")
        case .permissions: t("Quyền truy cập", "Permissions")
        case .done: t("Sẵn sàng", "Ready")
        }
    }

    private var title: String {
        switch step {
        case .welcome: return t("Mac của bạn. Tiện lợi hơn.", "Your Mac. A little more effortless.")
        case .pillars: return t("Chọn điều bạn yêu thích.", "Make room for what you love.")
        case .permissions: return t("Một vài quyền cần thiết.", "A few permissions to get started.")
        case .done: return t("Mọi thứ đã sẵn sàng.", "You're all set.")
        }
    }

    private var subtitle: String {
        switch step {
        case .welcome: return t("Nhạc, âm thanh và những tương tác nhỏ — ngay trên thanh Menu Bar của máy Mac.", "Music, audio and everyday interactions, right in your Mac's menu bar.")
        case .pillars: return t("Các tính năng đã sẵn sàng. Tắt những gì bạn không cần — mọi lựa chọn đều có thể đổi sau.", "Your features are ready. Turn off anything you don't need — you can change everything later.")
        case .permissions:
            return needsBluetooth
                ? t("SenseBar cần Trợ năng và Bluetooth cho các tính năng bạn đã chọn. Cấp từng quyền bên dưới để tiếp tục.", "SenseBar needs Accessibility and Bluetooth for your selected features. Allow each below to continue.")
                : t("Bật Trợ năng cho SenseBar trong Cài đặt Hệ thống. Nút Tiếp tục sẽ mở khóa khi quyền được cấp.", "Enable Accessibility for SenseBar in System Settings. Continue unlocks once access is granted.")
        case .done: return t("Bấm biểu tượng SenseBar trên thanh Menu Bar để mở bảng điều khiển.", "Click SenseBar in your menu bar to open your controls.")
        }
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .welcome:
            VStack(spacing: 18) {
                ZStack {
                    RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Theme.spaceGradient)
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
                        .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    }.padding(24)
                }.frame(height: 180)
                summary("macbook", "Dynamic Island", t("Điều khiển nhạc tại tai thỏ hoặc capsule.", "Music controls in your notch or capsule."), .purple)
                summary("slider.horizontal.3", "Audio Studio", t("Chỉnh âm lượng riêng cho từng ứng dụng.", "Fine-tune the volume of each app."), .blue)
            }
        case .pillars:
            VStack(spacing: 14) {
                choice("macbook", "Dynamic Island", t("Nhạc đang phát và các tương tác trên tai thỏ/capsule.", "Now Playing and interactions in your notch or capsule."), .purple, $island)
                if island {
                    HStack(alignment: .top, spacing: 14) {
                        companionChoice
                        accessoryAlertChoice
                    }
                }
                choice("slider.horizontal.3", "Audio Studio", t("Đổi loa đầu ra và chỉnh âm lượng từng ứng dụng từ 0–200%.", "Switch outputs and adjust each app's volume from 0–200%."), .blue, $audio)
                Label(t("Bạn quyết định những gì SenseBar được phép sử dụng.", "You choose what SenseBar can access."), systemImage: "hand.raised")
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
                if permissions.accessibilityGranted {
                    Text(t("Đã sẵn sàng nhận tương tác với Dynamic Island.", "Ready for interactions with Dynamic Island."))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                } else {
                    Text(t("Cho phép SenseBar nhận tương tác chuột để điều khiển Dynamic Island.", "Allow SenseBar to receive mouse interactions for Dynamic Island controls."))
                        .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3)
                    VStack(alignment: .leading, spacing: 14) {
                        accessibilityStep(1, t("Mở trang Trợ năng", "Open Accessibility"),
                                          detail: t("Bấm nút bên dưới để mở đúng trang cài đặt.", "Use the button below to open the right settings page."))
                        accessibilityStep(2, t("Bật công tắc SenseBar", "Enable SenseBar"),
                                          detail: t("Sau khi cấp quyền, quay lại đây để tiếp tục.", "Return here after granting access to continue."))
                    }
                    Button {
                        permissions.requestAccessibility()
                    } label: {
                        Label(t("Mở Cài đặt Trợ năng", "Open Accessibility Settings"), systemImage: "arrow.up.forward.app")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .padding(.horizontal, 18)
                    }
                    .buttonStyle(OnboardingPrimaryButtonStyle())

                    DisclosureGroup {
                        Text(t("Trong trang Trợ năng, bấm dấu + ở cuối danh sách, chọn SenseBar.app rồi bật công tắc bên cạnh ứng dụng.",
                               "In Accessibility, click + at the bottom of the list, select SenseBar.app, then enable its switch."))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 6)
                    } label: {
                        Text(t("Không thấy SenseBar trong danh sách?", "Can't find SenseBar in the list?"))
                            .font(.system(size: 11, weight: .medium))
                    }
                }
            }
            .onboardingSurface(tint: permissions.accessibilityGranted ? .green : .blue, selected: true)
            if needsBluetooth {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: permissions.bluetoothGranted ? "checkmark" : "airpodspro")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(permissions.bluetoothGranted ? Color.green : Color.blue)
                            .frame(width: 44, height: 44)
                            .background(Color.blue.opacity(0.065), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Bluetooth").font(.system(size: 14, weight: .semibold))
                            Text(t("Dành cho thông báo phụ kiện", "For accessory alerts"))
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    Text(permissions.bluetoothGranted
                         ? t("Đã cấp quyền nhận diện phụ kiện.", "Accessory access is granted.")
                         : t("Bạn đã bật thông báo phụ kiện. Cấp quyền Bluetooth để tiếp tục, hoặc tắt tính năng này bên dưới.",
                             "You enabled accessory alerts. Allow Bluetooth to continue, or turn off this feature below."))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !permissions.bluetoothGranted {
                        Button { permissions.requestBluetooth() } label: {
                            Label(t("Cho phép Bluetooth", "Allow Bluetooth"), systemImage: "hand.raised")
                                .font(.system(size: 12, weight: .semibold))
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .padding(.horizontal, 18)
                        }
                        .buttonStyle(OnboardingPrimaryButtonStyle())
                        Button(t("Tắt thông báo phụ kiện", "Turn off accessory alerts")) {
                            deviceNoticesBinding.wrappedValue = false
                        }
                        .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .onboardingSurface(tint: permissions.bluetoothGranted ? .green : .blue, selected: true)
            }
        case .done:
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 48)).foregroundStyle(.green)
                if island { summary("macbook", "Dynamic Island", t("Đã bật", "Enabled"), .purple) }
                if island && petEnabled { summary("pawprint.fill", t("Thú cưng", "Companion"), t("Đã bật", "Enabled"), .pink) }
                if needsBluetooth { summary("airpodspro", t("Thông báo phụ kiện", "Accessory alerts"), t("Bluetooth đã sẵn sàng", "Bluetooth is ready"), .blue) }
                if audio { summary("slider.horizontal.3", "Audio Studio", t("Đã bật", "Enabled"), .blue) }
                Label(t("Trợ năng đã được cấp", "Accessibility access granted"), systemImage: "checkmark.shield")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onboardingSurface(tint: .green, selected: true)
        }
    }

    private func accessibilityStep(_ number: Int, _ title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.blue)
                .frame(width: 24, height: 24)
                .background(Color.blue.opacity(0.09), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var companionChoice: some View {
        VStack(alignment: .leading, spacing: 12) {
            PetOnboardingIllustration(enabled: petEnabled)
                .frame(height: 72)
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(t("Thú cưng", "Companion"))
                        .font(.system(size: 13, weight: .semibold))
                    Text(t("Chào bạn, ngủ khi rảnh và phản ứng với trạng thái máy.",
                           "Greets you, sleeps when idle and reacts to system status."))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Toggle(t("Thú cưng", "Companion"), isOn: $petEnabled)
                    .labelsHidden().toggleStyle(.switch).controlSize(.small)
            }
            Label(t("Có thể đổi ngoại hình và tắt bất cứ lúc nào trong Cài đặt.",
                    "Change its look or turn it off anytime in Settings."),
                  systemImage: "paintpalette.fill")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 290, alignment: .topLeading)
        .onboardingSurface(tint: .pink, selected: petEnabled, padding: 16)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var accessoryAlertChoice: some View {
        VStack(alignment: .leading, spacing: 12) {
            DeviceAlertsIllustration(enabled: deviceNotices)
                .frame(height: 72)
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(t("Phụ kiện", "Accessories"))
                        .font(.system(size: 13, weight: .semibold))
                    Text(t("Hiện AirPods, bàn phím và trạng thái sạc trên đảo.",
                           "Show AirPods, keyboards and charging status on the island."))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Toggle(t("Thông báo phụ kiện", "Accessory alerts"), isOn: deviceNoticesBinding)
                    .labelsHidden().toggleStyle(.switch).controlSize(.small)
            }
            Divider().opacity(0.35)
            HStack {
                Label(t("Pin yếu · 20% và 10%", "Low battery · 20% and 10%"),
                      systemImage: "battery.25percent")
                    .font(.system(size: 10.5))
                Spacer(minLength: 8)
                Toggle(t("Cảnh báo pin phụ kiện", "Accessory battery alerts"), isOn: $lowBattery)
                    .labelsHidden().toggleStyle(.switch).controlSize(.small)
                    .disabled(!deviceNotices)
            }
            .opacity(deviceNotices ? 1 : 0.45)
            Label(t("Cần quyền Bluetooth ở bước tiếp theo.",
                    "Requires Bluetooth access in the next step."),
                  systemImage: "hand.raised.fill")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 290, alignment: .topLeading)
        .onboardingSurface(tint: .blue, selected: deviceNotices, padding: 16)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var deviceNoticesBinding: Binding<Bool> {
        Binding(get: { deviceNotices }, set: { enabled in
            deviceNotices = enabled
            if !enabled { lowBattery = false }
        })
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
        .onboardingSurface(tint: color, selected: value.wrappedValue, padding: 16)
    }

    private func move(to index: Int) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { stepIndex = index }
    }

    private func advance() {
        permissions.refreshStatus()
        guard canContinue else { return }
        if step == .done {
            // Ghi lựa chọn mặc định xuống bộ nhớ để lần mở sau vẫn giữ đúng ý người dùng.
            UserDefaults.standard.set(petEnabled, forKey: DefaultsKey.petEnabled)
            UserDefaults.standard.set(deviceNotices, forKey: DefaultsKey.notchDeviceNotices)
            UserDefaults.standard.set(lowBattery, forKey: DefaultsKey.notchLowPeripheralBattery)
            UserDefaults.standard.set(true, forKey: DefaultsKey.hasOnboarded)
            stepIndex = 0
            onFinish()
        } else { move(to: stepIndex + 1) }
    }
}

private extension View {
    func onboardingSurface(tint: Color, selected: Bool, padding: CGFloat = 20) -> some View {
        self.padding(padding)
            .background(Color(nsColor: .controlBackgroundColor),
                        in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(selected ? tint.opacity(0.20) : Color.primary.opacity(0.07), lineWidth: 1))
            .shadow(color: .black.opacity(0.025), radius: 8, y: 3)
    }
}

private struct OnboardingPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white.opacity(isEnabled ? 1 : 0.65))
            .background(
                LinearGradient(colors: [Color.blue, Color.blue.opacity(0.82)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: Capsule()
            )
            .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
            .shadow(color: .blue.opacity(isEnabled ? 0.18 : 0), radius: 8, y: 3)
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
            .contentShape(Capsule())
    }
}
