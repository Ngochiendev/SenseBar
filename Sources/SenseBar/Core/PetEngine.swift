import CoreGraphics
import Foundation

// MARK: - 1. Mô hình Ngoại hình & Bảng màu (Appearance & Palette)

/// Phong cách thiết kế tổng thể của thú cưng.
enum PetStyle: String, CaseIterable, Identifiable {
    /// Phong cách tối giản nguyên khối.
    case minimal
    /// Phong cách người máy với tai máy, ăng-ten và kính bảo hộ (visor).
    case robot

    var id: String { rawValue }
}

/// Kiểu dáng hình học thân thể của thú cưng.
enum PetShape: String, CaseIterable, Identifiable {
    /// Thân tròn dạng hình cầu.
    case ball
    /// Thân vuông bo góc mềm mại (Squircle / Siêu elip).
    case squircle

    var id: String { rawValue }
}

/// Cấu trúc màu sRGB độc lập dùng cho CoreGraphics mà không cần phụ thuộc AppKit.
struct PetColor: Equatable {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
    var alpha: CGFloat = 1.0

    /// Khởi tạo đối tượng CGColor để kết xuất đồ họa vector.
    var cgColor: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    /// Màu mực đen dịu cho mắt, tương phản tốt trên nền tai thỏ và đảo Dynamic Island.
    static let ink = PetColor(red: 0.07, green: 0.07, blue: 0.08)
    /// Kính bảo hộ tối màu trên mặt thú cưng robot.
    static let visor = PetColor(red: 0.09, green: 0.09, blue: 0.11)
    /// Ánh sáng bóng mờ (highlight) phản chiếu trên thân.
    static let shine = PetColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.55)
}

/// Bảng màu sắc chủ đạo của thú cưng theo thứ tự quang phổ pastel.
enum PetPalette: String, CaseIterable, Identifiable {
    case pearl, lemon, peach, rose, lilac, sky, mint

    var id: String { rawValue }

    /// Màu sáng phần thân trên đón sáng.
    var light: PetColor {
        switch self {
        case .pearl: return PetColor(red: 0.99, green: 0.98, blue: 0.96)
        case .lemon: return PetColor(red: 1.00, green: 0.96, blue: 0.64)
        case .peach: return PetColor(red: 1.00, green: 0.86, blue: 0.74)
        case .rose:  return PetColor(red: 1.00, green: 0.80, blue: 0.87)
        case .lilac: return PetColor(red: 0.88, green: 0.83, blue: 1.00)
        case .sky:   return PetColor(red: 0.77, green: 0.90, blue: 1.00)
        case .mint:  return PetColor(red: 0.72, green: 0.97, blue: 0.86)
        }
    }

    /// Màu đổ bóng phần thân dưới và các chi tiết phụ kiện robot.
    var shade: PetColor {
        switch self {
        case .pearl: return PetColor(red: 0.84, green: 0.85, blue: 0.90)
        case .lemon: return PetColor(red: 0.97, green: 0.83, blue: 0.30)
        case .peach: return PetColor(red: 0.98, green: 0.64, blue: 0.50)
        case .rose:  return PetColor(red: 0.95, green: 0.54, blue: 0.68)
        case .lilac: return PetColor(red: 0.69, green: 0.59, blue: 0.96)
        case .sky:   return PetColor(red: 0.43, green: 0.67, blue: 0.97)
        case .mint:  return PetColor(red: 0.40, green: 0.83, blue: 0.66)
        }
    }
}

/// Cấu hình ngoại hình tổng hợp của thú cưng.
struct PetLook: Equatable {
    var style: PetStyle
    var shape: PetShape
    var palette: PetPalette

    /// Ngoại hình mặc định: Phong cách tối giản, thân tròn, màu ngọc trai.
    static let standard = PetLook(style: .minimal, shape: .ball, palette: .pearl)
}

// MARK: - 2. Trạng thái Cảm xúc & Sự kiện Tương tác (Moods & Reactions)

/// Tâm trạng và biểu cảm cơ bản của thú cưng.
enum PetMood: String, CaseIterable, Identifiable {
    case exhausted, sleeping, charging, muted, downloadError
    case idle
    case happy
    case wink
    case love
    case sleepy
    case determined
    case surprised
    case searching
    case thinking
    case confused
    /// Tỉnh táo cảnh giác khi hệ thống đang giữ máy không ngủ (Keep Awake).
    case alert

    var id: String { rawValue }
}

/// Nhãn ngắn xuất hiện cùng hoạt cảnh trên notch/capsule.
enum PetStatusCue: String, Identifiable {
    case greeting, downloaded, lowBattery, charging, downloadError, dancing, love, sleeping, muted, ready

    var id: String { rawValue }

    @MainActor
    func title(using l10n: L10n) -> String {
        switch self {
        case .greeting: l10n.string(vi: "Xin chào", en: "Hello")
        case .downloaded: l10n.string(vi: "Tải xong", en: "Downloaded")
        case .lowBattery: l10n.string(vi: "Pin yếu", en: "Low battery")
        case .charging: l10n.string(vi: "Đang sạc", en: "Charging")
        case .downloadError: l10n.string(vi: "Tải lỗi", en: "Download error")
        case .dancing: l10n.string(vi: "Quẩy nhạc", en: "Dance")
        case .love: l10n.string(vi: "Yêu bạn", en: "Love")
        case .sleeping: l10n.string(vi: "Ngủ ngon", en: "Sleeping")
        case .muted: l10n.string(vi: "Đã tắt mic", en: "Mic muted")
        case .ready: l10n.string(vi: "Sẵn sàng", en: "Ready")
        }
    }

