import ApplicationServices
import AppKit
import CoreGraphics
import SwiftUI

enum OnboardingStep: Int, CaseIterable {
    case welcome = 0
    case pillars = 1
    case permissions = 2
    case done = 3
}

struct WelcomeOnboardingView: View {
    var onFinish: () -> Void

    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.onboardingStep) private var stepIndex: Int = 0
    @AppStorage(DefaultsKey.pillarDynamicIslandEnabled) private var dynamicIslandEnabled: Bool = true
    @AppStorage(DefaultsKey.pillarAudioStudioEnabled) private var audioStudioEnabled: Bool = true
    @AppStorage(DefaultsKey.pillarHardwareTelemetryEnabled) private var hardwareTelemetryEnabled: Bool = true

    private var currentStep: OnboardingStep {
        OnboardingStep(rawValue: min(max(0, stepIndex), OnboardingStep.allCases.count - 1)) ?? .welcome
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                stepContent
                    .frame(maxWidth: .infinity, alignment: .top)
            }

            Divider()
                .opacity(0.6)

            navigationFooter
        }
        .frame(width: 560, height: 640)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var stepContent: some View {
        switch currentStep {
        case .welcome:
            WelcomeHeroStep()
        case .pillars:
            PillarsSelectionStep(
                dynamicIslandEnabled: $dynamicIslandEnabled,
                audioStudioEnabled: $audioStudioEnabled,
                hardwareTelemetryEnabled: $hardwareTelemetryEnabled
            )
        case .permissions:
            PermissionsSetupStep()
        case .done:
            DoneReadyStep(
                dynamicIslandEnabled: dynamicIslandEnabled,
                audioStudioEnabled: audioStudioEnabled,
                hardwareTelemetryEnabled: hardwareTelemetryEnabled
            )
        }
    }

    private var navigationFooter: some View {
        HStack(spacing: 12) {
            if stepIndex > 0 {
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                        stepIndex = max(0, stepIndex - 1)
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .bold))
                        Text(l10n.s.btnBack)
                            .font(.system(size: 13, weight: .medium))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            } else {
                Color.clear
                    .frame(width: 88, height: 32)
            }

            Spacer()

            // Chấm tiến trình Aurora
            HStack(spacing: 7) {
                ForEach(OnboardingStep.allCases, id: \.rawValue) { step in
                    let isActive = step.rawValue == stepIndex
                    Capsule()
                        .fill(
                            isActive
                                ? AnyShapeStyle(Theme.auroraGradient)
                                : AnyShapeStyle(Color.primary.opacity(0.16))
                        )
                        .frame(width: isActive ? 22 : 7, height: 7)
                        .animation(.spring(response: 0.26, dampingFraction: 0.8), value: stepIndex)
                }
            }

            Spacer()

            Button {
                if stepIndex < OnboardingStep.allCases.count - 1 {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                        stepIndex += 1
                    }
                } else {
                    UserDefaults.standard.set(true, forKey: DefaultsKey.hasOnboarded)
                    UserDefaults.standard.set(0, forKey: DefaultsKey.onboardingStep)
                    onFinish()
                }
            } label: {
                HStack(spacing: 6) {
                    Text(stepIndex == OnboardingStep.allCases.count - 1 ? l10n.s.btnStart : l10n.s.btnContinue)
                        .font(.system(size: 13, weight: .semibold))
                    Image(systemName: stepIndex == OnboardingStep.allCases.count - 1 ? "sparkles" : "arrow.right")
                        .font(.system(size: 11.5, weight: .bold))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }
}

// MARK: - Bước 1: Màn hình Chào mừng (Welcome Hero)

private struct WelcomeHeroStep: View {
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Theme.spaceGradient
                Theme.auroraGradient
                    .opacity(0.24)
                    .blur(radius: 28)

                VStack(spacing: 10) {
                    BrandBadge(size: 86)
                        .padding(.top, 14)

                    Text(l10n.s.welcomeTitle)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)

