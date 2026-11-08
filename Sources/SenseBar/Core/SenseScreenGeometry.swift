import AppKit
import Foundation

/// Cung cấp số đo chuẩn phần cứng tai thỏ (Notch) và thanh Menu Bar / Capsule
/// trên tất cả các dòng máy MacBook và màn hình ngoài của Apple.
public struct SenseScreenGeometry: Equatable {
    public let screen: CGRect
    public let cameraWidth: CGFloat
    public let cameraHeight: CGFloat
    public let isNotched: Bool
    public let menuBarHeight: CGFloat
    public let backingScale: CGFloat

    // MARK: - Tiêu chuẩn phần cứng Apple Notch
    public static let standardNotchWidth: CGFloat = 185.0
    public static let standardNotchHeight: CGFloat = 32.0
    public static let standardShoulderRadius: CGFloat = 12.0
    public static let standardBottomRadius: CGFloat = 10.0

    public init(for screen: NSScreen) {
        self.screen = screen.frame
        self.backingScale = screen.backingScaleFactor

        let safeTop = screen.safeAreaInsets.top
        let hasHardwareNotch = safeTop > 0 && screen.auxiliaryTopLeftArea != nil && screen.auxiliaryTopRightArea != nil

        // Đo chiều cao thực tế của Menu Bar trên màn hình hiện tại:
        let visibleGap = screen.frame.maxY - screen.visibleFrame.maxY
        let hasVisibleBar = visibleGap.isFinite && (16...64).contains(visibleGap)

        if hasHardwareNotch,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            self.isNotched = true
            // Số đo chuẩn chính xác của camera cutout từ macOS:
            let measuredGap = right.minX - left.maxX
            self.cameraWidth = measuredGap > 80 ? measuredGap : Self.standardNotchWidth
            self.cameraHeight = max(Self.standardNotchHeight, safeTop)
            self.menuBarHeight = hasVisibleBar ? max(cameraHeight, visibleGap) : cameraHeight
        } else {
            self.isNotched = false
            self.cameraWidth = 180.0
            self.cameraHeight = Self.standardNotchHeight - 2.0
            self.menuBarHeight = hasVisibleBar ? visibleGap : max(24.0, NSStatusBar.system.thickness)
        }
    }

    // MARK: - Kích thước chuẩn cho Capsule

    /// Chiều cao chuẩn của viên nang để luôn nằm gọn và căn giữa trục dọc trong Menu Bar
    public var capsuleHeight: CGFloat {
        if menuBarHeight >= 30 {
            return 24.0 // Trên Menu Bar 32pt: cách trên 4pt, dưới 4pt
        } else {
            return 20.0 // Trên Menu Bar 24pt chuẩn: cách trên 2pt, dưới 2pt
        }
    }

    /// Khoảng cách từ đỉnh màn hình để Capsule nằm chính xác ở GIỮA thanh Menu Bar theo chiều dọc
    public var capsuleVerticalCenterOffset: CGFloat {
        return max(0, ((menuBarHeight - capsuleHeight) / 2).rounded(.down))
    }

    /// Kích thước viên nang chuẩn trong Menu Bar.
    /// - Parameters:
    ///   - customWidth: Độ tinh chỉnh chiều rộng (px).
    ///   - customHeight: Độ tinh chỉnh chiều cao (px).
    /// - Returns: Kích thước `CGSize` của viên nang thu gọn.
    public func compactCapsuleSize(customWidth: Double = 0, customHeight: Double = 0) -> CGSize {
        let baseWidth: CGFloat = 208.0 + CGFloat(customWidth)
        let baseHeight: CGFloat = capsuleHeight + CGFloat(customHeight)
        return CGSize(width: max(130.0, baseWidth), height: max(18.0, min(menuBarHeight, baseHeight)))
    }

    // MARK: - Kích thước chuẩn cho Notch

    /// Cánh mở rộng bên cạnh tai thỏ vật lý.
    public var compactNotchWingWidth: CGFloat {
        return 40.0
    }

    /// Kích thước toàn bộ của Dynamic Island thu gọn ôm sát tai thỏ.
    /// - Parameters:
    ///   - customWidth: Độ tinh chỉnh chiều rộng (px).
    ///   - customHeight: Độ tinh chỉnh chiều cao (px).
    /// - Returns: Kích thước `CGSize` của tai thỏ thu gọn.
    public func compactNotchSize(customWidth: Double = 0, customHeight: Double = 0) -> CGSize {
        // Màn hình MacBook có tai thỏ giữ nguyên 32pt, màn hình ngoài giảm -2pt (30pt) để khớp mép dưới
        let baseHeight: CGFloat = isNotched ? cameraHeight : (Self.standardNotchHeight - 2.0)
        let baseWidth: CGFloat = (isNotched ? cameraWidth : 170.0) + compactNotchWingWidth * 2
        let width = max(180.0, baseWidth + CGFloat(customWidth))
        let height = max(22.0, baseHeight + CGFloat(customHeight))
        return CGSize(width: width, height: height)
    }

    // MARK: - Kích thước chuẩn khi Mở rộng (Expanded)

    /// Kích thước hiển thị khi Dynamic Island mở rộng chi tiết điều khiển nhạc.
    public var expandedSize: CGSize {
        return CGSize(width: 396.0, height: 176.0)
    }

    /// Vai bo cong chuẩn (Top Shoulder: 12pt) và bán kính đáy (Bottom Radius: 10pt)
    public var shoulderRadius: (shoulder: CGFloat, bottom: CGFloat) {
        return (shoulder: Self.standardShoulderRadius, bottom: Self.standardBottomRadius)
    }
}

