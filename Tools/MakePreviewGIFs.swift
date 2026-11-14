import AppKit
import SwiftUI
import ImageIO
import UniformTypeIdentifiers

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


private let accent = Color(red: 0.44, green: 0.62, blue: 0.88)

// Sample the same decorative envelope as EqualizerBars, at a fixed time per frame.
struct FrameBars: View {
    let time: Double
    var width: CGFloat = 1.8
    var body: some View {
        HStack(spacing: width * 0.85) {
            ForEach(0..<7) { i in
                let envelope = pow(1 - abs(Double(i) - 3) / 3, 1.5)
                let low = max(width, 14 * (0.14 + envelope * 0.25))
                let high = max(width, 14 * (0.14 + envelope * 0.88))
                let phase = (time + Double(i) * 0.17) / (.pi / (5.2 + Double(i) * 0.61))
                let travel = (1 - cos(.pi * phase)) / 2
                Capsule().fill(accent).frame(width: width, height: low + (high - low) * travel)
            }
        }.frame(height: 14)
    }
}

struct DemoFrame: View {
    let isPill: Bool
    let time: Double
    // Representative MacBook cutout and 24pt external-display menu bar.
    // ScreenGeometry measures these per display in the running application.
    private var compact: CGSize {
        CGSize(width: isPill ? 135 : ScreenGeometry.standardNotchWidth + 80,
               height: isPill ? 22 : ScreenGeometry.standardNotchHeight)
    }
    private var expansion: Double {
        if time < 1.48 { return 0 }
        if time < 4.66 { return spring(time - 1.48) }
        return 1 - spring(time - 4.66)
    }
    // IslandView: spring(response: 0.42, dampingFraction: 0.72).
    private func spring(_ t: Double) -> Double {
        let omega = 2 * Double.pi / 0.42
        let zeta = 0.72
        let damped = omega * sqrt(1 - zeta * zeta)
        return 1 - exp(-zeta * omega * t) * (cos(damped * t) + zeta * omega / damped * sin(damped * t))
    }
    private func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * expansion }
    private var expandedSize: CGSize { ScreenGeometry(for: NSScreen.main!).expandedSize }
    private var cursor: CGPoint {
        let outside = CGPoint(x: 455, y: 222)
        // Enter via a wing, never via the physical camera cutout.
        let inside = CGPoint(x: isPill ? 328 : 397, y: isPill ? 13 : 19)
        func interpolate(_ a: CGPoint, _ b: CGPoint, _ t: Double) -> CGPoint {
            let u = max(0, min(1, t)); let s = u * u * (3 - 2 * u)
            return CGPoint(x: a.x + (b.x - a.x) * s, y: a.y + (b.y - a.y) * s)
        }
        if time < 0.6 { return outside }
        if time < 1.4 { return interpolate(outside, inside, (time - 0.6) / 0.8) }
        if time < 4.1 { return inside }
        return interpolate(inside, outside, (time - 4.1) / 0.4)
    }
    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(red: 0.18, green: 0.25, blue: 0.38), Color(red: 0.08, green: 0.12, blue: 0.21)], startPoint: .topLeading, endPoint: .bottomTrailing)
            menuBar
            island
                .frame(width: mix(compact.width, expandedSize.width), height: mix(compact.height, expandedSize.height), alignment: .top)
                .padding(.top, isPill ? 1 : 0)
            // The physical cutout stays black, including while the UI expands.
            if !isPill {
                NotchAttachedShape(topShoulder: 12, bottomRadius: 10)
                    .fill(.black).frame(width: ScreenGeometry.standardNotchWidth, height: ScreenGeometry.standardNotchHeight)
            }
            Image(nsImage: NSCursor.arrow.image).resizable()
                .frame(width: NSCursor.arrow.image.size.width, height: NSCursor.arrow.image.size.height)
                .offset(x: NSCursor.arrow.image.size.width / 2 - NSCursor.arrow.hotSpot.x,
                        y: NSCursor.arrow.image.size.height / 2 - NSCursor.arrow.hotSpot.y)
                .position(cursor)
        }
        .frame(width: 560, height: 250)
        .clipped()
        .environment(\.colorScheme, .dark)
    }
    private var menuBar: some View {
        HStack(spacing: 16) {
            Image(systemName: "apple.logo")
            Text("Finder").fontWeight(.semibold)
            Text("File")
            Text("Edit")
            Spacer()
            Image(systemName: "wifi")
            Image(systemName: "battery.100percent")
            Text("9:41")
        }
        .font(.system(size: 12)).foregroundStyle(.white.opacity(0.88))
        .padding(.horizontal, 16).frame(height: isPill ? 24 : 32)
        .background(.white.opacity(0.07))
    }
    private var silhouette: AnyShape {
        isPill
            ? AnyShape(RoundedRectangle(cornerRadius: mix(11, 26), style: .continuous))
            : AnyShape(NotchAttachedShape(topShoulder: mix(12, 14), bottomRadius: mix(10, 24)))
    }
    private var island: some View {
        ZStack(alignment: .top) {
            silhouette.fill(.black)
            // Explicit static macOS 14–15 fallback from IslandView.
            // ImageRenderer cannot capture a live desktop Liquid Glass backdrop.
            silhouette.fill(LinearGradient(stops: [
                .init(color: .white.opacity(0.20), location: 0),
                .init(color: .white.opacity(0.06), location: 0.12),
                .init(color: .clear, location: 0.58)
            ], startPoint: .top, endPoint: .bottom)).opacity(max(0, expansion))
            silhouette.fill(RadialGradient(colors: [accent.opacity(mix(0.10, 0.22)), .clear], center: .topLeading, startRadius: 8, endRadius: 220))
            silhouette.stroke(LinearGradient(colors: [.white.opacity(mix(0.12, 0.22)), accent.opacity(mix(0.14, 0.28)), .white.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.8)
            compactContent.opacity(max(0, 1 - expansion * 3))
            expandedContent.opacity(max(0, min(1, (expansion - 0.4) / 0.6)))
        }.frame(width: mix(compact.width, expandedSize.width), height: mix(compact.height, expandedSize.height), alignment: .top)
        .clipShape(silhouette)
    }
    private var compactContent: some View {
        HStack(spacing: 0) {
            AlbumArtView(artwork: nil, size: isPill ? 16 : 20, isCircle: isPill, cornerRadius: 5.5)
            Spacer(minLength: 0)
            FrameBars(time: time)
        }
        .padding(.horizontal, isPill ? 6 : 17)
        .frame(width: compact.width, height: compact.height)
    }
    private var expandedContent: some View {
        VStack(spacing: 10) {
            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    Circle().fill(.green).frame(width: 6, height: 6)
                    Text("Music").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.82))
                }.frame(maxWidth: .infinity, alignment: .leading)
                Spacer().frame(width: isPill ? 24 : ScreenGeometry.standardNotchWidth)
                HStack(spacing: 8) {
                    FrameBars(time: time, width: 2.2)
                    HStack(spacing: 3) {
                        Image(systemName: "waveform.badge.magnifyingglass").font(.system(size: 10, weight: .semibold))
                        Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold))
                    }.foregroundStyle(.white.opacity(0.70))
                    Image(systemName: "chevron.up.circle.fill").font(.system(size: 14)).foregroundStyle(.white.opacity(0.55))
                }.frame(maxWidth: .infinity, alignment: .trailing)
            }.frame(height: 28)
            HStack(spacing: 14) {
                AlbumArtView(artwork: nil, size: 64, cornerRadius: 14)
                    .shadow(color: accent.opacity(0.42), radius: 10, y: 4)
                VStack(alignment: .leading, spacing: 6) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Midnight City").font(.system(size: 14, weight: .bold))
                        Text("M83").font(.system(size: 11.5, weight: .medium)).foregroundStyle(.white.opacity(0.65))
                    }
                    VStack(spacing: 3) {
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(.white.opacity(0.16)).frame(height: 4)
                                Capsule().fill(accent).frame(width: proxy.size.width * (83 + time) / 244, height: 4)
                            }.frame(height: 8)
                        }.frame(height: 8)
                        HStack {
                            Text("1:\(String(format: "%02d", 23 + Int(time)))")
                            Spacer()
                            Text("4:04")
                        }.font(.system(size: 9.5, weight: .medium).monospacedDigit()).foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
            HStack(spacing: 18) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.forward.app.fill").font(.system(size: 10.5))
                    Text("Open App").font(.system(size: 10.5, weight: .semibold))
                }.foregroundStyle(.white.opacity(0.75)).padding(.horizontal, 9).padding(.vertical, 5)
                    .background(Capsule().fill(.white.opacity(0.10)))
                Spacer(minLength: 0)
                Image(systemName: "backward.fill").font(.system(size: 14, weight: .semibold)).frame(width: 28, height: 28)
                Image(systemName: "pause.fill").font(.system(size: 14, weight: .bold)).foregroundStyle(.black)
                    .frame(width: 32, height: 32).background(Circle().fill(.white))
                Image(systemName: "forward.fill").font(.system(size: 14, weight: .semibold)).frame(width: 28, height: 28)
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    Image(systemName: "speaker.wave.2.fill").foregroundStyle(accent)
                    Text("65%")
                }.font(.system(size: 10.5, weight: .semibold)).padding(.horizontal, 9).padding(.vertical, 5)
                    .background(Capsule().fill(.white.opacity(0.10)))
            }.padding(.bottom, 12)
        }
        .padding(.horizontal, 22)
        .frame(width: expandedSize.width, height: expandedSize.height, alignment: .top)
    }
}