    var symbol: String {
        switch self {
        case .greeting: "hand.wave.fill"
        case .downloaded: "arrow.down.circle.fill"
        case .lowBattery: "battery.25percent"
        case .charging: "bolt.fill"
        case .downloadError: "exclamationmark.arrow.triangle.2.circlepath"
        case .dancing: "music.note"
        case .love: "heart.fill"
        case .sleeping: "moon.zzz.fill"
        case .muted: "mic.slash.fill"
        case .ready: "sparkles"
        }
    }
}

/// Vị trí cánh tai thỏ nơi thú cưng đậu (trái hoặc phải camera).
enum PetSide: String, CaseIterable, Identifiable {
    case left
    case right

    var id: String { rawValue }
}

/// Tần suất thú cưng tự động đi dạo qua đảo Dynamic Island.
enum PetVisitFrequency: String, CaseIterable, Identifiable {
    case rare
    case normal
    case frequent

    var id: String { rawValue }

    /// Khoảng thời gian chờ ngẫu nhiên giữa các lần đi dạo (giây).
    var delay: ClosedRange<TimeInterval> {
        switch self {
        case .rare:     return 600...1200
        case .normal:   return 240...540
        case .frequent: return 90...180
        }
    }
}

/// Các phản ứng cảm xúc ngắn của thú cưng khi có sự kiện hệ thống.
enum PetReaction: String, CaseIterable {
    /// Ăn mừng khi hoàn tất tác vụ (tải xong file, agent xong việc).
    case celebrate
    /// Thể hiện yêu thương khi được cắm sạc hoặc người dùng xoa đầu vuốt ve.
    case love
    /// Ngạc nhiên, mắt mở to khi chuông hẹn giờ đổ.
    case surprised
    /// Chớp mắt nhanh như ánh đèn flash khi chụp màn hình.
    case flash
    /// Bối rối, nghiêng đầu khi gặp lỗi hoặc tải thất bại.
    case confused
    /// Vui mừng tỉnh giấc khi máy Mac được mở khóa.
    case wakeUp
    /// Ngáp ngủ khi tắt chế độ giữ thức hoặc khi pin yếu.
    case yawn
    /// Hào hứng nhón chân khi kích hoạt chống ngủ hoặc bật microphone.
    case perk
    /// Nhảy tưng bừng hai nhịp khi đến sự kiện lịch hẹn.
    case bounce
    /// Thu mình im lặng khi microphone vừa được tắt.
    case hush
    /// Tập trung sẵn sàng khi bấm bắt đầu đồng hồ bấm giờ.
    case ready
    /// Nhún nhảy nhịp nhàng theo điệu nhạc đang phát.
    case groove

    /// Thời lượng phát hoạt cảnh phản ứng (giây).
    var length: TimeInterval {
        switch self {
        case .celebrate: return 1.0
        case .love:      return 1.4
        case .surprised: return 0.9
        case .flash:     return 0.5
        case .confused:  return 1.2
        case .wakeUp:    return 1.6
        case .yawn:      return 1.2
        case .perk:      return 1.0
        case .bounce:    return 1.0
        case .hush:      return 1.0
        case .ready:     return 1.0
        case .groove:    return 1.6
        }
    }
}

/// Sự kiện phản ứng được phát cho thú cưng hiển thị.
struct PetReactionEvent: Equatable {
    let id: UUID
    let reaction: PetReaction
    let start: CFTimeInterval
}

// MARK: - 3. Cấu trúc Khuôn mặt & Biểu cảm Mắt (Facial Layout & Expressions)

/// Hình thái tạo hình của từng mắt.
enum PetEye: Equatable {
    case open, closed, happy, heart, sleepy, wide, squint
    /// Mắt sắc sảo, mí mắt nghiêng quyết tâm.
    case determined

    /// Xác định mắt có khả năng chớp ngẫu nhiên khi mở hay không.
    var blinks: Bool {
        switch self {
        case .open, .wide, .squint: return true
        default: return false
        }
    }
}

/// Trạng thái biểu cảm đầy đủ gồm hai mắt, hướng nhìn và góc nghiêng đầu.
struct PetExpression: Equatable {
    var left: PetEye
    var right: PetEye
    /// Hướng nhìn của mắt tính theo tỷ lệ kích thước thân (trục Y hướng xuống).
    var gaze: CGPoint = .zero
    /// Độ nghiêng đầu tính bằng radian theo chiều kim đồng hồ.
    var tilt: CGFloat = 0.0

    /// Mắt chỉ chớp khi cả hai mắt đang ở trạng thái mở.
    var blinks: Bool { left.blinks && right.blinks }
}

extension PetMood {
    /// Biểu cảm mắt và cử chỉ tương ứng với từng tâm trạng của thú cưng.
    var expression: PetExpression {
        switch self {
        case .downloadError:
            return PetExpression(left: .wide, right: .squint, tilt: 0.14)
        case .exhausted:
            return PetExpression(left: .sleepy, right: .sleepy, tilt: 0.18)
        case .sleeping:
            return PetExpression(left: .closed, right: .closed, tilt: 0.08)
        case .charging:
            return PetExpression(left: .happy, right: .happy)
        case .muted:
            return PetExpression(left: .open, right: .open)
        case .idle:
            return PetExpression(left: .open, right: .open)
        case .happy:
            return PetExpression(left: .happy, right: .happy, gaze: CGPoint(x: 0, y: -0.02))
        case .wink:
            return PetExpression(left: .open, right: .happy, tilt: -0.08)
        case .love:
            return PetExpression(left: .heart, right: .heart)
        case .sleepy:
            return PetExpression(left: .sleepy, right: .sleepy, gaze: CGPoint(x: 0, y: 0.03), tilt: 0.05)
        case .determined:
            return PetExpression(left: .determined, right: .determined)
        case .surprised:
            return PetExpression(left: .wide, right: .wide, gaze: CGPoint(x: 0, y: -0.02))
        case .searching:
            return PetExpression(left: .open, right: .open, gaze: CGPoint(x: 0.05, y: 0))
        case .thinking:
            return PetExpression(left: .squint, right: .open, gaze: CGPoint(x: 0.06, y: -0.06), tilt: -0.10)
        case .confused:
            return PetExpression(left: .open, right: .squint, gaze: CGPoint(x: -0.03, y: 0.01), tilt: 0.14)
        case .alert:
            return PetExpression(left: .wide, right: .wide)
        }
    }
}