                    Text(l10n.s.welcomeSubtitle)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.84))
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                        .padding(.horizontal, 42)
                }
                .padding(.vertical, 22)
            }
            .frame(height: 266)

            VStack(alignment: .leading, spacing: 13) {
                pillarPreviewRow(
                    icon: "macbook",
                    title: l10n.s.pillar1Title,
                    subtitle: l10n.s.pillar1Subtitle
                )
                pillarPreviewRow(
                    icon: "speaker.wave.2.fill",
                    title: l10n.s.pillar2Title,
                    subtitle: l10n.s.pillar2Subtitle
                )
                pillarPreviewRow(
                    icon: "fanblades.fill",
                    title: l10n.s.pillar3Title,
                    subtitle: l10n.s.pillar3Subtitle
                )
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 20)
        }
    }

    private func pillarPreviewRow(icon: String, title: String, subtitle: String) -> some View {
        let accent = Theme.iconColor(for: icon)
        return HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [accent, accent.opacity(0.75)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 38, height: 38)
                    .shadow(color: accent.opacity(0.28), radius: 5, x: 0, y: 2)

                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineSpacing(1.5)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.8)
        )
    }
}

// MARK: - Bước 2: Chọn 3 Trụ cột cốt lõi (3 Core Pillars)

private struct PillarsSelectionStep: View {
    @ObservedObject private var l10n = L10n.shared
    @Binding var dynamicIslandEnabled: Bool
    @Binding var audioStudioEnabled: Bool
    @Binding var hardwareTelemetryEnabled: Bool

    private var activeCount: Int {
        [dynamicIslandEnabled, audioStudioEnabled, hardwareTelemetryEnabled].filter { $0 }.count
    }

    var body: some View {
        VStack(spacing: 16) {
            // Header gắn trực tiếp Logo Icon SenseBar
            VStack(spacing: 6) {
                BrandBadge(size: 62)
                    .padding(.top, 22)

                Text(AppInfo.name)
                    .font(.system(size: 11, weight: .bold))
                    .kerning(0.4)
                    .foregroundStyle(.secondary)

                Text(l10n.s.purposeTitle)
                    .font(.system(size: 21, weight: .bold))

                Text(l10n.s.purposeSubtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 44)

                Text(String(format: l10n.s.purposeActiveCountFormat, activeCount))
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                    .foregroundStyle(Color.accentColor)
                    .padding(.top, 2)
            }

            VStack(spacing: 11) {
                pillarCard(
                    icon: "macbook",
                    title: l10n.s.pillar1Title,
                    subtitle: l10n.s.pillar1Subtitle,
                    tags: l10n.s.pillar1Tags,
                    isOn: $dynamicIslandEnabled
                )

                pillarCard(
                    icon: "speaker.wave.2.fill",
                    title: l10n.s.pillar2Title,
                    subtitle: l10n.s.pillar2Subtitle,
                    tags: l10n.s.pillar2Tags,
                    isOn: $audioStudioEnabled
                )

                pillarCard(
                    icon: "fanblades.fill",
                    title: l10n.s.pillar3Title,
                    subtitle: l10n.s.pillar3Subtitle,
                    tags: l10n.s.pillar3Tags,
                    isOn: $hardwareTelemetryEnabled
                )
            }
            .padding(.horizontal, 26)
            .padding(.bottom, 14)
        }
    }

