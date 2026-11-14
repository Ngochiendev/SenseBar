import AppKit
import SwiftUI

enum Theme {
    /// Nền vũ trụ sâu thẳm cho Hero Banner
    static let spaceGradient = LinearGradient(
        colors: [
            Color(red: 0.06, green: 0.07, blue: 0.14),
            Color(red: 0.11, green: 0.09, blue: 0.22),
            Color(red: 0.07, green: 0.12, blue: 0.24)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Màu nhấn riêng cho từng biểu tượng danh mục
    static func iconColor(for symbol: String) -> Color {
        let s = symbol.lowercased()
        if s.contains("speaker") || s.contains("waveform") || s.contains("music") {
            return Color(red: 0.00, green: 0.68, blue: 0.92) // Sonic Cyan
        }
        if s.contains("macbook") || s.contains("rectangle") || s.contains("sparkles") {
            return Color(red: 0.46, green: 0.34, blue: 0.94) // Island Violet
        }
        return Color(red: 0.38, green: 0.44, blue: 0.92) // Studio Indigo
    }
}

// MARK: - PanelSurface & Glass Card Modifiers (Dùng cho Menu Bar Popover)

enum PanelSurface {
    static func cardFill(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color.white : Color.white.opacity(0.075)
    }

    static func border(for scheme: ColorScheme) -> Color {
        let raised = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        return scheme == .light
            ? Color.black.opacity(raised ? 0.24 : 0.09)
            : Color.white.opacity(raised ? 0.28 : 0.11)
    }
}

extension View {
    func panelCard(padded: Bool = true) -> some View {
        modifier(PanelCardModifier(padded: padded))
    }
}

private struct PanelCardModifier: ViewModifier {
    var padded = true
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage(DefaultsKey.liquidGlassEnabled) private var liquidGlassEnabled: Bool = true

    func body(content: Content) -> some View {
        let isLight = colorScheme == .light
        let shape = RoundedRectangle(cornerRadius: 13, style: .continuous)

        content
            .padding(padded ? 12 : 0)
            .background {
                if isLight || !liquidGlassEnabled || reduceTransparency {
                    shape.fill(PanelSurface.cardFill(for: colorScheme))
                } else {
                    panelSurface(shape: shape, isLight: isLight)
                }
            }
            .overlay(
                shape.strokeBorder(
                    liquidGlassEnabled
                        ? LinearGradient(
                            stops: [
                                .init(color: (isLight ? Color.black : Color.white).opacity(isLight ? 0.16 : 0.22), location: 0.0),
                                .init(color: (isLight ? Color.black : Color.white).opacity(isLight ? 0.05 : 0.06), location: 0.60),
                                .init(color: (isLight ? Color.black : Color.white).opacity(isLight ? 0.10 : 0.14), location: 1.0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        : LinearGradient(colors: [PanelSurface.border(for: colorScheme)], startPoint: .top, endPoint: .bottom),
                    lineWidth: 0.85
                )
            )
    }

    @ViewBuilder
    private func panelSurface(shape: RoundedRectangle, isLight: Bool) -> some View {
        ZStack {
            #if compiler(>=6.2)
            if #available(macOS 26.0, *) {
                Color.clear.glassEffect(.regular, in: shape)
            } else {
                shape.fill(PanelSurface.cardFill(for: colorScheme))
            }
            #else
            shape.fill(PanelSurface.cardFill(for: colorScheme))
            #endif

            // Static tonal layers preserve depth on older Macs without a live blur pass.
            shape.fill(
                LinearGradient(
                    stops: [
                        .init(color: Color.white.opacity(isLight ? 0.34 : 0.08), location: 0.0),
                        .init(color: Color.white.opacity(isLight ? 0.12 : 0.025), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            shape.fill(
                LinearGradient(
                    stops: [
                        .init(color: Color.white.opacity(isLight ? 0.24 : 0.10), location: 0.0),
                        .init(color: Color.clear, location: 0.42)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }
}

// MARK: - SenseBar Brand & Icon Loader (AppIcon, MenuBarIcon, BrandMark)

enum BrandIconResources {
    /// Trả về đường dẫn thư mục chứa tài nguyên icon (ưu tiên Bundle.main, sau đó là thư mục build/ hoặc Resources/Brand/)
    private static func findResourceURL(named filename: String) -> URL? {
        if let bundleURL = Bundle.main.resourceURL?.appendingPathComponent(filename),
           FileManager.default.fileExists(atPath: bundleURL.path) {
            return bundleURL
        }
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let candidates = [
            cwd.appendingPathComponent("Resources/Icons/\(filename)"),
            cwd.appendingPathComponent("Resources/Brand/\(filename)"),
            cwd.appendingPathComponent("build/\(filename)"),
            cwd.appendingPathComponent("Resources/\(filename)"),
            cwd.appendingPathComponent("assets/\(filename)"),
            repoRoot.appendingPathComponent("assets/\(filename)"),
            repoRoot.appendingPathComponent("Resources/\(filename)")
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Trả về đường dẫn file GIF minh họa Dynamic Island (Notch hoặc Capsule).
    static func previewGIFURL(isCapsule: Bool) -> URL? {
        let filename = isCapsule ? "dynamic-island-capsule.gif" : "dynamic-island-notch.gif"
        return findResourceURL(named: filename)
    }

    /// Đọc và trả về NSImage từ file SVG 
    static func svgImage(named name: String) -> NSImage? {
        let filename = name.hasSuffix(".svg") ? name : "\(name).svg"
        guard let url = findResourceURL(named: filename) else { return nil }
        let image = NSImage(contentsOf: url)
        image?.isTemplate = true
        return image
    }

    /// Trả về NSImage của AppIcon chính thức
    static func appIconImage() -> NSImage {
        if let pngURL = findResourceURL(named: "AppIcon-Default.png"),
           let iconImage = NSImage(contentsOf: pngURL) {
            return iconImage
        }
        if let icnsURL = findResourceURL(named: "AppIcon.icns"),
           let iconImage = NSImage(contentsOf: icnsURL) {
            return iconImage
        }
        return renderProgrammaticAppIcon(size: 512)
    }

    /// Gán biểu tượng chính thức của SenseBar cho toàn ứng dụng (Dock, Cmd+Tab, Cửa sổ)
    @MainActor
    static func applyApplicationIcon() {
        NSApplication.shared.applicationIconImage = appIconImage()
    }

    /// Tạo NSImage chuẩn Template (26x20pt) cho thanh Menu Bar của macOS
    static func menuBarTemplateImage() -> NSImage {
        if let url2x = findResourceURL(named: "MenuBarIcon@2x.png"),
           let url1x = findResourceURL(named: "MenuBarIcon.png"),
           let data1x = try? Data(contentsOf: url1x),
           let data2x = try? Data(contentsOf: url2x),
           let rep1x = NSBitmapImageRep(data: data1x),
           let rep2x = NSBitmapImageRep(data: data2x) {
            let image = NSImage(size: NSSize(width: 26, height: 20))
            rep1x.size = NSSize(width: 26, height: 20)
            rep2x.size = NSSize(width: 26, height: 20)
            image.addRepresentation(rep1x)
            image.addRepresentation(rep2x)
            image.isTemplate = true
            return image
        }
        return renderProgrammaticMenuBarIcon()
    }

    /// Vẽ biểu tượng 5-Peak Sense Star + 3 Sonic Bars bằng CoreGraphics/AppKit
    static func drawSenseStarEmblem(center: NSPoint, scale: CGFloat, color: NSColor, lineWidth: CGFloat = 42) {
        let path = NSBezierPath()
        let steps = 720
        let A: CGFloat = 214 * scale
        let B: CGFloat = 72 * scale
        let p = 5
        let q = 2
        let rot: CGFloat = .pi / 2

        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps) * 2.0 * .pi
            let a1 = CGFloat(q) * t
            let a2 = CGFloat(p - q) * t
            let rawX = A * cos(a1) + B * cos(a2)
            let rawY = A * sin(a1) - B * sin(a2)
            let x = center.x + rawX * cos(rot) - rawY * sin(rot)
            let y = center.y + rawX * sin(rot) + rawY * cos(rot)
            if i == 0 {
                path.move(to: NSPoint(x: x, y: y))
            } else {
                path.line(to: NSPoint(x: x, y: y))
            }
        }
        path.close()
        path.lineJoinStyle = .round
        path.lineCapStyle = .round
        color.setStroke()
        path.lineWidth = lineWidth * scale
        path.stroke()

        color.setFill()
        let barHeights: [CGFloat] = [68 * scale, 122 * scale, 68 * scale]
        let bw: CGFloat = 28 * scale
        let bs: CGFloat = 24 * scale
        let totalW = CGFloat(barHeights.count) * bw + CGFloat(barHeights.count - 1) * bs
        let sx = center.x - totalW / 2
        for (i, h) in barHeights.enumerated() {
            let r = CGRect(x: sx + CGFloat(i) * (bw + bs), y: center.y - h / 2, width: bw, height: h)
            NSBezierPath(roundedRect: r, xRadius: bw / 2, yRadius: bw / 2).fill()
        }
    }

    private static func renderProgrammaticMenuBarIcon() -> NSImage {
        let size = NSSize(width: 26, height: 20)
        let image = NSImage(size: size, flipped: false) { rect in
            drawSenseStarEmblem(
                center: NSPoint(x: rect.midX, y: rect.midY),
                scale: 15.5 / 572.0,
                color: .black,
                lineWidth: 52
            )
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func renderProgrammaticAppIcon(size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let scale = size / 1024.0
            let iconRect = CGRect(x: 88 * scale, y: 88 * scale, width: 848 * scale, height: 848 * scale)
            let squircle = NSBezierPath(roundedRect: iconRect, xRadius: 195 * scale, yRadius: 195 * scale)
            squircle.addClip()

            let grad = NSGradient(colors: [
                NSColor(srgbRed: 1.00, green: 0.68, blue: 0.34, alpha: 1.0),
                NSColor(srgbRed: 1.00, green: 0.20, blue: 0.48, alpha: 1.0),
                NSColor(srgbRed: 0.56, green: 0.34, blue: 0.98, alpha: 1.0),
                NSColor(srgbRed: 0.00, green: 0.82, blue: 0.98, alpha: 1.0)
            ])
            grad?.draw(in: iconRect, angle: -45)
            drawSenseStarEmblem(
                center: NSPoint(x: rect.midX, y: rect.midY),
                scale: scale,
                color: .white,
                lineWidth: 40
            )
            return true
        }
    }
}

// MARK: - BrandBadge (Hiển thị trực tiếp Logo Icon SenseBar)

struct BrandBadge: View {
    var size: CGFloat = 72

    var body: some View {
        Image(nsImage: BrandIconResources.appIconImage())
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .scaledToFit()
            .frame(width: size, height: size)
            .shadow(color: Color(red: 0.58, green: 0.34, blue: 0.98).opacity(0.32), radius: size * 0.16, x: 0, y: size * 0.06)
    }
}
