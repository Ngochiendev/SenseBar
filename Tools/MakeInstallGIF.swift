import AppKit
import CoreGraphics
import Foundation

// Tạo ảnh động hướng dẫn cài đặt SenseBar (kéo app vào Applications) cho README / GitHub.
// Dùng: swift Tools/MakeInstallGIF.swift [--keep-frames]
// Kết quả: assets/install-sensebar.gif và assets/install-sensebar.mp4 (cần ffmpeg)

let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let projectDir = scriptDir.deletingLastPathComponent()
let assetsDir = projectDir.appendingPathComponent("assets")
let framesDir = projectDir.appendingPathComponent("build/install-frames")
let keepFrames = CommandLine.arguments.contains("--keep-frames")

// Khung hình 560x380 pt, xuất ở tỉ lệ 1.5x (840x570 px, cả hai đều chẵn cho MP4)
let widthPt: CGFloat = 560
let heightPt: CGFloat = 380
let iconSize: CGFloat = 124
let iconY: CGFloat = 175
let appX: CGFloat = 145
let applicationsX: CGFloat = 415
let outputScale: CGFloat = 1.5

let fps = 24
let frameCount = 72

guard let appIcon = NSImage(contentsOf: projectDir.appendingPathComponent("Resources/Brand/AppIcon-Default.png")) else {
    print("❌ Không đọc được Resources/Brand/AppIcon-Default.png")
    exit(1)
}
let folderIcon = NSWorkspace.shared.icon(forFile: "/Applications")

func easeInOut(_ t: CGFloat) -> CGFloat {
    t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
}

func clamp01(_ v: CGFloat) -> CGFloat { min(1, max(0, v)) }

func radialGlow(center: NSPoint, radius: CGFloat, color: NSColor) {
    let glow = NSGradient(colors: [color, color.withAlphaComponent(0)])!
    glow.draw(fromCenter: center, radius: 0, toCenter: center, radius: radius, options: [])
}

/// Vẽ icon tại tâm (toạ độ kiểu Finder, gốc trên trái) với tỉ lệ và độ mờ tuỳ chỉnh
func drawIcon(_ image: NSImage, centerX: CGFloat, centerY: CGFloat, scale: CGFloat, alpha: CGFloat) {
    let size = iconSize * scale
    let rect = NSRect(x: centerX - size / 2, y: heightPt - centerY - size / 2, width: size, height: size)
    image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: alpha,
               respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high.rawValue])
}

func drawCenteredText(_ text: String, y: CGFloat, attributes: [NSAttributedString.Key: Any], centerX: CGFloat = widthPt / 2) {
    let size = (text as NSString).size(withAttributes: attributes)
    (text as NSString).draw(at: NSPoint(x: centerX - size.width / 2, y: y), withAttributes: attributes)
}

func drawBackground() {
    NSColor(srgbRed: 0.97, green: 0.97, blue: 1.0, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: widthPt, height: heightPt).fill()

    radialGlow(center: NSPoint(x: 40, y: heightPt - 30), radius: 330,
               color: NSColor(srgbRed: 0.72, green: 0.62, blue: 1.00, alpha: 0.55))
    radialGlow(center: NSPoint(x: widthPt - 30, y: heightPt - 20), radius: 300,
               color: NSColor(srgbRed: 1.00, green: 0.80, blue: 0.68, alpha: 0.50))
    radialGlow(center: NSPoint(x: widthPt - 40, y: 20), radius: 340,
               color: NSColor(srgbRed: 0.50, green: 0.82, blue: 1.00, alpha: 0.55))
    radialGlow(center: NSPoint(x: 30, y: 10), radius: 280,
               color: NSColor(srgbRed: 1.00, green: 0.72, blue: 0.86, alpha: 0.40))

    drawCenteredText("SenseBar", y: heightPt - 66, attributes: [
        .font: NSFont.systemFont(ofSize: 28, weight: .bold),
        .foregroundColor: NSColor(srgbRed: 0.13, green: 0.12, blue: 0.22, alpha: 1),
        .kern: -0.4
    ])
    drawCenteredText("Kéo SenseBar vào Applications để cài đặt", y: 30, attributes: [
        .font: NSFont.systemFont(ofSize: 12, weight: .medium),
        .foregroundColor: NSColor(srgbRed: 0.40, green: 0.38, blue: 0.55, alpha: 0.9)
    ])

    let labelAttr: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 12),
        .foregroundColor: NSColor(srgbRed: 0.12, green: 0.12, blue: 0.18, alpha: 1)
    ]
    let labelY = heightPt - (iconY + iconSize / 2 + 22)
    drawCenteredText("SenseBar.app", y: labelY, attributes: labelAttr, centerX: appX)
    drawCenteredText("Applications", y: labelY, attributes: labelAttr, centerX: applicationsX)
}