    private func pillarCard(
        icon: String,
        title: String,
        subtitle: String,
        tags: [String],
        isOn: Binding<Bool>
    ) -> some View {
        let active = isOn.wrappedValue
        let accent = Theme.iconColor(for: icon)

        return Button {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                isOn.wrappedValue.toggle()
            }
        } label: {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [accent, accent.opacity(0.75)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                        .shadow(color: accent.opacity(active ? 0.35 : 0.12), radius: 5, x: 0, y: 2)

                    Image(systemName: icon)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(title)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.primary)

                        Spacer()

                        Image(systemName: active ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(active ? accent : Color.secondary.opacity(0.35))
                    }

                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 6) {
                        ForEach(tags, id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 10, weight: .semibold))
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .padding(.horizontal, 7.5)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule()
                                        .fill(active ? accent.opacity(0.14) : Color.primary.opacity(0.05))
                                )
                                .foregroundStyle(active ? accent : .secondary)
                        }
                    }
                    .padding(.top, 2)
                }
            }
            .padding(13)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(active ? accent.opacity(0.07) : Color.primary.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        active ? accent.opacity(0.45) : Color.primary.opacity(0.08),
                        lineWidth: active ? 1.2 : 0.8
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Bước 3: Cấp quyền hệ thống (Permissions)

private struct PermissionsSetupStep: View {
    @ObservedObject private var l10n = L10n.shared
    @State private var accessibilityGranted = AXIsProcessTrusted()
    @State private var screenCaptureGranted = CGPreflightScreenCaptureAccess()

    private let timer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                BrandBadge(size: 62)
                    .padding(.top, 24)

                Text(AppInfo.name)
                    .font(.system(size: 11, weight: .bold))
                    .kerning(0.4)
                    .foregroundStyle(.secondary)

                Text(l10n.s.permissionsTitle)
                    .font(.system(size: 21, weight: .bold))

                Text(l10n.s.permissionsSubtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 44)
            }

            VStack(spacing: 14) {
                permissionCard(
                    icon: "accessibility",
                    title: l10n.s.permAccessibilityTitle,
                    description: l10n.s.permAccessibilityDesc,
                    isGranted: accessibilityGranted
                ) {
                    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                    _ = AXIsProcessTrustedWithOptions(options)
                    accessibilityGranted = AXIsProcessTrusted()
                }

                permissionCard(
                    icon: "waveform",
                    title: l10n.s.permAudioScreenTitle,
                    description: l10n.s.permAudioScreenDesc,
                    isGranted: screenCaptureGranted
                ) {
                    _ = CGRequestScreenCaptureAccess()
                    screenCaptureGranted = CGPreflightScreenCaptureAccess()
                }
            }
            .padding(.horizontal, 26)

            Text(l10n.s.permNote)
                .font(.system(size: 11.5))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 48)
                .padding(.top, 4)
        }
        .onReceive(timer) { _ in
            accessibilityGranted = AXIsProcessTrusted()
            screenCaptureGranted = CGPreflightScreenCaptureAccess()
        }
    }

    private func permissionCard(
        icon: String,
        title: String,
        description: String,
        isGranted: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let accent = Theme.iconColor(for: icon)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(accent.opacity(0.16))
                        .frame(width: 38, height: 38)
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(accent)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(title)
                            .font(.system(size: 14, weight: .bold))

                        Spacer()

                        HStack(spacing: 4) {
                            Image(systemName: isGranted ? "checkmark.seal.fill" : "clock.badge.exclamationmark")
                                .font(.system(size: 11, weight: .bold))
                            Text(isGranted ? l10n.s.permGrantedBadge : l10n.s.permRequiredBadge)
                                .font(.system(size: 10.5, weight: .bold))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(isGranted ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                        )
                        .foregroundStyle(isGranted ? Color.green : Color.orange)
                    }

                    Text(description)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !isGranted {
                HStack {
                    Spacer()
                    Button(l10n.s.permGrantButton, action: action)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    isGranted ? Color.green.opacity(0.35) : Color.primary.opacity(0.08),
                    lineWidth: 0.9
                )
        )
    }
}

// MARK: - Bước 4: Hoàn tất (Done & Ready)

private struct DoneReadyStep: View {
    @ObservedObject private var l10n = L10n.shared
    let dynamicIslandEnabled: Bool
    let audioStudioEnabled: Bool
    let hardwareTelemetryEnabled: Bool

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Theme.spaceGradient
                Theme.auroraGradient
                    .opacity(0.28)
                    .blur(radius: 30)

                VStack(spacing: 12) {
                    BrandBadge(size: 88)
                        .padding(.top, 12)

                    Text(l10n.s.doneTitle)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)

                    Text(l10n.s.doneSubtitle)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.86))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 48)
                }
                .padding(.vertical, 24)
            }
            .frame(height: 276)

            VStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(l10n.s.doneActivePillarsTitle)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        activePillarBadge(icon: "macbook", title: "Dynamic Island", active: dynamicIslandEnabled)
                        activePillarBadge(icon: "speaker.wave.2.fill", title: "Âm thanh", active: audioStudioEnabled)
                        activePillarBadge(icon: "fanblades.fill", title: "Phần cứng & Quạt", active: hardwareTelemetryEnabled)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.primary.opacity(0.035))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8)
                )

                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.14))
                            .frame(width: 40, height: 40)
                        Image(systemName: "menubar.arrow.up.rectangle")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    }

                    Text(l10n.s.doneMenuBarHint)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.accentColor.opacity(0.06))
                )
            }
            .padding(26)
        }
    }

    private func activePillarBadge(icon: String, title: String, active: Bool) -> some View {
        let accent = Theme.iconColor(for: icon)
        return HStack(spacing: 6) {
            Image(systemName: active ? "checkmark.circle.fill" : "minus.circle")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(active ? accent : .secondary)
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(active ? .primary : .secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(active ? accent.opacity(0.12) : Color.primary.opacity(0.04))
        )
    }
}
