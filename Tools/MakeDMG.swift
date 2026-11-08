import AppKit
import CoreGraphics
import Foundation

// Tạo file SenseBar.dmg có nền tùy chỉnh.
// Dùng: swift Tools/MakeDMG.swift            -> đóng gói build/SenseBar.app thành build/SenseBar.dmg
//       swift Tools/MakeDMG.swift --bg-only <file.png> -> chỉ xuất ảnh nền để xem thử

let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let projectDir = scriptDir.deletingLastPathComponent()
let buildDir = projectDir.appendingPathComponent("build")
let appPath = buildDir.appendingPathComponent("SenseBar.app")
let dmgPath = buildDir.appendingPathComponent("SenseBar.dmg")

// Kích thước cửa sổ (pt) và vị trí tâm hai icon (tọa độ Finder, gốc ở góc trên trái)
let widthPt: CGFloat = 560
let heightPt: CGFloat = 380
let iconY: CGFloat = 175
let appX: CGFloat = 145
let applicationsX: CGFloat = 415
let scale: CGFloat = 2.0

func radialGlow(center: NSPoint, radius: CGFloat, color: NSColor) {
    let glow = NSGradient(colors: [color, color.withAlphaComponent(0)])!
    glow.draw(fromCenter: center, radius: 0, toCenter: center, radius: radius, options: [])
}

func renderDMGBackground() -> Data? {
    let pxW = Int(widthPt * scale)
    let pxH = Int(heightPt * scale)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pxW, pixelsHigh: pxH,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { return nil }

    // Phải đặt size (pt) trước khi tạo context để ảnh Retina được nhân đôi đúng
    rep.size = NSSize(width: widthPt, height: heightPt)
    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx

    let full = NSRect(x: 0, y: 0, width: widthPt, height: heightPt)

    // Nền trắng ngà
    NSColor(srgbRed: 0.97, green: 0.97, blue: 1.0, alpha: 1).setFill()
    full.fill()

    // Các mảng màu pastel mờ, cùng tông với icon app
    radialGlow(center: NSPoint(x: 40, y: heightPt - 30), radius: 330,
               color: NSColor(srgbRed: 0.72, green: 0.62, blue: 1.00, alpha: 0.55))
    radialGlow(center: NSPoint(x: widthPt - 30, y: heightPt - 20), radius: 300,
               color: NSColor(srgbRed: 1.00, green: 0.80, blue: 0.68, alpha: 0.50))
    radialGlow(center: NSPoint(x: widthPt - 40, y: 20), radius: 340,
               color: NSColor(srgbRed: 0.50, green: 0.82, blue: 1.00, alpha: 0.55))
    radialGlow(center: NSPoint(x: 30, y: 10), radius: 280,
               color: NSColor(srgbRed: 1.00, green: 0.72, blue: 0.86, alpha: 0.40))

    // Chuỗi chấm phát sáng chạy từ app sang Applications
    let midY = heightPt - iconY
    let violet = (r: 0.55, g: 0.38, b: 0.96)
    let cyan = (r: 0.18, g: 0.66, b: 0.98)
    let dots = 6
    let startX: CGFloat = 238
    let gap: CGFloat = 13
    for i in 0..<dots {
        let t = CGFloat(i) / CGFloat(dots - 1)
        let color = NSColor(
            srgbRed: violet.r + (cyan.r - violet.r) * t,
            green: violet.g + (cyan.g - violet.g) * t,
            blue: violet.b + (cyan.b - violet.b) * t,
            alpha: 1
        )
        let radius = 2.2 + 2.4 * t
        let center = NSPoint(x: startX + CGFloat(i) * gap, y: midY)
        radialGlow(center: center, radius: radius * 3.2, color: color.withAlphaComponent(0.28))
        color.withAlphaComponent(0.45 + 0.55 * t).setFill()
        NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius,
                                    width: radius * 2, height: radius * 2)).fill()
    }

    // Đầu mũi tên ở cuối chuỗi chấm
    let head = NSBezierPath()
    let tipX = startX + CGFloat(dots) * gap + 6
    head.move(to: NSPoint(x: tipX - 9, y: midY + 11))
    head.line(to: NSPoint(x: tipX + 2, y: midY))
    head.line(to: NSPoint(x: tipX - 9, y: midY - 11))
    head.lineWidth = 5
    head.lineCapStyle = .round
    head.lineJoinStyle = .round
    NSColor(srgbRed: cyan.r, green: cyan.g, blue: cyan.b, alpha: 1).setStroke()
    head.stroke()

    // Tiêu đề
    let title = "SenseBar"
    let titleAttr: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 28, weight: .bold),
        .foregroundColor: NSColor(srgbRed: 0.13, green: 0.12, blue: 0.22, alpha: 1),
        .kern: -0.4
    ]
    let titleSize = (title as NSString).size(withAttributes: titleAttr)
    (title as NSString).draw(at: NSPoint(x: (widthPt - titleSize.width) / 2, y: heightPt - 66),
                             withAttributes: titleAttr)

    // Dòng hướng dẫn
    let footer = "Kéo SenseBar vào Applications để cài đặt"
    let footAttr: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 12, weight: .medium),
        .foregroundColor: NSColor(srgbRed: 0.40, green: 0.38, blue: 0.55, alpha: 0.9)
    ]
    let footSize = (footer as NSString).size(withAttributes: footAttr)
    (footer as NSString).draw(at: NSPoint(x: (widthPt - footSize.width) / 2, y: 30),
                              withAttributes: footAttr)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