/// Tỷ lệ bố cục các chi tiết mắt và điểm bóng sáng trên khuôn mặt thú cưng.
struct PetFaceLayout: Equatable {
    let leftEye: CGPoint
    let rightEye: CGPoint
    let eyeSize: CGSize
    let shineCenter: CGPoint
    let shineRadii: CGSize
    let shineAngle: CGFloat
}

extension PetLook {
    /// Tính toán bố cục khuôn mặt dựa trên phong cách và hình dáng thân.
    var face: PetFaceLayout {
        if style == .robot {
            return PetFaceLayout(
                leftEye: CGPoint(x: 0.36, y: 0.63),
                rightEye: CGPoint(x: 0.64, y: 0.63),
                eyeSize: CGSize(width: 0.085, height: 0.16),
                shineCenter: CGPoint(x: 0.27, y: 0.34),
                shineRadii: CGSize(width: 0.07, height: 0.04),
                shineAngle: -0.3
            )
        }
        switch shape {
        case .ball:
            return PetFaceLayout(
                leftEye: CGPoint(x: 0.36, y: 0.50),
                rightEye: CGPoint(x: 0.64, y: 0.50),
                eyeSize: CGSize(width: 0.10, height: 0.20),
                shineCenter: CGPoint(x: 0.31, y: 0.29),
                shineRadii: CGSize(width: 0.085, height: 0.055),
                shineAngle: -0.5
            )
        case .squircle:
            return PetFaceLayout(
                leftEye: CGPoint(x: 0.35, y: 0.53),
                rightEye: CGPoint(x: 0.65, y: 0.53),
                eyeSize: CGSize(width: 0.10, height: 0.20),
                shineCenter: CGPoint(x: 0.24, y: 0.28),
                shineRadii: CGSize(width: 0.08, height: 0.05),
                shineAngle: -0.55
            )
        }
    }
}

// MARK: - 4. Dựng hình Vector CoreGraphics (Geometry & Vector Paths)

/// Bộ sinh đường dẫn hình học vector (CoreGraphics) cho thân thể, mắt và chi tiết thú cưng.
enum PetGeometry {
    /// Số lượng đỉnh đồng nhất dùng để biến đổi mượt mà giữa các hình dạng mắt.
    static let eyeCurveCount = 24

