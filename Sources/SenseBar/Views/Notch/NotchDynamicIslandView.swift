import AppKit
import SwiftUI

// MARK: - Hình dáng Tai thỏ có vai bo cong mượt (NotchAttachedShape)

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

// MARK: - Giao diện Dynamic Island chính trên thanh Menu Bar / Tai thỏ

struct NotchDynamicIslandView: View {
    @ObservedObject var controller: NotchDynamicIslandController
    var displayID: CGDirectDisplayID? = nil
    var isMirror: Bool = false
    @ObservedObject var music = NotchMusicService.shared
    @ObservedObject var audio = AudioStudioService.shared
    @ObservedObject var l10n = L10n.shared

    @AppStorage(DefaultsKey.notchStyle) private var notchStyle: String = "notch"
    @AppStorage(DefaultsKey.notchShowVisualizer) private var showVisualizer: Bool = true
    @AppStorage(DefaultsKey.notchCapsuleFitDrop) private var capsuleFitDrop: Double = 0
    @AppStorage(DefaultsKey.liquidGlassIslandEnabled) private var liquidGlassIsland: Bool = true
    @AppStorage(DefaultsKey.notchExpandAllDisplays) private var expandAllDisplays: Bool = false

    /// Màn hình có tai thỏ vật lý luôn dùng Notch, Capsule chỉ dành cho màn hình không tai thỏ.
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

    private var geo: SenseScreenGeometry {
        SenseScreenGeometry(for: assignedScreen)
    }

    private var islandSize: CGSize {
        controller.islandSize(for: assignedScreen, expanded: isViewExpanded)
    }

