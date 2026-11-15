import AppKit
import ImageIO

/// Chỉ đọc asset đóng gói. Ảnh giải mã thu nhỏ được cache để tránh giữ bitmap gốc 640 px.
@MainActor
enum CrossPetArtwork {
    private final class Entry: NSObject {
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }
    private static let cache = NSCache<NSString, Entry>()

    static var resourceBundle: Bundle {
        if let resources = Bundle.main.resourceURL,
           let packaged = Bundle(url: resources.appendingPathComponent("SenseBar_SenseBar.bundle")) {
            return packaged
        }
        return Bundle.module
    }

    static func image(_ character: CrossPetCharacter, pose: String = "idle", head: Bool) -> CGImage? {
        let stem = head && pose == "idle" ? "avatar" : pose
        let key = "\(character.rawValue)/\(stem)/\(head)" as NSString
        if let entry = cache.object(forKey: key) { return entry.image }
        guard let url = resourceBundle.url(forResource: stem, withExtension: "webp",
                                          subdirectory: "CrossPet/\(character.rawValue)"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let bitmap = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: head ? 256 : 320,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        let result: CGImage
        if head && stem != "avatar" {
            // Các pose toàn thân dùng phần trên của canvas để giữ mặt đọc được trên notch.
            let box = CGRect(x: 0, y: 0, width: bitmap.width, height: Int(Double(bitmap.height) * 0.60))
            result = bitmap.cropping(to: box) ?? bitmap
        } else { result = bitmap }
        let cropped = trimTransparentEdges(result)
        let displayed = registeredCanvas(cropped, side: head ? 256 : 320)
        cache.setObject(Entry(displayed), forKey: key, cost: displayed.bytesPerRow * displayed.height)
        cache.totalCostLimit = 8 * 1_024 * 1_024
        return displayed
    }

    /// Mọi tư thế dùng chung canvas vuông, căn giữa ngang và chạm đáy.
    /// Cắt alpha trước khi fit để khoảng trống nguồn không làm nhân vật đổi kích cỡ.
    private static func registeredCanvas(_ image: CGImage, side: Int) -> CGImage {
        guard let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                                      bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        let scale = Double(side) / Double(max(image.width, image.height))
        let width = Double(image.width) * scale
        let height = Double(image.height) * scale
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: (Double(side) - width) / 2, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }

    private static func trimTransparentEdges(_ image: CGImage) -> CGImage {
        let width = image.width, height = image.height
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        return rgba.withUnsafeMutableBytes { pixels in
            guard let context = CGContext(data: pixels.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            var left = width, top = height, right = -1, bottom = -1
            for row in 0..<height {
                for column in 0..<width where pixels[(row * width + column) * 4 + 3] > 8 {
                    left = min(left, column); right = max(right, column)
                    top = min(top, row); bottom = max(bottom, row)
                }
            }
            guard right >= left, bottom >= top, let rendered = context.makeImage() else { return image }
            return rendered.cropping(to: CGRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1)) ?? image
        }
    }
}