/// Chuỗi chấm ở giữa: một nhịp sáng chạy từ trái sang phải, lặp liền mạch theo `t`
func drawDots(t: CGFloat) {
    let midY = heightPt - iconY
    let violet = (r: 0.55, g: 0.38, b: 0.96)
    let cyan = (r: 0.18, g: 0.66, b: 0.98)
    let dots = 6
    let startX: CGFloat = 238
    let gap: CGFloat = 13

    for i in 0..<dots {
        let k = CGFloat(i) / CGFloat(dots - 1)
        let color = NSColor(
            srgbRed: violet.r + (cyan.r - violet.r) * k,
            green: violet.g + (cyan.g - violet.g) * k,
            blue: violet.b + (cyan.b - violet.b) * k,
            alpha: 1
        )
        // Mỗi chấm sáng lên lệch pha nhau một chút, tạo cảm giác chạy về bên phải
        let wave = cos(2 * .pi * (t * 2 - k * 0.8))
        let pulse = pow(max(0, wave), 2)
        let radius = 2.2 + 2.4 * k + 1.2 * pulse
        let center = NSPoint(x: startX + CGFloat(i) * gap, y: midY)
        radialGlow(center: center, radius: radius * 3.2, color: color.withAlphaComponent(0.12 + 0.30 * pulse))
        color.withAlphaComponent(0.35 + 0.65 * pulse).setFill()
        NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius,
                                    width: radius * 2, height: radius * 2)).fill()
    }

    let tipX = startX + CGFloat(dots) * gap + 6
    let head = NSBezierPath()
    head.move(to: NSPoint(x: tipX - 9, y: midY + 11))
    head.line(to: NSPoint(x: tipX + 2, y: midY))
    head.line(to: NSPoint(x: tipX - 9, y: midY - 11))
    head.lineWidth = 5
    head.lineCapStyle = .round
    head.lineJoinStyle = .round
    NSColor(srgbRed: cyan.r, green: cyan.g, blue: cyan.b, alpha: 1).setStroke()
    head.stroke()
}

func drawCheckBadge(progress: CGFloat) {
    guard progress > 0 else { return }
    let radius: CGFloat = 14 * progress
    let center = NSPoint(x: applicationsX + 38, y: heightPt - (iconY + 40))
    NSColor(srgbRed: 0.20, green: 0.78, blue: 0.42, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius,
                                width: radius * 2, height: radius * 2)).fill()
    let check = NSBezierPath()
    check.move(to: NSPoint(x: center.x - radius * 0.45, y: center.y))
    check.line(to: NSPoint(x: center.x - radius * 0.1, y: center.y - radius * 0.38))
    check.line(to: NSPoint(x: center.x + radius * 0.5, y: center.y + radius * 0.35))
    check.lineWidth = max(1, 3 * progress)
    check.lineCapStyle = .round
    check.lineJoinStyle = .round
    NSColor.white.setStroke()
    check.stroke()
}