    private var activeTrack: NowPlayingTrack {
        music.track ?? NowPlayingTrack(
            title: l10n.string(vi: "Chưa phát nhạc", en: "Not Playing"),
            artist: l10n.string(vi: "Mở Apple Music, Spotify hoặc trình duyệt để phát", en: "Play music in Apple Music, Spotify, or browser"),
            album: "SenseBar Audio",
            duration: 215,
            elapsed: 0,
            isPlaying: false,
            appName: "SenseBar",
            bundleID: "com.apple.Music",
            pid: 0
        )
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
                .padding(.top, topOffset)
                .animation(.spring(response: 0.34, dampingFraction: 0.82), value: isViewExpanded)
                .animation(.spring(response: 0.34, dampingFraction: 0.82), value: music.track != nil)
                .animation(.spring(response: 0.32, dampingFraction: 0.84), value: isPill)
        }
        .frame(width: NotchDynamicIslandController.canvasWidth, height: NotchDynamicIslandController.canvasHeight, alignment: .top)
    }

    @ViewBuilder
    private func islandContainer(size: CGSize, isPill: Bool, geo: SenseScreenGeometry) -> some View {
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

            if expanded {
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
            if !controller.isExpanded {
                controller.expand(Pinned: true)
            }
        }
    }

    @ViewBuilder
    private func classicGlassBackground<S: Shape>(_ shape: S) -> some View {
        ZStack {
            // Hiệu ứng kính mờ cho macOS 14/15 và máy Intel
            NotchTranslucentMaterial(cornerRadius: 24)

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

            // Vệt phản chiếu ánh sáng mép trên
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

            // Viền khúc xạ vát cạnh
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

    // MARK: - Trạng thái Thu gọn (Compact Wings & Capsule)

    @ViewBuilder
    private func compactContent(size: CGSize, isPill: Bool, geo: SenseScreenGeometry) -> some View {
        if isPill {
            // Capsule nổi trong Menu Bar: ảnh bìa tròn cách đều trên/dưới ~3.5pt
            let coverSize: CGFloat = max(12, size.height - 7)
            HStack(spacing: 7) {
                AlbumArtView(artwork: music.artwork, size: coverSize, isCircle: true)

                // Tên bài hát đang phát
                Text(activeTrack.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer(minLength: 4)

                // Cột sóng nhạc mini
                if showVisualizer {
                    SenseEqualizerBars(
                        isPlaying: activeTrack.isPlaying,
                        bars: 4,
                        barWidth: 1.8,
                        height: max(8, size.height - 13),
                        tint: music.accentColor
                    )
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(music.accentColor)
                }
            }
            .padding(.leading, 5)
            .padding(.trailing, 8)
            .offset(y: -1.0) // Bù ascent của font SF để nội dung cân giữa theo mắt nhìn
            .frame(width: size.width, height: size.height)
        } else {
            // Hiển thị ôm sát phần cứng Tai thỏ (Notch Wings)
            // Lưu ý: NotchAttachedShape có phần vai loe ở đỉnh (0 ..< shoulder = 12pt),
            // vách đứng màu đen thực tế bắt đầu từ x = shoulder (12pt).
            // Do đó để có đúng 12pt padding tính từ vách đen, lề tính từ mép khung là shoulder + 12pt.
            let shoulder = geo.shoulderRadius.shoulder
            let innerPadding: CGFloat = 5.0
            let centerGap = geo.isNotched ? geo.cameraWidth : 160.0
            let wingWidth = max(40, (size.width - centerGap) / 2)
            HStack(spacing: 0) {
                // Cánh trái: cách vách đứng trái 12pt + chứa vừa ảnh bìa 20pt
                HStack(spacing: 0) {
                    AlbumArtView(artwork: music.artwork, size: 20, cornerRadius: 5.5)
                    Spacer(minLength: 0)
                }
                .padding(.leading, shoulder + innerPadding)
                .frame(width: wingWidth, height: size.height)

                // Khoảng trống camera tai thỏ ở giữa
                if geo.isNotched {
                    // Màn hình có tai thỏ vật lý: để khoảng trống không che mắt camera
                    Spacer()
                        .frame(width: geo.cameraWidth)
                } else {
                    // Màn hình không có tai thỏ vật lý: hiển thị tên bài hát / trạng thái ở giữa
                    VStack(spacing: 1) {
                        Text(activeTrack.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        if !activeTrack.artist.isEmpty && activeTrack.artist != "SenseBar Audio" {
                            Text(activeTrack.artist)
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundStyle(.white.opacity(0.65))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                // Cánh phải: chứa vừa sóng nhạc 5 cột + cách vách đứng phải 12pt
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    if showVisualizer && activeTrack.isPlaying {
                        SenseEqualizerBars(
                            isPlaying: true,
                            bars: 5,
                            barWidth: 2.2,
                            height: 12,
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
            .frame(width: size.width, height: size.height)
        }
    }

    // MARK: - Trạng thái Mở rộng (Expanded Music Studio trên Tai thỏ)

    private var expandedContent: some View {
        VStack(spacing: 10) {
            // Hàng trên cùng nằm hai bên tai thỏ
            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(activeTrack.isPlaying ? Color.green : Color.white.opacity(0.35))
                        .frame(width: 6, height: 6)
                    Text(activeTrack.appName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()
                    .frame(width: isPillMode ? 24 : controller.cameraCutoutWidth)

                HStack(spacing: 8) {
                    if showVisualizer {
                        SenseEqualizerBars(
                            isPlaying: activeTrack.isPlaying,
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

            // Thân chính: Ảnh đĩa + Tên bài hát + Thanh tua + Nút điều khiển
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
                        Text(activeTrack.title)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        Text(activeTrack.artist.isEmpty ? activeTrack.album : activeTrack.artist)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.65))
                            .lineLimit(1)
                    }

                    // Thanh tiến trình (Timeline)
                    VStack(spacing: 3) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule(style: .continuous)
                                    .fill(Color.white.opacity(0.16))
                                    .frame(height: 4)

                                Capsule(style: .continuous)
                                    .fill(music.accentColor)
                                    .frame(width: max(4, geo.size.width * activeTrack.progress), height: 4)
                            }
                            .frame(height: 8)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onEnded { value in
                                        let ratio = min(1, max(0, value.location.x / max(1, geo.size.width)))
                                        music.seek(to: activeTrack.duration * ratio)
                                    }
                            )
                        }
                        .frame(height: 8)

                        HStack {
                            Text(NowPlayingTrack.formattedTime(activeTrack.elapsed))
                            Spacer()
                            Text(NowPlayingTrack.formattedTime(activeTrack.duration))
                        }
                        .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
            .padding(.horizontal, 22)

            // Cụm nút điều khiển phát nhạc & âm lượng nhanh
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

                Button {
                    music.togglePlayPause()
                } label: {
                    Image(systemName: activeTrack.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.white))
                }
                .buttonStyle(.plain)

                Button {
                    music.nextTrack()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.88))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)

                Spacer()

                // Nút bật/tắt tiếng nhanh ngay trên Dynamic Island
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

