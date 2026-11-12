import AppKit
import SwiftUI

/// Thẻ minh họa Dynamic Island có hoạt ảnh rê chuột mở rộng trong menu chính.
struct IslandPreviewCard: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var music = MusicService.shared
    @ObservedObject private var islandController = IslandController.shared
    @AppStorage(DefaultsKey.notchStyle) private var notchStyle: String = "notch"
    @AppStorage(DefaultsKey.notchShowVisualizer) private var showVisualizer: Bool = true

    /// Capsule chỉ có hiệu lực khi có màn hình không tai thỏ, ngược lại luôn là Notch.
    private var showsCapsule: Bool {
        notchStyle == "pill" && islandController.canChooseStyle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(
                    l10n.string(vi: "Minh họa Dynamic Island", en: "Dynamic Island Example"),
                    systemImage: "eye.fill"
                )
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.secondary)

                Spacer()

                Text(showsCapsule
                     ? l10n.string(vi: "Kiểu Viên nang", en: "Pill Style")
                     : l10n.string(vi: "Kiểu Tai thỏ", en: "Notch Style"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.blue.opacity(0.10)))
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.blue.opacity(0.28), lineWidth: 0.8)
                    )
            }

            // Hình ảnh Example mô phỏng trực tiếp thanh Menu Bar & Tai thỏ MacBook (tối ưu 15fps khi mở popover)
            TimelineView(.animation(minimumInterval: 1.0 / 15.0)) { timeline in
                let cycle = timeline.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 4.2) / 4.2
                let exp = previewExpansionProgress(for: cycle)
                let isPill = showsCapsule
                let compactW: CGFloat = isPill ? 56 : 148
                let compactH: CGFloat = isPill ? 18 : 22
                let expandedW: CGFloat = 248
                let expandedH: CGFloat = 62
                let currentW = compactW + (expandedW - compactW) * exp
                let currentH = compactH + (expandedH - compactH) * exp
                let cursorPt = previewCursorPoint(for: cycle)

                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.13, green: 0.16, blue: 0.24),
                                    Color(red: 0.08, green: 0.10, blue: 0.16)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    // Thanh Menu Bar giả lập
                    HStack {
                        HStack(spacing: 4) {
                            Image(systemName: "apple.logo")
                                .font(.system(size: 8.5, weight: .bold))
                            Text("SenseBar")
                                .font(.system(size: 8.5, weight: .semibold))
                        }
                        .foregroundStyle(.white.opacity(0.78))

                        Spacer()

                        HStack(spacing: 5) {
                            Image(systemName: "wifi")
                                .font(.system(size: 8))
                            Text("9:41")
                                .font(.system(size: 8.5, weight: .medium))
                        }
                        .foregroundStyle(.white.opacity(0.78))
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 22)
                    .background(Color.white.opacity(0.07))

                    // Island tự động biến hình từ Thu gọn -> Mở rộng khi con trỏ chạm vào
                    ZStack(alignment: .top) {
                        Group {
                            if isPill {
                                RoundedRectangle(cornerRadius: compactH / 2 + (14 - compactH / 2) * exp, style: .continuous)
                                    .fill(Color.black)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: compactH / 2 + (14 - compactH / 2) * exp, style: .continuous)
                                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.6)
                                    )
                            } else {
                                NotchAttachedShape(topShoulder: 7 + 3 * exp, bottomRadius: 8 + 6 * exp)
                                    .fill(Color.black)
                                    .overlay(
                                        NotchAttachedShape(topShoulder: 7 + 3 * exp, bottomRadius: 8 + 6 * exp)
                                            .stroke(Color.white.opacity(0.16), lineWidth: 0.6)
                                    )
                            }
                        }

                        if exp < 0.45 {
                            Group {
                                if isPill {
                                    HStack(spacing: 5) {
                                        AlbumArtView(artwork: music.artwork, size: 12, isCircle: true)
                                        Spacer(minLength: 2)
                                        if showVisualizer {
                                            EqualizerBars(
                                                isPlaying: true,
                                                bars: 7,
                                                barWidth: 1.4,
                                                height: 8.5,
                                                tint: music.accentColor
                                            )
                                        } else {
                                            Image(systemName: "music.note")
                                                .font(.system(size: 7.5, weight: .semibold))
                                                .foregroundStyle(music.accentColor)
                                        }
                                    }
                                    .padding(.horizontal, 4.5)
                                } else {
                                    HStack(spacing: 0) {
                                        AlbumArtView(artwork: music.artwork, size: 13, cornerRadius: 3.8)
                                            .padding(.leading, 13)
                                        Spacer()
                                        Circle()
                                            .fill(Color(red: 0.12, green: 0.15, blue: 0.22))
                                            .frame(width: 5.5, height: 5.5)
                                            .overlay(
                                                Circle()
                                                    .fill(Color.cyan.opacity(0.45))
                                                    .frame(width: 2, height: 2)
                                            )
                                        Spacer()
                                        Group {
                                            if showVisualizer {
                                                EqualizerBars(
                                                    isPlaying: true,
                                                    bars: 5,
                                                    barWidth: 1.5,
                                                    height: 9,
                                                    tint: music.accentColor
                                                )
                                            } else {
                                                Image(systemName: "music.note")
                                                    .font(.system(size: 8, weight: .semibold))
                                                    .foregroundStyle(music.accentColor)
                                            }
                                        }
                                        .padding(.trailing, 13)
                                    }
                                }
                            }
                            .frame(width: compactW, height: compactH)
                            .opacity(Double(max(0, 1.0 - exp * 2.4)))
                        }

                        if exp > 0.22 {
                            VStack(spacing: 5) {
                                HStack(spacing: 0) {
                                    HStack(spacing: 4) {
                                        Circle().fill(Color.green).frame(width: 4.5, height: 4.5)
                                        Text(music.track?.appName ?? "Apple Music")
                                            .font(.system(size: 7.5, weight: .semibold))
                                            .foregroundStyle(.white.opacity(0.78))
                                    }
                                    Spacer()
                                    if showVisualizer {
                                        EqualizerBars(
                                            isPlaying: true,
                                            bars: 5,
                                            barWidth: 1.4,
                                            height: 8,
                                            tint: music.accentColor
                                        )
                                    }
                                }

                                HStack(spacing: 8) {
                                    AlbumArtView(artwork: music.artwork, size: 28, cornerRadius: 6)

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(music.track?.title ?? "Midnight City — M83")
                                            .font(.system(size: 9.5, weight: .bold))
                                            .foregroundStyle(.white)
                                            .lineLimit(1)
                                        Capsule()
                                            .fill(Color.white.opacity(0.22))
                                            .frame(width: 92, height: 3)
                                            .overlay(alignment: .leading) {
                                                Capsule()
                                                    .fill(music.accentColor)
                                                    .frame(width: 56, height: 3)
                                            }
                                    }

                                    Spacer()

                                    HStack(spacing: 6) {
                                        Image(systemName: "backward.fill")
                                            .font(.system(size: 8.5))
                                        Image(systemName: "pause.circle.fill")
                                            .font(.system(size: 14))
                                        Image(systemName: "forward.fill")
                                            .font(.system(size: 8.5))
                                    }
                                    .foregroundStyle(.white.opacity(0.92))
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .frame(width: expandedW, height: expandedH)
                            .opacity(Double(min(1, (exp - 0.22) / 0.45)))
                        }
                    }
                    .frame(width: currentW, height: currentH)
                    .padding(.top, isPill ? 2 : 0)

                    // Con trỏ chuột minh họa trỏ vào Notch / Capsule
                    Image(systemName: "cursorarrow")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.65), radius: 2, x: 0.5, y: 1)
                        .position(x: cursorPt.x, y: cursorPt.y)
                }
                .frame(height: 86)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
        }
        .panelCard()
    }

    private func previewExpansionProgress(for cycle: Double) -> CGFloat {
        if cycle < 0.22 {
            return 0
        } else if cycle < 0.34 {
            let t = (cycle - 0.22) / 0.12
            return CGFloat(t * t * (3.0 - 2.0 * t))
        } else if cycle < 0.72 {
            return 1
        } else if cycle < 0.84 {
            let t = (cycle - 0.72) / 0.12
            return CGFloat(1.0 - t * t * (3.0 - 2.0 * t))
        } else {
            return 0
        }
    }

    private func previewCursorPoint(for cycle: Double) -> CGPoint {
        let start = CGPoint(x: 266, y: 72)
        let targetCompact = CGPoint(x: 186, y: 14)
        let targetExpanded = CGPoint(x: 198, y: 42)
        if cycle < 0.22 {
            let t = cycle / 0.22
            let s = CGFloat(t * t * (3.0 - 2.0 * t))
            return CGPoint(x: start.x + (targetCompact.x - start.x) * s, y: start.y + (targetCompact.y - start.y) * s)
        } else if cycle < 0.36 {
            let t = (cycle - 0.22) / 0.14
            let s = CGFloat(t * t * (3.0 - 2.0 * t))
            return CGPoint(x: targetCompact.x + (targetExpanded.x - targetCompact.x) * s, y: targetCompact.y + (targetExpanded.y - targetCompact.y) * s)
        } else if cycle < 0.72 {
            return targetExpanded
        } else if cycle < 0.86 {
            let t = (cycle - 0.72) / 0.14
            let s = CGFloat(t * t * (3.0 - 2.0 * t))
            return CGPoint(x: targetExpanded.x + (start.x - targetExpanded.x) * s, y: targetExpanded.y + (start.y - targetExpanded.y) * s)
        } else {
            return start
        }
    }
}
