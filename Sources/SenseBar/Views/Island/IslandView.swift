import AppKit
import SwiftUI

/// Đường cong hình học mô phỏng tai thỏ macOS, kết hợp vai cong loe phía trên và góc bo tròn phía dưới.
struct NotchAttachedShape: Shape {
    var topShoulder: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topShoulder, bottomRadius) }
        set {
            topShoulder = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let shoulder = min(topShoulder, rect.height * 0.45, rect.width * 0.15)
        let bottom = min(bottomRadius, rect.height * 0.45, (rect.width - shoulder * 2) / 2)
        let tangent: CGFloat = 0.55228475

        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: 0))
        path.addCurve(
            to: CGPoint(x: rect.width - shoulder, y: shoulder),
            control1: CGPoint(x: rect.width - shoulder * tangent, y: 0),
            control2: CGPoint(x: rect.width - shoulder, y: shoulder * (1 - tangent))
        )
        path.addLine(to: CGPoint(x: rect.width - shoulder, y: rect.height - bottom))
        path.addCurve(
            to: CGPoint(x: rect.width - shoulder - bottom, y: rect.height),
            control1: CGPoint(x: rect.width - shoulder, y: rect.height - bottom * (1 - tangent)),
            control2: CGPoint(x: rect.width - shoulder - bottom * (1 - tangent), y: rect.height)
        )
        path.addLine(to: CGPoint(x: shoulder + bottom, y: rect.height))
        path.addCurve(
            to: CGPoint(x: shoulder, y: rect.height - bottom),
            control1: CGPoint(x: shoulder + bottom * (1 - tangent), y: rect.height),
            control2: CGPoint(x: shoulder, y: rect.height - bottom * (1 - tangent))
        )
        path.addLine(to: CGPoint(x: shoulder, y: shoulder))
        path.addCurve(
            to: .zero,
            control1: CGPoint(x: shoulder, y: shoulder * (1 - tangent)),
            control2: CGPoint(x: shoulder * tangent, y: 0)
        )
        path.closeSubpath()
        return path
    }
}

/// Giao diện Dynamic Island trên macOS, hỗ trợ chế độ tai thỏ phần cứng hoặc viên nang nổi (Capsule).
struct IslandView: View {
    @ObservedObject var controller: IslandController
    var displayID: CGDirectDisplayID? = nil
    var isMirror: Bool = false
    @ObservedObject var music = MusicService.shared
    @ObservedObject var audio = AudioStudioService.shared
    @ObservedObject var pet = PetService.shared
    @ObservedObject var l10n = L10n.shared
    @ObservedObject private var notices = DeviceNoticeService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @AppStorage(DefaultsKey.notchStyle) private var notchStyle: String = "notch"
    @AppStorage(DefaultsKey.notchShowVisualizer) private var showVisualizer: Bool = true
    @AppStorage(DefaultsKey.notchCapsuleFitDrop) private var capsuleFitDrop: Double = 0
    @AppStorage(DefaultsKey.liquidGlassIslandEnabled) private var liquidGlassIsland: Bool = true
    @AppStorage(DefaultsKey.notchExpandAllDisplays) private var expandAllDisplays: Bool = false

    /// Chế độ viên nang nổi chỉ áp dụng cho màn hình không có tai thỏ vật lý.
    private var isPillMode: Bool {
        notchStyle == "pill" && !geo.isNotched
    }

    private var isViewExpanded: Bool {
        controller.isExpanded && (!isMirror || expandAllDisplays)
    }

    private var assignedScreen: NSScreen {
        if let displayID, let matched = NSScreen.screens.first(where: { $0.displayID == displayID }) {
            return matched
        }
        return controller.targetScreenForActivePanel
    }

    private var geo: ScreenGeometry {
        ScreenGeometry(for: assignedScreen)
    }

    private var islandSize: CGSize {
        controller.islandSize(for: assignedScreen, expanded: isViewExpanded)
    }

