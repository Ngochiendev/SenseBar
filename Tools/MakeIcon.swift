// Generates the complete SenseBar brand & icon asset suite:
// 1. Resources/Brand/AppIcon-Default.png (1024x1024 Master App Icon: 5-Peak Sense Star + 3 Sonic Bars on Aurora Mesh)
// 2. Resources/Brand/logo.png (1024x1024 Master Monochrome Template Silhouette)
// 3. Resources/Brand/AppIcon.icon/Assets/sensebar-brandmark.svg (Vector SVG for adaptive icon catalog)
// 4. build/AppIcon.iconset/icon_*.png (10 standard & Retina iconset PNGs)
// 5. build/AppIcon.icns (macOS multi-resolution .icns container)
// 6. build/MenuBarIcon.png (26x20 @1x) & build/MenuBarIcon@2x.png (52x40 @2x)
// 7. build/BrandMark.png (640px trimmed template mark for UI headers, Onboarding, About)

import AppKit
import CoreGraphics

let iconSizes: [(name: String, px: Int, icnsType: String?)] = [
    ("icon_16x16", 16, nil), ("icon_16x16@2x", 32, "ic11"),
    ("icon_32x32", 32, nil), ("icon_32x32@2x", 64, "ic12"),
    ("icon_128x128", 128, "ic07"), ("icon_128x128@2x", 256, "ic13"),
    ("icon_256x256", 256, "ic08"), ("icon_256x256@2x", 512, "ic14"),
    ("icon_512x512", 512, "ic09"), ("icon_512x512@2x", 1024, "ic10"),
]

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/AppIcon.iconset"
let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let projectDir = scriptDir.deletingLastPathComponent()

func bitmapCanvas(_ px: Int, _ py: Int) -> NSBitmapImageRep? {
    NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: px,
        pixelsHigh: py,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )
}

/// Outward-pointing 5-Peak Hypotrochoid curve (Sense Star)
func makeSenseStarPath(
    center: NSPoint,
    majorA A: CGFloat,
    minorB B: CGFloat,
    lobes p: Int = 5,
    stepWinding q: Int = 2,
    rotationOffset: CGFloat = .pi / 2,
    steps: Int = 2000
) -> NSBezierPath {
    let path = NSBezierPath()
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2.0 * .pi
        let a1 = CGFloat(q) * t
        let a2 = CGFloat(p - q) * t
        let rawX = A * cos(a1) + B * cos(a2)
        let rawY = A * sin(a1) - B * sin(a2)
        let x = center.x + rawX * cos(rotationOffset) - rawY * sin(rotationOffset)
        let y = center.y + rawX * sin(rotationOffset) + rawY * cos(rotationOffset)
        if i == 0 {
            path.move(to: NSPoint(x: x, y: y))
        } else {
            path.line(to: NSPoint(x: x, y: y))
        }
    }
    path.close()
    path.lineJoinStyle = .round
    path.lineCapStyle = .round
    return path
}

