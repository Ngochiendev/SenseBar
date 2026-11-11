import AppKit
import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

// MARK: - NotchAttachedShape (y hệt trong NotchDynamicIslandView.swift)

struct NotchAttachedShape: Shape {
    var topShoulder: CGFloat
    var bottomRadius: CGFloat

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

// MARK: - Sóng nhạc từng frame (y hệt SenseEqualizerBars)

struct FrameEqualizerBars: View {
    let bars: Int
    let barWidth: CGFloat
    let height: CGFloat
    let phase: Double
    let tint: Color

    var body: some View {
        HStack(alignment: .center, spacing: max(1.6, barWidth * 0.82)) {
            ForEach(0..<bars, id: \.self) { idx in
                let wave = (sin(phase * 6.2 + Double(idx) * 1.15) + 1.0) * 0.5
                let wave2 = (cos(phase * 4.5 - Double(idx) * 0.85) + 1.0) * 0.5
                let level = max(0.22, min(1.0, 0.25 + (wave * 0.5 + wave2 * 0.5) * 0.75))
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [tint, tint.opacity(0.68)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: barWidth, height: max(2.5, height * level))
            }
        }
        .frame(height: height)
    }
}

// MARK: - Copy nguyên bản 100% Minh họa trong MenuPanelView.swift

struct ExactPopoverIllustrationFrame: View {
    let isPill: Bool
    let cycle: Double // 0.0 ..< 1.0

    private let accentColor = Color(red: 0.44, green: 0.62, blue: 0.88)

    var body: some View {
        let exp = previewExpansionProgress(for: cycle)
        let compactW: CGFloat = isPill ? 162 : 148
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
                                previewAlbumBadge(size: 13, cornerRadius: 3.5)
                                HStack(spacing: 3) {
                                    Image(systemName: "headphones")
                                        .font(.system(size: 7.5, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.85))
                                    Text("Midnight City — M83")
                                        .font(.system(size: 8.5, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 3)
                                FrameEqualizerBars(
                                    bars: 4,
                                    barWidth: 1.5,
                                    height: 8.5,
                                    phase: cycle * .pi * 2,
                                    tint: accentColor
                                )
                            }
                            .padding(.horizontal, 6)
                        } else {
                            HStack(spacing: 0) {
                                previewAlbumBadge(size: 13, cornerRadius: 3.8)
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
                                FrameEqualizerBars(
                                    bars: 5,
                                    barWidth: 1.5,
                                    height: 9,
                                    phase: cycle * .pi * 2,
                                    tint: accentColor
                                )
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
                                Text("Google Chrome")
                                    .font(.system(size: 7.5, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.78))
                            }
                            Spacer()
                            FrameEqualizerBars(
                                bars: 5,
                                barWidth: 1.4,
                                height: 8,
                                phase: cycle * .pi * 2,
                                tint: accentColor
                            )
                        }

                        HStack(spacing: 8) {
                            previewAlbumBadge(size: 28, cornerRadius: 6)

                            VStack(alignment: .leading, spacing: 3) {
                                Text("Midnight City — M83")
                                    .font(.system(size: 9.5, weight: .bold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                Capsule()
                                    .fill(Color.white.opacity(0.22))
                                    .frame(width: 92, height: 3)
                                    .overlay(alignment: .leading) {
                                        Capsule()
                                            .fill(accentColor)
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
        .frame(width: 332, height: 86, alignment: .top)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    @ViewBuilder
    private func previewAlbumBadge(size: CGFloat, cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.24, green: 0.56, blue: 0.96),
                        Color(red: 0.52, green: 0.28, blue: 0.92)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.45, weight: .bold))
                    .foregroundStyle(.white)
            )
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

// MARK: - Xuất GIF bằng ImageIO

@MainActor
func exportGIF(isPill: Bool, outputURL: URL) throws {
    let totalFrames = 84
    let frameDelay: Double = 0.05 // 20 fps * 84 frames = 4.2s (đúng chu kỳ 4.2s của MenuPanelView)
    guard let destination = CGImageDestinationCreateWithURL(
        outputURL as CFURL,
        UTType.gif.identifier as CFString,
        totalFrames,
        nil
    ) else {
        throw NSError(domain: "MakePreviewGIFs", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot create GIF destination"])
    }

    let fileProps: [CFString: Any] = [
        kCGImagePropertyGIFDictionary: [
            kCGImagePropertyGIFLoopCount: 0
        ]
    ]
    CGImageDestinationSetProperties(destination, fileProps as CFDictionary)

    let frameProps: [CFString: Any] = [
        kCGImagePropertyGIFDictionary: [
            kCGImagePropertyGIFDelayTime: frameDelay,
            kCGImagePropertyGIFUnclampedDelayTime: frameDelay
        ]
    ]

    for i in 0..<totalFrames {
        let cycle = Double(i) / Double(totalFrames)
        let view = ExactPopoverIllustrationFrame(isPill: isPill, cycle: cycle)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0
        if let cgImage = renderer.cgImage {
            CGImageDestinationAddImage(destination, cgImage, frameProps as CFDictionary)
        }
    }

    if !CGImageDestinationFinalize(destination) {
        throw NSError(domain: "MakePreviewGIFs", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to finalize GIF"])
    }
}

let projectRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let assetsDir = projectRoot.appendingPathComponent("assets")
try FileManager.default.createDirectory(at: assetsDir, withIntermediateDirectories: true)

let notchURL = assetsDir.appendingPathComponent("dynamic-island-notch.gif")
let capsuleURL = assetsDir.appendingPathComponent("dynamic-island-capsule.gif")

MainActor.assumeIsolated {
    do {
        try exportGIF(isPill: false, outputURL: notchURL)
        print("✓ Exported \(notchURL.path)")
        try exportGIF(isPill: true, outputURL: capsuleURL)
        print("✓ Exported \(capsuleURL.path)")
    } catch {
        fputs("Error: \(error)\n", stderr)
        exit(1)
    }
}