func renderFrame(index: Int) -> Data? {
    let t = CGFloat(index) / CGFloat(frameCount)
    let pxW = Int(widthPt * outputScale)
    let pxH = Int(heightPt * outputScale)

    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pxW, pixelsHigh: pxH,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { return nil }
    // Đặt size (pt) trước khi tạo context để nét vẽ được nhân tỉ lệ đúng
    rep.size = NSSize(width: widthPt, height: heightPt)
    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx

    drawBackground()
    drawDots(t: t)

    // Icon thư mục Applications: nảy nhẹ khi app rơi vào
    let bounceU = clamp01((t - 0.60) / 0.14)
    let folderScale = 1 + 0.09 * sin(.pi * bounceU)
    drawIcon(folderIcon, centerX: applicationsX, centerY: iconY, scale: folderScale, alpha: 1)

    // Icon app gốc luôn nằm yên ở vị trí cũ
    drawIcon(appIcon, centerX: appX, centerY: iconY, scale: 1, alpha: 1)

    // Bản sao của app bay theo cung tròn sang Applications rồi nhỏ dần
    let travel = easeInOut(clamp01((t - 0.12) / 0.48))
    if t >= 0.12 && t < 0.62 {
        let x = appX + (applicationsX - appX) * travel
        let y = iconY - sin(.pi * travel) * 34
        let fade = 1 - clamp01((travel - 0.82) / 0.18)
        drawIcon(appIcon, centerX: x, centerY: y, scale: 1 - 0.45 * travel, alpha: fade)
    }

    // Dấu tick hiện ra sau khi cài xong, rồi mờ đi để vòng lặp liền mạch
    let appear = clamp01((t - 0.70) / 0.08)
    let vanish = 1 - clamp01((t - 0.92) / 0.08)
    drawCheckBadge(progress: easeInOut(appear) * vanish)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

@discardableResult
func run(_ path: String, _ args: [String]) -> Int32 {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: path)
    proc.arguments = args
    proc.standardOutput = FileHandle.nullDevice
    proc.standardError = FileHandle.nullDevice
    try? proc.run()
    proc.waitUntilExit()
    return proc.terminationStatus
}

let ffmpegCandidates = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"]
guard let ffmpeg = ffmpegCandidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
    print("❌ Không tìm thấy ffmpeg. Cài bằng: brew install ffmpeg")
    exit(1)
}

try? FileManager.default.removeItem(at: framesDir)
try FileManager.default.createDirectory(at: framesDir, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: assetsDir, withIntermediateDirectories: true)

print("▸ Vẽ \(frameCount) khung hình...")
for i in 0..<frameCount {
    guard let data = renderFrame(index: i) else {
        print("❌ Lỗi vẽ khung hình \(i)")
        exit(1)
    }
    try data.write(to: framesDir.appendingPathComponent(String(format: "f_%03d.png", i)))
}

let pattern = framesDir.appendingPathComponent("f_%03d.png").path
let gifPath = assetsDir.appendingPathComponent("install-sensebar.gif").path
let mp4Path = assetsDir.appendingPathComponent("install-sensebar.mp4").path

print("▸ Xuất GIF...")
let gifStatus = run(ffmpeg, [
    "-y", "-framerate", "\(fps)", "-i", pattern,
    "-vf", "split[a][b];[a]palettegen=max_colors=256[p];[b][p]paletteuse=dither=sierra2_4a",
    "-loop", "0", gifPath
])

print("▸ Xuất MP4...")
let mp4Status = run(ffmpeg, [
    "-y", "-framerate", "\(fps)", "-stream_loop", "3", "-i", pattern,
    "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18", "-movflags", "+faststart", mp4Path
])

if !keepFrames { try? FileManager.default.removeItem(at: framesDir) }

print(gifStatus == 0 ? "✓ \(gifPath)" : "❌ Xuất GIF thất bại")
print(mp4Status == 0 ? "✓ \(mp4Path)" : "❌ Xuất MP4 thất bại")