/// Draws the 5-Peak Sense Star + 3 Sonic Equalizer Bars at the given center & scale
func drawSenseBarEmblem(center: NSPoint, scale: CGFloat, color: NSColor, lineWidth: CGFloat = 42) {
    let knot = makeSenseStarPath(
        center: center,
        majorA: 214 * scale,
        minorB: 72 * scale
    )
    color.setStroke()
    knot.lineWidth = lineWidth * scale
    knot.stroke()

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

/// Draws the silky Apple-style Aurora Mesh Gradient inside `rect`
func drawAuroraMeshBackground(in rect: CGRect) {
    let baseGrad = NSGradient(
        starting: NSColor(srgbRed: 0.99, green: 0.76, blue: 0.52, alpha: 1.0),
        ending: NSColor(srgbRed: 0.56, green: 0.44, blue: 0.96, alpha: 1.0)
    )!
    baseGrad.draw(in: rect, angle: -45)

    struct MeshBlob {
        let center: NSPoint
        let radius: CGFloat
        let color: NSColor
    }

    let blobs: [MeshBlob] = [
        MeshBlob(center: NSPoint(x: 210, y: 810), radius: 640, color: NSColor(srgbRed: 1.00, green: 0.74, blue: 0.36, alpha: 0.96)),
        MeshBlob(center: NSPoint(x: 800, y: 820), radius: 620, color: NSColor(srgbRed: 1.00, green: 0.16, blue: 0.44, alpha: 0.95)),
        MeshBlob(center: NSPoint(x: 210, y: 190), radius: 660, color: NSColor(srgbRed: 0.00, green: 0.85, blue: 1.00, alpha: 0.96)),
        MeshBlob(center: NSPoint(x: 820, y: 220), radius: 640, color: NSColor(srgbRed: 0.62, green: 0.34, blue: 0.98, alpha: 0.94)),
        MeshBlob(center: NSPoint(x: 340, y: 510), radius: 460, color: NSColor(srgbRed: 0.98, green: 0.94, blue: 0.92, alpha: 0.58)),
        MeshBlob(center: NSPoint(x: 560, y: 490), radius: 480, color: NSColor(srgbRed: 0.46, green: 0.50, blue: 0.96, alpha: 0.70))
    ]

    for b in blobs {
        let g = NSGradient(
            colors: [
                b.color,
                b.color.withAlphaComponent(b.color.alphaComponent * 0.52),
                b.color.withAlphaComponent(b.color.alphaComponent * 0.15),
                NSColor.clear
            ],
            atLocations: [0.0, 0.42, 0.75, 1.0],
            colorSpace: .deviceRGB
        )!
        g.draw(fromCenter: b.center, radius: 0, toCenter: b.center, radius: b.radius, options: [.drawsBeforeStartingLocation])
    }
}

// MARK: - 1. Generate Master Files in Resources/Brand/

let brandDir = projectDir.appendingPathComponent("Resources/Brand")
try? FileManager.default.createDirectory(at: brandDir, withIntermediateDirectories: true)
let appIconPath = brandDir.appendingPathComponent("AppIcon-Default.png").path
let logoPath = brandDir.appendingPathComponent("logo.png").path

// 1A. Generate Resources/Brand/AppIcon-Default.png (1024x1024)
if let rep = bitmapCanvas(1024, 1024), let nsCtx = NSGraphicsContext(bitmapImageRep: rep) {
    let ctx = nsCtx.cgContext
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = nsCtx

    let iconRect = CGRect(x: 88, y: 88, width: 848, height: 848)
    let radius: CGFloat = 195
    let squircle = NSBezierPath(roundedRect: iconRect, xRadius: radius, yRadius: radius)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -16), blur: 36, color: NSColor(calibratedWhite: 0, alpha: 0.20).cgColor)
    NSColor.white.setFill()
    squircle.fill()
    ctx.restoreGState()

    ctx.saveGState()
    squircle.addClip()
    drawAuroraMeshBackground(in: iconRect)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 18, color: NSColor(calibratedWhite: 0, alpha: 0.16).cgColor)
    drawSenseBarEmblem(center: NSPoint(x: 512, y: 512), scale: 1.0, color: .white, lineWidth: 40)
    ctx.restoreGState()

    let rim = NSBezierPath(roundedRect: iconRect.insetBy(dx: 2.5, dy: 2.5), xRadius: radius - 2.5, yRadius: radius - 2.5)
    rim.lineWidth = 5
    NSColor.white.withAlphaComponent(0.32).setStroke()
    rim.stroke()

    ctx.restoreGState()
    NSGraphicsContext.restoreGraphicsState()

    if let data = rep.representation(using: .png, properties: [:]) {
        try data.write(to: URL(fileURLWithPath: appIconPath))
    }
}

