import AppKit
import SwiftUI

enum Theme {
    /// Dải màu cực quang đặc trưng của SenseBar Aurora Studio
    static let auroraGradient = LinearGradient(
        colors: [
            Color(red: 1.00, green: 0.68, blue: 0.34),
            Color(red: 1.00, green: 0.24, blue: 0.52),
            Color(red: 0.58, green: 0.34, blue: 0.98),
            Color(red: 0.05, green: 0.82, blue: 0.98)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

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
        switch symbol {
        case "macbook", "sparkles":
            return Color(red: 0.56, green: 0.36, blue: 0.98) // Tím Indigo Aurora
        case "speaker.wave.2.fill", "speaker.wave.2", "waveform":
            return Color(red: 0.08, green: 0.68, blue: 0.98) // Xanh Cyan Audio
        case "fanblades.fill", "cpu", "chart.line.uptrend.xyaxis":
            return Color(red: 0.12, green: 0.80, blue: 0.56) // Xanh Ngọc Lục Bảo SMC
        case "accessibility", "key.horizontal.fill", "lock.shield.fill":
            return Color(red: 0.98, green: 0.56, blue: 0.20) // Cam Amber Quyền Hệ Thống
        default:
            return Color.accentColor
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
        let candidates = [
            cwd.appendingPathComponent("Resources/Brand/\(filename)"),
            cwd.appendingPathComponent("build/\(filename)"),
            cwd.appendingPathComponent("Resources/\(filename)")
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
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