    var body: some View {
        let currentGeo = geo
        let size = islandSize
        let isPill = isPillMode
        let topOffset: CGFloat = isPill
            ? (currentGeo.capsuleVerticalCenterOffset + CGFloat(capsuleFitDrop))
            : 0

        ZStack(alignment: .top) {
            Color.clear

            islandContainer(size: size, isPill: isPill, geo: currentGeo)
                .frame(width: size.width, height: size.height, alignment: .top)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: notices.current?.id)
                .padding(.top, topOffset)
                .animation(.spring(response: 0.42, dampingFraction: 0.72), value: isViewExpanded)
                .animation(.spring(response: 0.42, dampingFraction: 0.72), value: music.track?.isPlaying)
                .animation(.spring(response: 0.42, dampingFraction: 0.72), value: pet.isEnabled)
                .animation(.easeInOut(duration: 0.18), value: pet.currentStatusCue?.id)
                .animation(.spring(response: 0.32, dampingFraction: 0.84), value: isPill)
        }
        .frame(width: IslandController.canvasWidth, height: IslandController.canvasHeight, alignment: .top)
    }

    @ViewBuilder
    private func islandContainer(size: CGSize, isPill: Bool, geo: ScreenGeometry) -> some View {
        let expanded = isViewExpanded
        let pillRadius = expanded ? 26.0 : Double(size.height / 2)
        let shoulder = expanded ? 14.0 : geo.shoulderRadius.shoulder
        let bottom = expanded ? 24.0 : geo.shoulderRadius.bottom
        let usesGlass = liquidGlassIsland && expanded

        ZStack(alignment: .top) {
            if isPill {
                let pillShape = RoundedRectangle(cornerRadius: pillRadius, style: .continuous)
                Group {
                    if usesGlass {
                        #if compiler(>=6.2)
                        if #available(macOS 26.0, *) {
                            Color.clear
                                .glassEffect(.regular, in: pillShape)
                                .environment(\.appearsActive, true)
                                .materialActiveAppearance(.active)
                                .overlay(
                                    pillShape.fill(
                                        LinearGradient(
                                            colors: [
                                                Color.black.opacity(0.40),
                                                Color.black.opacity(0.65)
                                            ],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                )
                        } else {
                            classicGlassBackground(pillShape)
                        }
                        #else
                        classicGlassBackground(pillShape)
                        #endif
                    } else {
                        pillShape.fill(Color.black)
                    }
                }
                .overlay(
                    pillShape.fill(
                        RadialGradient(
                            colors: [
                                music.accentColor.opacity(expanded ? 0.22 : 0.10),
                                Color.clear
                            ],
                            center: .topLeading,
                            startRadius: 8,
                            endRadius: 220
                        )
                    )
                )
                .overlay(
                    pillShape.strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(expanded ? 0.22 : 0.12),
                                music.accentColor.opacity(expanded ? 0.28 : 0.14),
                                Color.white.opacity(0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.8
                    )
                )
            } else {
                let notchShape = NotchAttachedShape(topShoulder: shoulder, bottomRadius: bottom)
                Group {
                    if usesGlass {
                        #if compiler(>=6.2)
                        if #available(macOS 26.0, *) {
                            Color.clear
                                .glassEffect(.regular, in: notchShape)
                                .environment(\.appearsActive, true)
                                .materialActiveAppearance(.active)
                                .overlay(
                                    notchShape.fill(
                                        LinearGradient(
                                            stops: [
                                                Gradient.Stop(color: Color.black, location: 0),
                                                Gradient.Stop(color: Color.black.opacity(0.92), location: 0.22),
                                                Gradient.Stop(color: Color.black.opacity(0.45), location: 1.0)
                                            ],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                )
                        } else {
                            classicGlassBackground(notchShape)
                        }
                        #else
                        classicGlassBackground(notchShape)
                        #endif
                    } else {
                        notchShape.fill(Color.black)
                    }
                }
                .overlay(
                    notchShape.fill(
                        RadialGradient(
                            colors: [
                                music.accentColor.opacity(expanded ? 0.22 : 0.10),
                                Color.clear
                            ],
                            center: .topLeading,
                            startRadius: 8,
                            endRadius: 220
                        )
                    )
                )
                .overlay(
                    notchShape.stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(expanded ? 0.22 : 0.12),
                                music.accentColor.opacity(expanded ? 0.28 : 0.14),
                                Color.white.opacity(0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.8
                    )
                )
            }

            if let notice = notices.current, !expanded {
                deviceNotice(notice, size: size, isPill: isPill, geo: geo)
            } else if expanded {
                expandedContent
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            } else {
                compactContent(size: size, isPill: isPill, geo: geo)
                    .transition(.opacity)
            }
        }
        .clipShape(
            isPill
                ? AnyShape(RoundedRectangle(cornerRadius: pillRadius, style: .continuous))
                : AnyShape(NotchAttachedShape(topShoulder: shoulder, bottomRadius: bottom))
        )
        .contentShape(
            isPill
                ? AnyShape(RoundedRectangle(cornerRadius: pillRadius, style: .continuous))
                : AnyShape(NotchAttachedShape(topShoulder: shoulder, bottomRadius: bottom))
        )
        .onTapGesture {
            guard !controller.isExpanded, music.track?.isPlaying == true else { return }
            controller.expand(Pinned: true)
        }
    }

    @ViewBuilder
    private func classicGlassBackground<S: Shape>(_ shape: S) -> some View {
        ZStack {
            // macOS 14–15 fallback is deliberately static: no continuously sampled
            // desktop blur, keeping the expanded island inexpensive on older GPUs.
            shape.fill(
                LinearGradient(
                    stops: [
                        .init(color: Color.black.opacity(0.45), location: 0.0),
                        .init(color: Color.black.opacity(0.62), location: 0.35),
                        .init(color: Color.black.opacity(0.78), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            shape.fill(
                LinearGradient(
                    stops: [
                        .init(color: Color.white.opacity(0.32), location: 0.0),
                        .init(color: Color.white.opacity(0.12), location: 0.12),
                        .init(color: Color.white.opacity(0.02), location: 0.32),
                        .init(color: Color.clear, location: 0.58)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            shape.stroke(
                LinearGradient(
                    stops: [
                        .init(color: Color.white.opacity(0.46), location: 0.0),
                        .init(color: Color.white.opacity(0.18), location: 0.30),
                        .init(color: Color.white.opacity(0.06), location: 0.70),
                        .init(color: Color.white.opacity(0.20), location: 1.0)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 0.9
            )
        }
    }

    // MARK: - Trạng thái Thu gọn (Compact)

    private func deviceNotice(_ notice: IslandDeviceNotice, size: CGSize, isPill: Bool,
                              geo: ScreenGeometry) -> some View {
        DeviceNoticeView(notice: notice, size: size, geometry: geo, isPill: isPill)
            .id(notice.id)
    }

    @ViewBuilder
    private func compactContent(size: CGSize, isPill: Bool, geo: ScreenGeometry) -> some View {
        if isPill {
            let baseTrack = PetEngine.track(
                stripWidth: size.width,
                stripHeight: size.height,
                wing: 0,
                cameraWidth: 0,
                floats: true,
                bodyHeight: size.height
            )
            let track: PetTrack = {
                var adjusted = baseTrack
                let edgeInset = max(6, adjusted.size * 0.72)
                adjusted.rest = pet.side == .left ? edgeInset : size.width - edgeInset
                adjusted.mirrored = pet.side == .right
                return adjusted
            }()

            ZStack {
                if let playingTrack = music.track, playingTrack.isPlaying, !pet.hasActivePresentation {
                    let coverSize: CGFloat = max(14, size.height - 6)
                    HStack(spacing: 8) {
                        AlbumArtView(artwork: music.artwork, size: coverSize, isCircle: true)

                        Spacer(minLength: 0)

                        if showVisualizer {
                            EqualizerBars(
                                isPlaying: true,
                                bars: 7,
                                barWidth: 1.8,
                                height: 14,
                                tint: music.accentColor
                            )
                        } else {
                            Image(systemName: "music.note")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(music.accentColor)
                        }
                    }
                    .padding(.horizontal, 6)
                } else if pet.isEnabled {
                    PetTrackView(
                        look: pet.look,
                        track: track,
                        rests: true,
                        visit: pet.currentVisit,
                        mood: pet.mood,
                        reaction: pet.currentReaction,
                        awake: pet.isEnabled,
                        yieldsToActivities: !pet.hasActivePresentation
                    )
                    .frame(width: size.width, height: size.height)
                }

                if let cue = pet.currentStatusCue {
                    petStatusCue(cue, size: size, isPill: true, geo: geo)
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))
                }

            }
            .frame(width: size.width, height: size.height)
        } else {
            let shoulder = geo.shoulderRadius.shoulder
            let innerPadding: CGFloat = 5.0
            let wingWidth = geo.compactNotchWingWidth

            let track = PetEngine.track(
                stripWidth: size.width,
                stripHeight: size.height,
                wing: wingWidth,
                cameraWidth: geo.cameraWidth,
                floats: false,
                bodyHeight: size.height,
                side: pet.side
            )

            ZStack {
                if let playingTrack = music.track, playingTrack.isPlaying, !pet.hasActivePresentation {
                    HStack(spacing: 0) {
                        HStack(spacing: 0) {
                            AlbumArtView(artwork: music.artwork, size: 20, cornerRadius: 5.5)
                            Spacer(minLength: 0)
                        }
                        .padding(.leading, shoulder + innerPadding)
                        .frame(width: wingWidth, height: size.height)

                        if geo.isNotched {
                            Spacer().frame(width: geo.cameraWidth)
                        } else {
                            VStack(spacing: 1) {
                                Text(playingTrack.title)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                if !playingTrack.artist.isEmpty && playingTrack.artist != "SenseBar Audio" {
                                    Text(playingTrack.artist)
                                        .font(.system(size: 9.5, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.65))
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                }
                            }
                            .padding(.horizontal, 8)
                            .frame(width: geo.cameraWidth)
                            .clipped()
                        }

                        HStack(spacing: 0) {
                            Spacer(minLength: 0)
                            if showVisualizer {
                                EqualizerBars(
                                    isPlaying: true,
                                    bars: 7,
                                    barWidth: 1.8,
                                    height: 14,
                                    tint: music.accentColor
                                )
                            } else {
                                Image(systemName: "music.note")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(music.accentColor)
                            }
                        }
                        .padding(.trailing, shoulder + innerPadding)
                        .frame(width: wingWidth, height: size.height)
                    }
                } else if pet.isEnabled {
                    PetTrackView(
                        look: pet.look,
                        track: track,
                        rests: true,
                        visit: pet.currentVisit,
                        mood: pet.mood,
                        reaction: pet.currentReaction,
                        awake: pet.isEnabled,
                        yieldsToActivities: !pet.hasActivePresentation
                    )
                    .frame(width: size.width, height: size.height)
                }

                if let cue = pet.currentStatusCue {
                    petStatusCue(cue, size: size, isPill: false, geo: geo)
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))
                }

            }
            .frame(width: size.width, height: size.height)
        }
    }

    @ViewBuilder
    private func petStatusCue(_ cue: PetStatusCue, size: CGSize, isPill: Bool,
                              geo: ScreenGeometry) -> some View {
        let label = Label(statusTitle(cue), systemImage: cue.symbol)
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.white.opacity(0.12), in: Capsule())

        if isPill || !geo.isNotched {
            label.frame(width: size.width, height: size.height, alignment: .center)
        } else {
            let wing = geo.compactNotchWingWidth
            HStack(spacing: 0) {
                if pet.side == .left {
                    Spacer().frame(width: wing + geo.cameraWidth)
                    label.frame(width: wing)
                } else {
                    label.frame(width: wing)
                    Spacer().frame(width: geo.cameraWidth + wing)
                }
            }
            .frame(width: size.width, height: size.height)
        }
    }

    private func statusTitle(_ cue: PetStatusCue) -> String {
        switch cue {
        case .greeting: l10n.string(vi: "Xin chào", en: "Hello")
        case .downloaded: l10n.string(vi: "Tải xong", en: "Downloaded")
        case .lowBattery: l10n.string(vi: "Pin yếu", en: "Low battery")
        case .charging: l10n.string(vi: "Đang sạc", en: "Charging")
        case .downloadError: l10n.string(vi: "Tải lỗi", en: "Download error")
        case .dancing: l10n.string(vi: "Quẩy nhạc", en: "Dance")
        case .love: l10n.string(vi: "Yêu bạn", en: "Love")
        case .sleeping: l10n.string(vi: "Ngủ ngon", en: "Sleeping")
        case .muted: l10n.string(vi: "Đã tắt mic", en: "Mic muted")
        case .ready: l10n.string(vi: "Sẵn sàng", en: "Ready")
        }
    }

    // MARK: - Trạng thái Mở rộng (Expanded)

    @ViewBuilder
    private var expandedContent: some View {
        if let track = music.track {
            VStack(spacing: 10) {
                // Hàng trên cùng: Trạng thái phát & Nút thu gọn
                HStack(spacing: 0) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(track.isPlaying ? Color.green : Color.white.opacity(0.35))
                            .frame(width: 6, height: 6)
                        Text(track.appName)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.82))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer()
                        .frame(width: isPillMode ? 24 : controller.cameraCutoutWidth)

                    HStack(spacing: 8) {
                        if showVisualizer {
                            EqualizerBars(
                                isPlaying: track.isPlaying,
                                bars: 7,
                                barWidth: 2.2,
                                height: 14,
                                tint: music.accentColor
                            )
                        }
                        Button {
                            controller.collapse()
                        } label: {
                            Image(systemName: "chevron.up.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.white.opacity(0.55))
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .frame(height: max(26, controller.cameraCutoutHeight - 4))
                .padding(.horizontal, 22)

                // Nội dung: Ảnh bìa, thông tin bài hát và thanh tiến trình
                HStack(spacing: 14) {
                    Button {
                        music.openPlayerApp()
                    } label: {
                        AlbumArtView(artwork: music.artwork, size: 64, cornerRadius: 14)
                            .shadow(color: music.accentColor.opacity(0.42), radius: 10, y: 4)
                    }
                    .buttonStyle(.plain)
                    .help(l10n.string(vi: "Mở ứng dụng phát nhạc", en: "Open music player app"))

                    VStack(alignment: .leading, spacing: 6) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.title)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                                .lineLimit(1)

                            Text(track.artist.isEmpty ? track.album : track.artist)
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(.white.opacity(0.65))
                                .lineLimit(1)
                        }

                        // Thanh tiến trình
                        VStack(spacing: 3) {
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule(style: .continuous)
                                        .fill(Color.white.opacity(0.16))
                                        .frame(height: 4)

                                    Capsule(style: .continuous)
                                        .fill(music.accentColor)
                                        .frame(width: max(4, geo.size.width * track.progress), height: 4)
                                }
                                .frame(height: 8)
                                .contentShape(Rectangle())
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onEnded { value in
                                            let ratio = min(1, max(0, value.location.x / max(1, geo.size.width)))
                                            music.seek(to: track.duration * ratio)
                                        }
                                )
                            }
                            .frame(height: 8)

                            HStack {
                                Text(NowPlayingTrack.formattedTime(track.elapsed))
                                Spacer()
                                Text(NowPlayingTrack.formattedTime(track.duration))
                            }
                            .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.5))
                        }
                    }
                }
                .padding(.horizontal, 22)

                // Phím điều khiển phát nhạc và âm lượng
                HStack(spacing: 18) {
                    Button {
                        music.openPlayerApp()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.forward.app.fill")
                                .font(.system(size: 10.5))
                            Text(l10n.string(vi: "Mở App", en: "Open App"))
                                .font(.system(size: 10.5, weight: .semibold))
                        }
                        .foregroundStyle(.white.opacity(0.75))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.white.opacity(0.10)))
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button {
                        music.previousTrack()
                    } label: {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.88))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .disabled(!track.supportsTransportControls)
                    .opacity(track.supportsTransportControls ? 1 : 0.35)

                    Button {
                        music.togglePlayPause()
                    } label: {
                        Image(systemName: track.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Color.white))
                    }
                    .buttonStyle(.plain)
                    .disabled(!track.supportsTransportControls)
                    .opacity(track.supportsTransportControls ? 1 : 0.35)

                    Button {
                        music.nextTrack()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.88))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .disabled(!track.supportsTransportControls)
                    .opacity(track.supportsTransportControls ? 1 : 0.35)

                    Spacer()

                    Button {
                        audio.toggleMasterMute()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: audio.isMasterMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .font(.system(size: 10.5))
                                .foregroundStyle(audio.isMasterMuted ? .red : music.accentColor)
                            Text("\(Int((audio.isMasterMuted ? 0 : audio.masterVolume) * 100))%")
                                .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                                .foregroundStyle(.white.opacity(0.78))
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.white.opacity(0.10)))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 12)
            }
        }
    }
}