@main
struct MakePreviewGIFs {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let assets = URL(fileURLWithPath: "/tmp/sensebar-rendered-previews", isDirectory: true)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        for isPill in [false, true] {
            let url = assets.appendingPathComponent("dynamic-island-\(isPill ? "capsule" : "notch").gif")
            guard NSScreen.main != nil else {
                throw NSError(domain: "MakePreviewGIFs", code: 1, userInfo: [NSLocalizedDescriptionKey: "A macOS graphical session is required for rendering."])
            }
            let count = 120
            guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, count, nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
            CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
            for index in 0..<count {
                try autoreleasepool {
                    let renderer = ImageRenderer(content: DemoFrame(isPill: isPill, time: Double(index) * 0.05))
                    renderer.scale = 2
                    guard let frame = renderer.cgImage else { throw CocoaError(.fileReadUnknown) }
                    CGImageDestinationAddImage(destination, frame, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.05, kCGImagePropertyGIFUnclampedDelayTime: 0.05]] as CFDictionary)
                    if [0, 60].contains(index) {
                        let png = URL(fileURLWithPath: "/tmp/sensebar-\(isPill ? "capsule" : "notch")-\(index).png")
                        if let output = CGImageDestinationCreateWithURL(png as CFURL, UTType.png.identifier as CFString, 1, nil) {
                            CGImageDestinationAddImage(output, frame, nil)
                            CGImageDestinationFinalize(output)
                        }
                    }
                }
            }
            guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
            print("Exported \(url.path)")
        }
    }
}