// 1B. Generate Resources/Brand/logo.png (1024x1024 Monochrome Template Silhouette)
if let rep = bitmapCanvas(1024, 1024), let nsCtx = NSGraphicsContext(bitmapImageRep: rep) {
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = nsCtx
    // Slightly bolder stroke (52pt) so when scaled down to 16pt on Menu Bar, the 5-Peak Star & 3 Sonic Bars are razor-sharp!
    let ink = NSColor(srgbRed: 0.03, green: 0.04, blue: 0.06, alpha: 1.0)
    drawSenseBarEmblem(center: NSPoint(x: 512, y: 512), scale: 1.0, color: ink, lineWidth: 50)
    NSGraphicsContext.restoreGraphicsState()

    if let data = rep.representation(using: .png, properties: [:]) {
        try data.write(to: URL(fileURLWithPath: logoPath))
    }
}

// 1C. Generate Resources/Brand/AppIcon.icon/Assets/sensebar-brandmark.svg (Vector SVG of the 5-Peak Sense Star + 3 Sonic Bars)
let svgDir = brandDir.appendingPathComponent("AppIcon.icon/Assets")
try? FileManager.default.createDirectory(at: svgDir, withIntermediateDirectories: true)
let svgPath = svgDir.appendingPathComponent("sensebar-brandmark.svg")
do {
    let center = NSPoint(x: 512, y: 512)
    let steps = 360
    var dStr = ""
    let A: CGFloat = 214
    let B: CGFloat = 72
    let p = 5
    let q = 2
    let rot: CGFloat = -.pi / 2 // SVG Y-axis is top-down
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2.0 * .pi
        let a1 = CGFloat(q) * t
        let a2 = CGFloat(p - q) * t
        let rawX = A * cos(a1) + B * cos(a2)
        let rawY = A * sin(a1) - B * sin(a2)
        let x = center.x + rawX * cos(rot) - rawY * sin(rot)
        let y = center.y + rawX * sin(rot) + rawY * cos(rot)
        let cmd = (i == 0) ? "M" : "L"
        dStr += String(format: "%@%.2f,%.2f ", cmd, x, y)
    }
    dStr += "Z"
    let svgContent = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
      <path d="\(dStr)" fill="none" stroke="#000000" stroke-width="44" stroke-linecap="round" stroke-linejoin="round"/>
      <rect x="434" y="478" width="28" height="68" rx="14" fill="#000000"/>
      <rect x="498" y="451" width="28" height="122" rx="14" fill="#000000"/>
      <rect x="562" y="478" width="28" height="68" rx="14" fill="#000000"/>
    </svg>
    """
    try svgContent.write(to: svgPath, atomically: true, encoding: .utf8)
}

// MARK: - 2. Build Derived Assets (AppIcon.iconset, AppIcon.icns, MenuBarIcon, BrandMark)

guard let logo = NSImage(contentsOfFile: logoPath),
      let logoTIFF = logo.tiffRepresentation,
      let logoRep = NSBitmapImageRep(data: logoTIFF),
      let appIconMaster = NSImage(contentsOfFile: appIconPath)
else {
    print("could not load master brand files")
    exit(1)
}

func contentBounds(of rep: NSBitmapImageRep) -> CGRect {
    var minX = rep.pixelsWide, minY = rep.pixelsHigh, maxX = 0, maxY = 0
    for y in 0..<rep.pixelsHigh {
        for x in 0..<rep.pixelsWide {
            if let color = rep.colorAt(x: x, y: y), color.alphaComponent > 0.05 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
    }
    guard maxX > minX, maxY > minY else {
        return CGRect(x: 0, y: 0, width: rep.pixelsWide, height: rep.pixelsHigh)
    }
    return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
}

let bounds = contentBounds(of: logoRep)
let sourceRect = CGRect(
    x: bounds.minX,
    y: CGFloat(logoRep.pixelsHigh) - bounds.maxY,
    width: bounds.width,
    height: bounds.height
)

func drawMark(into target: CGRect) {
    let scale = min(target.width / sourceRect.width, target.height / sourceRect.height)
    let size = CGSize(width: sourceRect.width * scale, height: sourceRect.height * scale)
    let rect = CGRect(
        x: target.midX - size.width / 2,
        y: target.midY - size.height / 2,
        width: size.width,
        height: size.height
    )
    logo.draw(
        in: rect,
        from: sourceRect,
        operation: .sourceOver,
        fraction: 1,
        respectFlipped: false,
        hints: [.interpolation: NSImageInterpolation.high.rawValue]
    )
}

func renderAppIcon(px: Int) -> Data? {
    let size = CGFloat(px)
    guard let rep = bitmapCanvas(px, px), let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    rep.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    appIconMaster.draw(
        in: NSRect(x: 0, y: 0, width: size, height: size),
        from: NSRect(origin: .zero, size: appIconMaster.size),
        operation: .sourceOver,
        fraction: 1,
        respectFlipped: false,
        hints: [.interpolation: NSImageInterpolation.high.rawValue]
    )
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

// Menu bar glyph: 26x20 canvas for MenuBarIcon.
// Our 5-Peak Sense Star is ~1:1, so 16pt height centers optically in the 20pt menu bar!
let menuBarGlyphHeight: CGFloat = 16.0
let menuBarCanvas = (width: 26, height: 20)

func renderMenuBarIcon(scale: Int) -> Data? {
    let width = menuBarCanvas.width * scale, height = menuBarCanvas.height * scale
    guard let rep = bitmapCanvas(width, height), let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    rep.size = NSSize(width: menuBarCanvas.width, height: menuBarCanvas.height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    let ink = menuBarGlyphHeight * CGFloat(scale)
    let y = (CGFloat(height) - ink) / 2
    drawMark(into: CGRect(x: 0, y: y, width: CGFloat(width), height: ink))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

func appendFourCC(_ value: String, to data: inout Data) {
    data.append(contentsOf: value.utf8)
}

func appendUInt32BE(_ value: Int, to data: inout Data) {
    let clamped = UInt32(value)
    data.append(UInt8((clamped >> 24) & 0xff))
    data.append(UInt8((clamped >> 16) & 0xff))
    data.append(UInt8((clamped >> 8) & 0xff))
    data.append(UInt8(clamped & 0xff))
}

func writeICNS(entries: [(type: String, data: Data)], to url: URL) throws {
    let totalLength = 8 + entries.reduce(0) { $0 + 8 + $1.data.count }
    var icns = Data()
    appendFourCC("icns", to: &icns)
    appendUInt32BE(totalLength, to: &icns)
    for entry in entries {
        appendFourCC(entry.type, to: &icns)
        appendUInt32BE(8 + entry.data.count, to: &icns)
        icns.append(entry.data)
    }
    try icns.write(to: url)
}

try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
var icnsEntries: [(type: String, data: Data)] = []
for (name, px, icnsType) in iconSizes {
    guard let data = renderAppIcon(px: px) else {
        print("failed to render \(name)")
        exit(1)
    }
    try data.write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
    if let icnsType {
        icnsEntries.append((type: icnsType, data: data))
    }
}
try writeICNS(entries: icnsEntries, to: URL(fileURLWithPath: "\(outDir)/../AppIcon.icns"))

for scale in [1, 2] {
    guard let data = renderMenuBarIcon(scale: scale) else {
        print("failed to render menu bar icon @\(scale)x")
        exit(1)
    }
    let suffix = scale == 1 ? "" : "@2x"
    try data.write(to: URL(fileURLWithPath: "\(outDir)/../MenuBarIcon\(suffix).png"))
}

let markWidth = 640
let markHeight = Int(CGFloat(markWidth) * sourceRect.height / sourceRect.width)
if let rep = bitmapCanvas(markWidth, markHeight), let ctx = NSGraphicsContext(bitmapImageRep: rep) {
    rep.size = NSSize(width: markWidth, height: markHeight)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    drawMark(into: CGRect(x: 0, y: 0, width: CGFloat(markWidth), height: CGFloat(markHeight)))
    NSGraphicsContext.restoreGraphicsState()
    if let data = rep.representation(using: .png, properties: [:]) {
        try data.write(to: URL(fileURLWithPath: "\(outDir)/../BrandMark.png"))
    }
}

print("✓ Generated all SenseBar Brand & Icon assets successfully!")