@discardableResult
func runCommand(_ launchPath: String, _ arguments: [String]) -> Int32 {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: launchPath)
    proc.arguments = arguments
    try? proc.run()
    proc.waitUntilExit()
    return proc.terminationStatus
}

/// Chạy lệnh có giới hạn thời gian, tránh treo trên máy không có giao diện (CI)
@discardableResult
func runWithTimeout(_ launchPath: String, _ arguments: [String], seconds: TimeInterval) -> Bool {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: launchPath)
    proc.arguments = arguments
    proc.standardInput = FileHandle.nullDevice
    guard (try? proc.run()) != nil else { return false }
    let deadline = Date().addingTimeInterval(seconds)
    while proc.isRunning && Date() < deadline {
        Thread.sleep(forTimeInterval: 0.2)
    }
    if proc.isRunning {
        proc.terminate()
        return false
    }
    return proc.terminationStatus == 0
}

// Chế độ xem thử: chỉ xuất ảnh nền
if let flag = CommandLine.arguments.firstIndex(of: "--bg-only"), CommandLine.arguments.count > flag + 1 {
    guard let data = renderDMGBackground() else { exit(1) }
    try data.write(to: URL(fileURLWithPath: CommandLine.arguments[flag + 1]))
    print("✓ Đã xuất ảnh nền")
    exit(0)
}

guard FileManager.default.fileExists(atPath: appPath.path) else {
    print("❌ Không thấy \(appPath.path). Hãy chạy ./build-app.sh trước.")
    exit(1)
}

print("▸ Tạo ảnh nền DMG...")
guard let bgData = renderDMGBackground() else {
    print("❌ Không tạo được ảnh nền.")
    exit(1)
}

let tempDmg = buildDir.appendingPathComponent("SenseBar_temp.dmg")
let mountPoint = URL(fileURLWithPath: "/Volumes/SenseBar")

runCommand("/usr/bin/hdiutil", ["detach", mountPoint.path, "-force"])
try? FileManager.default.removeItem(at: tempDmg)
try? FileManager.default.removeItem(at: dmgPath)

print("▸ Tạo và gắn đĩa tạm...")
runCommand("/usr/bin/hdiutil", ["create", "-size", "350m", "-fs", "HFS+", "-volname", "SenseBar", tempDmg.path])
runCommand("/usr/bin/hdiutil", ["attach", tempDmg.path, "-readwrite", "-mountpoint", mountPoint.path])

print("▸ Chép app, tạo liên kết Applications...")
runCommand("/bin/cp", ["-R", appPath.path, mountPoint.appendingPathComponent("SenseBar.app").path])
runCommand("/bin/ln", ["-s", "/Applications", mountPoint.appendingPathComponent("Applications").path])

let bgDir = mountPoint.appendingPathComponent(".background")
try? FileManager.default.createDirectory(at: bgDir, withIntermediateDirectories: true)
try bgData.write(to: bgDir.appendingPathComponent("background.png"))

// Icon riêng cho ổ đĩa
let icnsPath = appPath.appendingPathComponent("Contents/Resources/AppIcon.icns")
if FileManager.default.fileExists(atPath: icnsPath.path) {
    try? FileManager.default.copyItem(at: icnsPath, to: mountPoint.appendingPathComponent(".VolumeIcon.icns"))
    if FileManager.default.fileExists(atPath: "/usr/bin/SetFile") {
        runCommand("/usr/bin/SetFile", ["-a", "C", mountPoint.path])
    }
}

print("▸ Sắp xếp cửa sổ Finder...")
let right = 260 + Int(widthPt)
let bottom = 160 + Int(heightPt)
let appleScript = """
tell application "Finder"
    tell disk "SenseBar"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {260, 160, \(right), \(bottom)}
        set theViewOptions to the icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 124
        set background picture of theViewOptions to file ".background:background.png"
        set position of item "SenseBar.app" of container window to {\(Int(appX)), \(Int(iconY))}
        set position of item "Applications" of container window to {\(Int(applicationsX)), \(Int(iconY))}
        close
        open
        update without registering applications
        delay 1
        close
    end tell
end tell
"""
if !runWithTimeout("/usr/bin/osascript", ["-e", appleScript], seconds: 60) {
    print("⚠️ Không sắp xếp được cửa sổ Finder (máy không có giao diện?). DMG vẫn được tạo nhưng dùng bố cục mặc định.")
}

print("▸ Nén DMG...")
if runCommand("/usr/bin/hdiutil", ["detach", mountPoint.path]) != 0 {
    Thread.sleep(forTimeInterval: 2)
    runCommand("/usr/bin/hdiutil", ["detach", mountPoint.path, "-force"])
}
runCommand("/usr/bin/hdiutil", ["convert", tempDmg.path, "-format", "UDZO", "-imagekey", "zlib-level=9", "-o", dmgPath.path])
try? FileManager.default.removeItem(at: tempDmg)

print("✓ DMG sẵn sàng tại \(dmgPath.path)")
