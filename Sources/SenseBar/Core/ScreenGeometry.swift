import AppKit
import Foundation

/// Cung cấp số đo chuẩn phần cứng tai thỏ (Notch) và thanh Menu Bar / Capsule
/// trên tất cả các dòng máy MacBook và màn hình ngoài của Apple.
public struct ScreenGeometry: Equatable {
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
            return 26.0 // Trên Menu Bar 32pt chuẩn: cách trên 3pt, dưới 3pt
        } else {
            return 22.0 // Trên Menu Bar 24pt chuẩn: cách trên 1pt, dưới 1pt
        }
    }

    /// Khoảng cách từ đỉnh màn hình để Capsule nằm chính xác ở GIỮA thanh Menu Bar theo chiều dọc
    public var capsuleVerticalCenterOffset: CGFloat {
        return max(0, ((menuBarHeight - capsuleHeight) / 2).rounded(.down))
    }

    /// Kích thước viên nang chuẩn trong Menu Bar (Học hỏi tỉ lệ vàng của vorssaint).
    /// - Parameters:
    ///   - isPlaying: Có đang phát nhạc hay không.
    ///   - hasPet: Có thú cưng đang hoạt động không.
    ///   - customWidth: Độ tinh chỉnh chiều rộng (px).
    ///   - customHeight: Độ tinh chỉnh chiều cao (px).
    /// - Returns: Kích thước `CGSize` của viên nang thu gọn.
    public func compactCapsuleSize(
        isPlaying: Bool = false,
        hasPet: Bool = false,
        customWidth: Double = 0,
        customHeight: Double = 0
    ) -> CGSize {
        let baseHeight: CGFloat = capsuleHeight + CGFloat(customHeight)
        if isPlaying || hasPet {
            // Khi phát nhạc hoặc có thú cưng: kích thước tiêu chuẩn ~ 135.0pt
            let baseWidth: CGFloat = 135.0 + CGFloat(customWidth)
            return CGSize(width: max(56.0, baseWidth), height: max(18.0, min(menuBarHeight, baseHeight)))
        } else {
            // Khi dừng nhạc ở trạng thái nghỉ (Resting Dynamic Island)
            let baseWidth: CGFloat = 135.0 + CGFloat(customWidth)
            return CGSize(width: max(56.0, baseWidth), height: max(18.0, min(menuBarHeight, baseHeight)))
        }
    }

    // MARK: - Kích thước chuẩn cho Notch

    /// Cánh mở rộng bên cạnh tai thỏ vật lý.
    public var compactNotchWingWidth: CGFloat {
        return 40.0
    }

    /// Kích thước toàn bộ của Dynamic Island thu gọn ôm sát tai thỏ.
    /// - Parameters:
    ///   - isPlaying: Có đang phát nhạc hay không.
    ///   - hasPet: Có thú cưng đang hoạt động không.
    ///   - customWidth: Độ tinh chỉnh chiều rộng (px).
    ///   - customHeight: Độ tinh chỉnh chiều cao (px).
    /// - Returns: Kích thước `CGSize` của tai thỏ thu gọn.
    public func compactNotchSize(
        isPlaying: Bool = false,
        hasPet: Bool = false,
        customWidth: Double = 0,
        customHeight: Double = 0
    ) -> CGSize {
        let baseHeight: CGFloat = isNotched ? cameraHeight : (Self.standardNotchHeight - 2.0)
        let height = max(22.0, baseHeight + CGFloat(customHeight))

        if isPlaying || hasPet {
            // Khi phát nhạc hoặc có thú cưng: mở đều 2 cánh ôm 2 bên tai thỏ cân đối
            let baseWidth: CGFloat = cameraWidth + compactNotchWingWidth * 2
            let width = max(180.0, baseWidth + CGFloat(customWidth))
            return CGSize(width: width, height: height)
        } else {
            // Khi dừng nhạc và không bật thú cưng (rỗng):
            // - Trên MacBook có Notch: khớp 100% che kín sau tai thỏ vật lý (không chìa cánh)
            // - Trên màn hình rời: hiển thị tai thỏ mô phỏng chuẩn tỉ lệ MacBook (180pt x 30pt) rỗng sạch sẽ
            let baseW = isNotched ? cameraWidth : Self.standardNotchWidth
            return CGSize(width: baseW + CGFloat(customWidth), height: height)
        }
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