    /// Dựng đường viền thân thể cho thú cưng theo hình dạng đã chọn.
    static func body(_ shape: PetShape, size: CGFloat) -> CGPath {
        let path = CGMutablePath()
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * size, y: y * size) }

        switch shape {
        case .ball:
            path.addEllipse(in: CGRect(x: 0.08 * size, y: 0.12 * size, width: 0.84 * size, height: 0.84 * size))
        case .squircle:
            let steps = 72
            let exponent: CGFloat = 2.0 / 3.4
            for index in 0..<steps {
                let theta = CGFloat(index) / CGFloat(steps) * 2.0 * .pi
                let cosT = cos(theta), sinT = sin(theta)
                let px = 0.5 + 0.43 * (cosT < 0 ? -1.0 : 1.0) * pow(abs(cosT), exponent)
                let py = 0.55 + 0.40 * (sinT < 0 ? -1.0 : 1.0) * pow(abs(sinT), exponent)
                if index == 0 {
                    path.move(to: point(px, py))
                } else {
                    path.addLine(to: point(px, py))
                }
            }
            path.closeSubpath()
        }
        return path
    }

    /// Tập hợp các thành phần đồ họa của thú cưng robot.
    struct Robot {
        let head: CGPath
        let ears: CGPath
        let antenna: CGPath
        let bulb: CGPath
        let visor: CGPath
    }

    /// Độ lệch trục Y của trọng tâm thú cưng so với khung bao để căn giữa chính xác.
    static func figureOffset(_ look: PetLook) -> CGFloat {
        let bounds: CGRect
        if look.style == .robot {
            let parts = robot(size: 1.0)
            bounds = [parts.ears, parts.antenna, parts.bulb]
                .reduce(parts.head.boundingBoxOfPath) { $0.union($1.boundingBoxOfPath) }
        } else {
            bounds = body(look.shape, size: 1.0).boundingBoxOfPath
        }
        return bounds.midY - 0.5
    }

    /// Dựng các thành phần vector chi tiết của robot với kích cỡ cho trước.
    static func robot(size: CGFloat) -> Robot {
        func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
            CGRect(x: x * size, y: y * size, width: width * size, height: height * size)
        }
        func rounded(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
            CGPath(roundedRect: rect, cornerWidth: radius * size, cornerHeight: radius * size, transform: nil)
        }

        let ears = CGMutablePath()
        ears.addPath(rounded(rect(0.05, 0.50, 0.08, 0.20), 0.035))
        ears.addPath(rounded(rect(0.87, 0.50, 0.08, 0.20), 0.035))

        return Robot(
            head: rounded(rect(0.12, 0.26, 0.76, 0.68), 0.20),
            ears: ears,
            antenna: rounded(rect(0.475, 0.12, 0.05, 0.16), 0.025),
            bulb: CGPath(ellipseIn: rect(0.43, 0.04, 0.14, 0.14), transform: nil),
            visor: rounded(rect(0.20, 0.44, 0.60, 0.38), 0.15)
        )
    }

    /// Dựng đốm sáng bóng mờ (highlight) nghiêng theo bề mặt thân.
    static func shine(_ face: PetFaceLayout, size: CGFloat) -> CGPath {
        var transform = CGAffineTransform(translationX: face.shineCenter.x * size, y: face.shineCenter.y * size)
            .rotated(by: face.shineAngle)
        let radii = CGSize(width: face.shineRadii.width * size, height: face.shineRadii.height * size)
        return CGPath(
            ellipseIn: CGRect(x: -radii.width, y: -radii.height, width: radii.width * 2, height: radii.height * 2),
            transform: &transform
        )
    }

    /// Dựng đường nét hoàn chỉnh cho mắt quanh tâm toạ độ tương ứng.
    static func eye(_ eye: PetEye, size: CGSize, center: CGPoint, right: Bool) -> CGPath {
        let points = eyePoints(eye, size: size, right: right).map {
            CGPoint(x: $0.x + center.x, y: $0.y + center.y)
        }
        return smoothClosedPath(points)
    }

    /// Tạo mảng toạ độ đỉnh theo chiều kim đồng hồ chuẩn hoá cho hình thái mắt.
    static func eyePoints(_ eye: PetEye, size: CGSize, right: Bool) -> [CGPoint] {
        let width = max(0.5, size.width), height = max(0.5, size.height)
        var outline: [CGPoint]

        switch eye {
        case .open:
            outline = stadium(width: width, height: height, center: .zero)
        case .closed:
            outline = stadium(width: width * 1.5, height: width * 0.45, center: CGPoint(x: 0, y: height * 0.12))
        case .squint:
            outline = stadium(width: width, height: height * 0.55, center: CGPoint(x: 0, y: height * 0.08))
        case .wide:
            outline = ellipse(radii: CGSize(width: width * 0.8, height: width * 0.8), center: CGPoint(x: 0, y: -height * 0.02))
        case .happy:
            outline = arch(span: width * 2.1, rise: height * 0.42, thickness: width * 0.55, top: -height * 0.18)
        case .heart:
            outline = heart(width: width * 2.0, height: width * 1.8, center: CGPoint(x: 0, y: -height * 0.02))
        case .sleepy:
            outline = lid(width: width * 1.25, top: height * 0.02, depth: height * 0.38)
        case .determined:
            outline = clipBelow(
                stadium(width: width, height: height, center: .zero),
                from: CGPoint(x: -width / 2.0, y: -height * 0.30),
                to: CGPoint(x: width / 2.0, y: height * 0.02)
            )
        }

        if right {
            outline = outline.map { CGPoint(x: -$0.x, y: $0.y) }
        }
        return resample(outline, count: eyeCurveCount)
    }

    // MARK: - Thuật toán Tạo hình học Vector Chi tiết

    private static let denseResolution = 96

    /// Dựng hình con nhộng bo tròn hai đầu (Stadium).
    private static func stadium(width: CGFloat, height: CGFloat, center: CGPoint) -> [CGPoint] {
        let radius = min(width, height) / 2.0
        let rect = CGRect(x: center.x - width / 2.0, y: center.y - height / 2.0, width: width, height: height)
        return roundedRect(rect, radius: radius)
    }

    /// Dựng hình chữ nhật bo góc với số lượng điểm dày đặc.
    private static func roundedRect(_ rect: CGRect, radius: CGFloat) -> [CGPoint] {
        let corners: [(CGPoint, CGFloat)] = [
            (CGPoint(x: rect.maxX - radius, y: rect.minY + radius), -.pi / 2.0),
            (CGPoint(x: rect.maxX - radius, y: rect.maxY - radius), 0),
            (CGPoint(x: rect.minX + radius, y: rect.maxY - radius), .pi / 2.0),
            (CGPoint(x: rect.minX + radius, y: rect.minY + radius), .pi)
        ]
        var points: [CGPoint] = []
        let steps = denseResolution / 4
        for (cornerCenter, startAngle) in corners {
            for step in 0...steps {
                let angle = startAngle + CGFloat(step) / CGFloat(steps) * .pi / 2.0
                points.append(CGPoint(x: cornerCenter.x + radius * cos(angle), y: cornerCenter.y + radius * sin(angle)))
            }
        }
        return points
    }

    /// Dựng đường elip tham số.
    private static func ellipse(radii: CGSize, center: CGPoint) -> [CGPoint] {
        (0..<denseResolution).map { index in
            let angle = -CGFloat.pi / 2.0 + CGFloat(index) / CGFloat(denseResolution) * 2.0 * .pi
            return CGPoint(x: center.x + radii.width * cos(angle), y: center.y + radii.height * sin(angle))
        }
    }

    /// Dựng vòm cong mắt cười hai đầu bo tròn.
    private static func arch(span: CGFloat, rise: CGFloat, thickness: CGFloat, top: CGFloat) -> [CGPoint] {
        let halfSpan = max(0.1, span / 2.0 - thickness / 2.0)
        let safeRise = max(0.1, rise)
        let arcRadius = (halfSpan * halfSpan + safeRise * safeRise) / (2.0 * safeRise)
        let apex = top + thickness / 2.0
        let arcCenter = CGPoint(x: 0, y: apex + arcRadius)
        let reach = asin(min(1.0, halfSpan / arcRadius))

        func arcPoint(_ angle: CGFloat, _ r: CGFloat) -> CGPoint {
            CGPoint(x: arcCenter.x + r * sin(angle), y: arcCenter.y - r * cos(angle))
        }

        let steps = denseResolution / 3
        var points: [CGPoint] = []
        for step in 0...steps {
            let progress = CGFloat(step) / CGFloat(steps)
            points.append(arcPoint(-reach + progress * reach * 2.0, arcRadius + thickness / 2.0))
        }

        let rightEnd = arcPoint(reach, arcRadius)
        for step in 1..<12 {
            let angle = reach + CGFloat(step) / 12.0 * .pi
            points.append(CGPoint(x: rightEnd.x + thickness / 2.0 * sin(angle), y: rightEnd.y - thickness / 2.0 * cos(angle)))
        }

        for step in 0...steps {
            let progress = CGFloat(step) / CGFloat(steps)
            points.append(arcPoint(reach - progress * reach * 2.0, arcRadius - thickness / 2.0))
        }

        let leftEnd = arcPoint(-reach, arcRadius)
        for step in 1..<12 {
            let angle = -reach + .pi + CGFloat(step) / 12.0 * .pi
            points.append(CGPoint(x: leftEnd.x + thickness / 2.0 * sin(angle), y: leftEnd.y - thickness / 2.0 * cos(angle)))
        }

        return points
    }

    /// Dựng đường nét trái tim chuẩn hoá tham số.
    private static func heart(width: CGFloat, height: CGFloat, center: CGPoint) -> [CGPoint] {
        let rawPoints: [CGPoint] = (0..<denseResolution).map { index in
            let theta = CGFloat(index) / CGFloat(denseResolution) * 2.0 * .pi
            let x = 16.0 * pow(sin(theta), 3)
            let y = 13.0 * cos(theta) - 5.0 * cos(2.0 * theta) - 2.0 * cos(3.0 * theta) - cos(4.0 * theta)
            return CGPoint(x: x, y: y)
        }
        let minY = rawPoints.map(\.y).min() ?? 0, maxY = rawPoints.map(\.y).max() ?? 1
        let midY = (minY + maxY) / 2.0
        return rawPoints.map {
            CGPoint(
                x: center.x + $0.x / 32.0 * width,
                y: center.y - ($0.y - midY) / (maxY - minY) * height
            )
        }
    }

    /// Dựng mắt buồn ngủ với mí trên ngang và cung tròn phía dưới.
    private static func lid(width: CGFloat, top: CGFloat, depth: CGFloat) -> [CGPoint] {
        let halfWidth = width / 2.0
        var points: [CGPoint] = []
        let flatSteps = denseResolution / 4
        for step in 0...flatSteps {
            points.append(CGPoint(x: -halfWidth + CGFloat(step) / CGFloat(flatSteps) * width, y: top))
        }
        let roundSteps = denseResolution - flatSteps
        for step in 1..<roundSteps {
            let angle = CGFloat(step) / CGFloat(roundSteps) * .pi
            points.append(CGPoint(x: halfWidth * cos(angle), y: top + depth * sin(angle)))
        }
        return points
    }

    /// Cắt xén đa giác lồi nằm dưới đường thẳng nối giữa hai điểm.
    private static func clipBelow(_ points: [CGPoint], from: CGPoint, to: CGPoint) -> [CGPoint] {
        func evaluateSide(_ point: CGPoint) -> CGFloat {
            (to.x - from.x) * (point.y - from.y) - (to.y - from.y) * (point.x - from.x)
        }
        var clipped: [CGPoint] = []
        for index in points.indices {
            let current = points[index]
            let next = points[(index + 1) % points.count]
            let sideA = evaluateSide(current), sideB = evaluateSide(next)
            if sideA >= 0 { clipped.append(current) }
            if (sideA >= 0) != (sideB >= 0) {
                let fraction = sideA / (sideA - sideB)
                clipped.append(CGPoint(
                    x: current.x + (next.x - current.x) * fraction,
                    y: current.y + (next.y - current.y) * fraction
                ))
            }
        }
        return clipped.count >= 3 ? clipped : points
    }

    // MARK: - Tái lấy mẫu & Làm mịn Spline (Resampling & Splines)

    /// Lấy mẫu lại đường bao thành số lượng điểm đều nhau, bắt đầu từ đỉnh cao nhất trên trục đối xứng.
    static func resample(_ outline: [CGPoint], count: Int) -> [CGPoint] {
        guard outline.count >= 3, count >= 3 else { return outline }
        var points = outline

        // Đảm bảo hướng xoay thuận chiều kim đồng hồ (diện tích dương khi Y hướng xuống)
        var area: CGFloat = 0
        for index in points.indices {
            let p1 = points[index], p2 = points[(index + 1) % points.count]
            area += p1.x * p2.y - p2.x * p1.y
        }
        if area < 0 { points.reverse() }

        // Tìm điểm giao cắt trục X = 0 cao nhất làm điểm gốc
        var startAnchor: (index: Int, point: CGPoint)?
        for index in points.indices {
            let p1 = points[index], p2 = points[(index + 1) % points.count]
            guard (p1.x <= 0 && p2.x > 0) || (p1.x >= 0 && p2.x < 0) || p1.x == 0 else { continue }
            let fraction = p2.x == p1.x ? 0 : -p1.x / (p2.x - p1.x)
            let crossing = CGPoint(x: 0, y: p1.y + (p2.y - p1.y) * fraction)
            if startAnchor == nil || crossing.y < startAnchor!.point.y {
                startAnchor = (index, crossing)
            }
        }

        guard let start = startAnchor else { return Array(points.prefix(count)) }
        var loop = [start.point]
        for offset in 1...points.count {
            loop.append(points[(start.index + offset) % points.count])
        }
        loop.append(start.point)

        // Tính khoảng cách tích luỹ giữa các đoạn thẳng
        var distances: [CGFloat] = [0]
        for index in 1..<loop.count {
            let segmentDistance = hypot(loop[index].x - loop[index - 1].x, loop[index].y - loop[index - 1].y)
            distances.append(distances[index - 1] + segmentDistance)
        }

        let totalLength = distances.last ?? 0
        guard totalLength > 0 else { return Array(repeating: start.point, count: count) }

        var sampledPoints: [CGPoint] = []
        var segmentIndex = 1
        for step in 0..<count {
            let targetDist = totalLength * CGFloat(step) / CGFloat(count)
            while segmentIndex < distances.count - 1, distances[segmentIndex] < targetDist {
                segmentIndex += 1
            }
            let span = distances[segmentIndex] - distances[segmentIndex - 1]
            let fraction = span > 0 ? (targetDist - distances[segmentIndex - 1]) / span : 0
            let p1 = loop[segmentIndex - 1], p2 = loop[segmentIndex]
            sampledPoints.append(CGPoint(
                x: p1.x + (p2.x - p1.x) * fraction,
                y: p1.y + (p2.y - p1.y) * fraction
            ))
        }
        return sampledPoints
    }

    /// Dựng đường cong Spline bậc 3 (Catmull-Rom) đóng khép kín qua các điểm kiểm soát.
    static func smoothClosedPath(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        let count = points.count
        guard count >= 3 else { return path }
        path.move(to: points[0])
        for index in 0..<count {
            let pPrev = points[(index - 1 + count) % count]
            let pCurr = points[index]
            let pNext = points[(index + 1) % count]
            let pAfter = points[(index + 2) % count]
            let control1 = CGPoint(x: pCurr.x + (pNext.x - pPrev.x) / 6.0, y: pCurr.y + (pNext.y - pPrev.y) / 6.0)
            let control2 = CGPoint(x: pNext.x - (pAfter.x - pCurr.x) / 6.0, y: pNext.y - (pAfter.y - pCurr.y) / 6.0)
            path.addCurve(to: pNext, control1: control1, control2: control2)
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - 5. Động học Quỹ đạo Chuyển động (Motion & Kinematics Engine)

/// Chuyến đi dạo hoặc xuất hiện của thú cưng qua thanh đảo Dynamic Island.
struct PetVisit: Equatable {
    /// Loại hành trình chuyển động của thú cưng.
    enum Kind: Equatable {
        /// Đi một vòng quanh đảo và quay lại vị trí ban đầu.
        case lap
        /// Băng ngang từ đầu bên này sang đầu bên kia của đảo.
        case pass

        /// Xác định hành trình kết thúc ở vị trí khuất tầm nhìn (sau camera hoặc ngoài biên).
        var endsOutOfSight: Bool {
            self == .pass
        }
    }

    let id: UUID
    let kind: Kind
    let greeting: PetMood
    let start: CFTimeInterval

    var duration: TimeInterval { PetMotion.duration(of: kind) }
}

/// Không gian quỹ đạo di chuyển của thú cưng dọc theo thanh tai thỏ hoặc thanh đảo nổi.
struct PetTrack: Equatable {
    var width: CGFloat
    var height: CGFloat
    var size: CGFloat
    var rest: CGFloat
    var hidden: ClosedRange<CGFloat>?
    var baseline: CGFloat
    var ceiling: CGFloat = 0.0
    var mirrored = false
    var scale: CGFloat = 1.0

    /// Tính độ cao bước nhảy an toàn, không để đầu thú cưng chạm vào mép trên màn hình.
    func hop(_ share: CGFloat) -> CGFloat {
        min(size * share, max(scale, baseline - size / 2.0 - ceiling - (hidden == nil ? 1.0 : 2.0) * scale))
    }

    /// Toạ độ vị trí ẩn nấp sau camera với khoảng cách an toàn `margin`.
    func behindCamera(_ hidden: ClosedRange<CGFloat>, margin: CGFloat) -> CGFloat {
        hidden.lowerBound + size / 2.0 + margin * scale
    }

    /// Tạo bản sao quỹ đạo phóng to theo tỷ lệ xem trước trong Cài đặt.
    func scaled(by factor: CGFloat) -> PetTrack {
        PetTrack(
            width: width * factor,
            height: height * factor,
            size: size * factor,
            rest: rest * factor,
            hidden: hidden.map { ($0.lowerBound * factor)...($0.upperBound * factor) },
            baseline: baseline * factor,
            ceiling: ceiling * factor,
            mirrored: mirrored,
            scale: self.scale * factor
        )
    }

    /// Trả về quỹ đạo chuẩn hoá với vị trí đứng nghỉ bên cánh trái.
    var leftSide: PetTrack {
        guard mirrored else { return self }
        var left = self
        left.mirrored = false
        left.rest = width - rest
        return left
    }

    /// Vị trí điểm chào hỏi xa ở cánh đối diện của camera.
    var farSpot: CGFloat {
        guard let hidden else { return min(width - size * 0.8, rest + width * 0.22) }
        return hidden.upperBound + (hidden.lowerBound - rest)
    }
}

/// Quỹ đạo hoạt ảnh hoàn chỉnh gồm chuỗi khung hình toạ độ, độ nảy và độ co giãn đàn hồi.
struct PetPath: Equatable {
    var keyTimes: [Double] = []
    var x: [CGFloat] = []
    var lift: [CGFloat] = []
    /// Giá trị dương làm bẹp thân khi tiếp đất, giá trị âm kéo dài thân khi nhảy cao.
    var squash: [CGFloat] = []
    /// Góc nhìn của mắt theo phương ngang (-1.0 đến 1.0).
    var gaze: [CGFloat] = []
    var duration: TimeInterval = 0.0
    /// Khoảng thời gian xuất hiện biểu cảm chào hỏi.
    var greeting: ClosedRange<TimeInterval> = 0...0
}

/// Bộ động cơ tính toán và kết xuất hoạt ảnh động học (Kinematics) cho thú cưng.
enum PetMotion {
    static let lapDuration: TimeInterval = 3.6
    static let passDuration: TimeInterval = 3.4

    /// Tính tổng thời lượng của một hành trình di chuyển.
    static func duration(of kind: PetVisit.Kind) -> TimeInterval {
        switch kind {
        case .lap: return lapDuration
        case .pass: return passDuration
        }
    }

    /// Tính toán quỹ đạo chuyển động chi tiết dựa trên loại hành trình và thông số đường chạy.
    static func path(for kind: PetVisit.Kind, on track: PetTrack) -> PetPath {
        guard track.mirrored else {
            switch kind {
            case .lap: return lap(on: track)
            case .pass: return pass(on: track)
            }
        }

        var mirroredPath = self.path(for: kind, on: track.leftSide)
        mirroredPath.x = mirroredPath.x.map { track.width - $0 }
        mirroredPath.gaze = mirroredPath.gaze.map { -$0 }
        return mirroredPath
    }

    // MARK: - Các Bước Chuyển Động Vi Mô (Kinematic Steps)

    private enum MotionStep {
        case stay(TimeInterval, bounces: Int = 0)
        case hop(to: CGFloat, TimeInterval, height: CGFloat)
        case walk(to: CGFloat, TimeInterval)
        case jump(to: CGFloat)
    }

    static func lap(on track: PetTrack) -> PetPath {
        let size = track.size
        let offstageRight = track.width + size
        let offstageLeft = -size
        var steps: [MotionStep] = [.stay(0.18)]
        if let hidden = track.hidden {
            steps += [
                .hop(to: track.behindCamera(hidden, margin: 2), 0.34, height: track.hop(0.24)),
                .walk(to: hidden.upperBound - size / 2.0 - 2.0 * track.scale, 0.50),
                .hop(to: track.farSpot, 0.34, height: track.hop(0.24))
            ]
        } else {
            steps += [.hop(to: track.farSpot, 0.60, height: track.hop(0.3)), .stay(0.58)]
        }
        steps += [
            .stay(0.94, bounces: 2),
            .walk(to: offstageRight, 0.40),
            .jump(to: offstageLeft),
            .hop(to: track.rest, 0.52, height: track.hop(0.26))
        ]
        var path = sample(steps, start: track.rest, track: track, duration: lapDuration)
        let greetStart: TimeInterval = track.hidden == nil ? 0.78 : 1.30
        path.greeting = greetStart...(greetStart + 1.0)
        return path
    }

    static func pass(on track: PetTrack) -> PetPath {
        let size = track.size
        var steps: [MotionStep] = [
            .stay(0.20),
            .hop(to: track.rest, 0.42, height: track.hop(0.26)),
            .stay(0.88, bounces: 2)
        ]
        if let hidden = track.hidden {
            steps += [
                .hop(to: track.behindCamera(hidden, margin: 2), 0.34, height: track.hop(0.24)),
                .walk(to: hidden.upperBound - size / 2.0 - 2.0 * track.scale, 0.50),
                .hop(to: track.farSpot, 0.34, height: track.hop(0.24)),
                .stay(0.22)
            ]
        } else {
            steps += [.hop(to: track.farSpot, 0.60, height: track.hop(0.3)), .stay(0.80)]
        }
        steps += [.walk(to: track.width + size, 0.40)]
        var path = sample(steps, start: -size, track: track, duration: passDuration)
        path.greeting = 0.55...1.55
        return path
    }

    // MARK: - Bộ lấy mẫu Keyframe Động học (60 FPS Kinematics Sampler)

    private static func sample(
        _ steps: [MotionStep],
        start: CGFloat,
        track: PetTrack,
        duration: TimeInterval
    ) -> PetPath {
        let sampleRate: Double = 60.0
        var path = PetPath()
        var currentTime: TimeInterval = 0
        var currentPosition = start
        var landingImpact: (squash: CGFloat, time: TimeInterval) = (0, 0)

        func recordFrame(_ x: CGFloat, lift: CGFloat, squash: CGFloat, gaze: CGFloat) {
            let recoveryFactor = landingImpact.squash * CGFloat(max(0, 1.0 - (currentTime - landingImpact.time) / 0.14))
            path.keyTimes.append(min(1.0, currentTime / duration))
            path.x.append(x)
            path.lift.append(lift)
            path.squash.append(squash != 0 ? squash : recoveryFactor)
            path.gaze.append(gaze)
        }

        recordFrame(currentPosition, lift: 0, squash: 0, gaze: 0)

        for step in steps {
            switch step {
            case .jump(let targetPosition):
                currentPosition = targetPosition
                recordFrame(currentPosition, lift: 0, squash: 0, gaze: 0.05)

            case .stay(let length, let bounces):
                let frameCount = max(1, Int((length * sampleRate).rounded()))
                for frame in 1...frameCount {
                    let progress = CGFloat(frame) / CGFloat(frameCount)
                    currentTime += length / Double(frameCount)
                    let bounceWave = bounces > 0 ? abs(sin(progress * .pi * CGFloat(bounces))) : 0
                    recordFrame(currentPosition, lift: bounceWave * track.hop(0.16), squash: 0, gaze: 0)
                }

            case .hop(let targetPosition, let length, let hopHeight):
                let origin = currentPosition
                let frameCount = max(2, Int((length * sampleRate).rounded()))
                let direction: CGFloat = targetPosition >= origin ? 1.0 : -1.0
                for frame in 1...frameCount {
                    let progress = CGFloat(frame) / CGFloat(frameCount)
                    currentTime += length / Double(frameCount)
                    // Gia tốc mềm mại (Hermite cubic easing)
                    let easedProgress = progress * progress * (3.0 - 2.0 * progress)
                    // Co giãn đàn hồi khi dậm nhảy và tiếp đất
                    let squashEffect: CGFloat = progress < 0.2
                        ? -0.12 * (1.0 - progress / 0.2)
                        : progress > 0.88
                            ? 0.14 * (progress - 0.88) / 0.12
                            : 0
                    let parabolicArc = hopHeight * 4.0 * progress * (1.0 - progress)
                    recordFrame(
                        origin + (targetPosition - origin) * easedProgress,
                        lift: parabolicArc,
                        squash: squashEffect,
                        gaze: 0.05 * direction
                    )
                }
                currentPosition = targetPosition
                landingImpact = (0.14, currentTime)

            case .walk(let targetPosition, let length):
                let origin = currentPosition
                let frameCount = max(2, Int((length * sampleRate).rounded()))
                let direction: CGFloat = targetPosition >= origin ? 1.0 : -1.0
                for frame in 1...frameCount {
                    let progress = CGFloat(frame) / CGFloat(frameCount)
                    currentTime += length / Double(frameCount)
                    // Nhún nhẹ chân khi bước đi
                    let bobbing = abs(sin(progress * .pi * 3.0)) * track.hop(0.06)
                    recordFrame(
                        origin + (targetPosition - origin) * progress,
                        lift: bobbing,
                        squash: 0,
                        gaze: 0.05 * direction
                    )
                }
                currentPosition = targetPosition
            }
        }

        if currentTime < duration {
            currentTime = duration
            recordFrame(currentPosition, lift: 0, squash: 0, gaze: 0)
        } else if let lastIndex = path.keyTimes.indices.last {
            path.keyTimes[lastIndex] = 1.0
        }
        path.duration = duration
        return path
    }
}

// MARK: - 6. Tiện ích & Hỗ trợ Hệ thống (System Coordinator)

/// Bộ điều phối hỗ trợ quản lý cấu hình, định thời gian và tính toán kích cỡ SenseBar cho thú cưng.
enum PetEngine {
    /// Media đang phát luôn giữ pet tỉnh; chỉ ngủ sau đủ năm phút kể từ lần tương tác/mở máy.
    static func idleMood(systemIdle: TimeInterval, sinceReset: TimeInterval, isMediaPlaying: Bool) -> PetMood {
        guard !isMediaPlaying, systemIdle.isFinite, sinceReset.isFinite else { return .idle }
        return min(systemIdle, max(0, sinceReset)) >= 300 ? .sleeping : .idle
    }

    /// Danh sách các tâm trạng chào đón thân thiện.
    static let greetings: [PetMood] = [.happy, .wink, .love]

    /// Khoảng thời gian giữa hai lần chớp mắt ngẫu nhiên.
    static func blinkInterval(lowPower: Bool) -> ClosedRange<TimeInterval> {
        lowPower ? 5.2...12.8 : 2.6...6.4
    }

    /// Tỷ lệ liếc nhìn sang bên trước khi chớp mắt (khoảng 25% các lần chớp mắt).
    static let glanceChance = 0.25

    /// Khoảng nghỉ tối thiểu giữa hai lần vuốt ve.
    static let pettingRepeatInterval: TimeInterval = 30

    // MARK: - Truy xuất Cấu hình UserDefaults

    /// Lấy tần suất đi dạo từ cấu hình đã lưu.
    static func visitFrequency(in defaults: UserDefaults = .standard) -> PetVisitFrequency {
        PetVisitFrequency(rawValue: defaults.string(forKey: DefaultsKey.petVisitFrequency) ?? "") ?? .normal
    }

    // MARK: - Toạ độ & Tương tác Con trỏ Chuột

    /// Tính toán hướng nhìn của mắt hướng về phía con trỏ chuột.
    static func pointerGaze(from center: CGPoint, to pointer: CGPoint, size: CGFloat) -> CGPoint {
        guard size > 0 else { return .zero }
        let dx = (pointer.x - center.x) / (size * 3.0)
        let dy = (pointer.y - center.y) / (size * 2.0)
        return CGPoint(x: max(-1.0, min(1.0, dx)) * 0.08, y: max(-1.0, min(1.0, dy)) * 0.05)
    }

    /// Sinh khoảng thời gian chờ ngẫu nhiên cho chuyến đi dạo tiếp theo.
    static func nextVisitDelay(
        _ frequency: PetVisitFrequency = visitFrequency(),
        random: Double = Double.random(in: 0...1)
    ) -> TimeInterval {
        let range = frequency.delay
        return range.lowerBound + (range.upperBound - range.lowerBound) * min(1.0, max(0.0, random))
    }

    /// Chọn ngẫu nhiên một biểu cảm chào đón thân thiện.
    static func greeting(random: Double = Double.random(in: 0..<1)) -> PetMood {
        greetings[min(greetings.count - 1, max(0, Int(random * Double(greetings.count))))]
    }

    /// Kích thước cạnh vuông bao quanh thú cưng tính theo chiều cao thanh đảo.
    static func size(stripHeight: CGFloat, floats: Bool) -> CGFloat {
        floats ? max(10.0, min(18.0, stripHeight - 6.0)) : max(12.0, min(20.0, stripHeight - 12.0))
    }

    /// Khởi tạo thông số quỹ đạo di chuyển phù hợp cho thanh tai thỏ hoặc đảo nổi.
    static func track(
        stripWidth: CGFloat,
        stripHeight: CGFloat,
        wing: CGFloat,
        cameraWidth: CGFloat,
        floats: Bool,
        bodyHeight: CGFloat,
        side: PetSide = .left
    ) -> PetTrack {
        if floats {
            let petSize = self.size(stripHeight: bodyHeight, floats: true)
            return PetTrack(
                width: stripWidth,
                height: stripHeight,
                size: petSize,
                rest: stripWidth / 2.0,
                hidden: nil,
                baseline: stripHeight / 2.0,
                ceiling: max(0, (stripHeight - bodyHeight) / 2.0)
            )
        }

        let petSize = self.size(stripHeight: stripHeight, floats: false)
        // Căn vị trí thú cưng ở tâm an toàn của cánh tai thỏ (cách đều vai cong và mép camera)
        let shoulderInset: CGFloat = 12.0
        let safeWingCenter = (shoulderInset + wing) / 2.0
        let restX = (side == .right) ? (stripWidth - safeWingCenter) : safeWingCenter

        return PetTrack(
            width: stripWidth,
            height: stripHeight,
            size: petSize,
            rest: restX,
            hidden: wing...(wing + cameraWidth),
            baseline: stripHeight / 2.0 + 0.5,
            mirrored: side == .right
        )
    }

}
