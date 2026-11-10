import AppKit
import SwiftUI

/// Thẻ cài đặt và tương tác thú cưng
public struct PetCard: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var mascotService = PetService.shared

    @AppStorage(DefaultsKey.petEnabled) private var enabled = true
    @AppStorage(DefaultsKey.petStyle) private var style = "minimal"
    @AppStorage(DefaultsKey.petShape) private var shape = "ball"
    @AppStorage(DefaultsKey.petPalette) private var palette = "pearl"
    @AppStorage(DefaultsKey.petSide) private var side = "left"
    @AppStorage(DefaultsKey.petVisits) private var visits = true
    @AppStorage(DefaultsKey.petReactions) private var reactions = true
    @AppStorage(DefaultsKey.petHidesWhenIdle) private var hidesWhenIdle = false

    // Danh sách hình dáng được giữ lại (đã loại bỏ egg và pill theo yêu cầu)
    private let allowedShapes: [PetShape] = [.ball, .squircle]

    public init() {}

    private var currentLook: PetLook {
        let validShape: PetShape = (shape == "squircle") ? .squircle : .ball
        return PetLook(
            style: PetStyle(rawValue: style) ?? .minimal,
            shape: validShape,
            palette: PetPalette(rawValue: palette) ?? .pearl
        )
    }

    private var currentSide: PetSide {
        PetSide(rawValue: side) ?? .left
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerRow

            if enabled {
                VStack(alignment: .leading, spacing: 12) {
                    // Sân khấu mô phỏng tương tác
                    PetStageCard(
                        look: currentLook,
                        side: currentSide,
                        awake: enabled
                    )

                    Divider().opacity(0.4)

                    // Ngoại hình (Appearance)
                    appearanceControls

                    Divider().opacity(0.4)

                    // Vị trí & Hành vi (Behavior)
                    behaviorControls
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .panelCard()
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: enabled)
        .animation(.spring(response: 0.25, dampingFraction: 0.84), value: style)
    }

    // MARK: - Header Row

    private var headerRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "pawprint.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.pink)
                .frame(width: 24, height: 24)
                .background(Color.pink.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(l10n.string(vi: "Thú cưng (Companion)", en: "Companion"))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.primary)
                Text(l10n.string(
                    vi: "Bạn nhỏ sống trên Tai thỏ & Đảo động",
                    en: "A little friend on your Dynamic Island"
                ))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            Toggle("", isOn: $enabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.mini)
        }
    }

    // MARK: - Appearance Controls

    private var appearanceControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(l10n.string(vi: "Ngoại hình", en: "Appearance"), systemImage: "paintpalette.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.primary)
                Spacer()
            }

            // Kiểu: Tối giản vs Robot
            HStack(spacing: 8) {
                styleButton(
                    id: "minimal",
                    title: l10n.string(vi: "Tối giản", en: "Minimal"),
                    styleItem: .minimal
                )
                styleButton(
                    id: "robot",
                    title: "Robot",
                    styleItem: .robot
                )
            }

            // Hình dáng (chỉ hiện khi không phải Robot: Hình tròn vs Vuông bo)
            if currentLook.style != .robot {
                HStack(spacing: 8) {
                    Text(l10n.string(vi: "Hình dạng:", en: "Shape:"))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 6) {
                        ForEach(allowedShapes) { item in
                            let isSelected = currentLook.shape == item
                            Button {
                                withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                                    shape = item.rawValue
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    PetView(
                                        look: PetLook(style: .minimal, shape: item, palette: currentLook.palette),
                                        size: 15,
                                        idles: false
                                    )
                                    .frame(width: 15, height: 15)

                                    Text(item == .ball ? l10n.string(vi: "Hình tròn", en: "Ball") : l10n.string(vi: "Vuông bo", en: "Squircle"))
                                        .font(.system(size: 10.5, weight: isSelected ? .bold : .medium))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4.5)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.04))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(isSelected ? Color.accentColor.opacity(0.7) : Color.clear, lineWidth: 1.2)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Spacer()
                }
                .transition(.opacity)
            }

            // Bảng màu 7 swatches
            HStack(spacing: 8) {
                Text(l10n.string(vi: "Màu sắc:", en: "Color:"))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    ForEach(PetPalette.allCases) { item in
                        let isSelected = currentLook.palette == item
                        Button {
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                                palette = item.rawValue
                            }
                        } label: {
                            Circle()
                                .fill(LinearGradient(
                                    colors: [Color(cgColor: item.light.cgColor), Color(cgColor: item.shade.cgColor)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ))
                                .frame(width: 17, height: 17)
                                .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 0.5))
                                .padding(2.5)
                                .overlay(Circle().strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.8))
                        }
                        .buttonStyle(.plain)
                        .help(item.rawValue.capitalized)
                    }
                }
                Spacer()
            }
        }
    }

    private func styleButton(id: String, title: String, styleItem: PetStyle) -> some View {
        let isSelected = style == id
        return Button {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                style = id
            }
        } label: {
            HStack(spacing: 6) {
                PetView(
                    look: PetLook(style: styleItem, shape: currentLook.shape, palette: currentLook.palette),
                    size: 20,
                    idles: false
                )
                .frame(width: 20, height: 20)
                .frame(width: 38, height: 24)
                .background(Color.black, in: Capsule())

                Text(title)
                    .font(.system(size: 11, weight: isSelected ? .bold : .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.7) : Color.clear, lineWidth: 1.2)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Behavior Controls

    private var behaviorControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(l10n.string(vi: "Vị trí & Hoạt động", en: "Position & Behavior"), systemImage: "slider.horizontal.3")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.primary)
                Spacer()
            }

            // Chọn cánh trái / phải cạnh camera
            HStack(spacing: 8) {
                Text(l10n.string(vi: "Vị trí đậu:", en: "Resting side:"))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    sideButton(target: .left, title: l10n.string(vi: "Cánh trái", en: "Left"))
                    sideButton(target: .right, title: l10n.string(vi: "Cánh phải", en: "Right"))
                }
                Spacer()
            }

            // 2 Toggle rút gọn, không rườm rà
            HStack {
                Label(l10n.string(vi: "Thỉnh thoảng đi dạo", en: "Stroll now and then"), systemImage: "figure.walk")
                    .font(.system(size: 10.5, weight: .medium))
                Spacer()
                Toggle("", isOn: $visits)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.mini)
            }

            HStack {
                Label(l10n.string(vi: "Ẩn khi không dùng", en: "Hide when idle"), systemImage: "eye.slash")
                    .font(.system(size: 10.5, weight: .medium))
                Spacer()
                Toggle("", isOn: $hidesWhenIdle)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.mini)
            }
        }
    }

    private func sideButton(target: PetSide, title: String) -> some View {
        let isSelected = currentSide == target
        return Button {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                side = target.rawValue
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: target == .left ? "arrow.left.to.line" : "arrow.right.to.line")
                    .font(.system(size: 9, weight: .semibold))
                Text(title)
                    .font(.system(size: 10.5, weight: isSelected ? .bold : .medium))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4.5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.7) : Color.clear, lineWidth: 1.2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Mini Stage Card

private struct PetStageCard: View {
    let look: PetLook
    let side: PetSide
    let awake: Bool

    @State private var visit: PetVisit?
    @State private var reaction: PetReactionEvent?
    @State private var captionTitle: String?
    @State private var captionIcon: String?
    @State private var playingWork: DispatchWorkItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Sân khấu mô phỏng Menu Bar + Notch cao 74pt
            GeometryReader { proxy in
                PetStage(
                    look: look,
                    side: side,
                    awake: awake,
                    visit: visit,
                    reaction: reaction,
                    caption: captionTitle != nil ? (captionTitle!, captionIcon ?? "sparkles") : nil,
                    width: proxy.size.width
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    playRandom()
                }
            }
            .frame(height: 74)

            // Lưới phản hồi cảm xúc rút gọn
            FlowLayoutLite(spacing: 5.5) {
                actionChip("Chào", icon: "hand.wave.fill", color: .blue) { playVisit() }
                actionChip("Tải", icon: "arrow.down.circle.fill", color: .teal) { playReaction(.celebrate, title: "Tải xong", icon: "arrow.down.circle.fill") }
                actionChip("Pin yếu", icon: "battery.25percent", color: .red) { playReaction(.yawn, title: "Pin yếu", icon: "battery.25percent") }
                actionChip("Sạc pin", icon: "bolt.fill", color: .yellow) { playReaction(.love, title: "Đang sạc pin", icon: "bolt.fill") }
                actionChip("Tải lỗi", icon: "exclamationmark.triangle.fill", color: .orange) { playReaction(.confused, title: "Tải lỗi", icon: "exclamationmark.triangle.fill") }
                actionChip("Sự kiện", icon: "calendar", color: .blue) { playReaction(.bounce, title: "Sự kiện", icon: "calendar") }
            }

            // Ghi chú vuốt ve
            HStack(spacing: 4) {
                Image(systemName: "hand.point.up.left")
                    .font(.system(size: 8.5))
                    .foregroundStyle(.secondary)
                Text("Nhấp vào để gọi thú cưng đi dạo. Rê giữ chuột 1s trên đảo để vuốt ve.")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private func actionChip(_ title: String, icon: String, color: Color = .primary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(color == .primary ? Color.accentColor : color)
                Text(title)
                    .font(.system(size: 9.5, weight: .medium))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3.5)
            .background(Color.primary.opacity(0.05), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func playRandom() {
        playVisit()
    }

    private func playVisit() {
        guard awake else { return }
        playingWork?.cancel()
        captionTitle = "Chào"
        captionIcon = "hand.wave.fill"

        let started = PetVisit(id: UUID(), kind: .lap, greeting: .wink, start: CACurrentMediaTime())
        visit = started
        PetService.shared.triggerVisit(kind: .lap, force: true)
        let work = DispatchWorkItem {
            if visit?.id == started.id {
                visit = nil
                captionTitle = nil
            }
        }
        playingWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + started.duration, execute: work)
    }

    private func playReaction(_ reactionKind: PetReaction, title: String, icon: String) {
        guard awake else { return }
        playingWork?.cancel()
        captionTitle = title
        captionIcon = icon

        let event = PetReactionEvent(id: UUID(), reaction: reactionKind, start: CACurrentMediaTime())
        reaction = event
        PetService.shared.triggerReaction(reactionKind)
        let work = DispatchWorkItem {
            if reaction?.id == event.id {
                reaction = nil
                captionTitle = nil
            }
        }
        playingWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + reactionKind.length, execute: work)
    }
}

// MARK: - Stage

private struct PetStage: View {
    let look: PetLook
    let side: PetSide
    let awake: Bool
    let visit: PetVisit?
    let reaction: PetReactionEvent?
    let caption: (title: String, symbol: String)?
    let width: CGFloat

    var body: some View {
        let islandWidth: CGFloat = 148
        let islandHeight: CGFloat = 24
        let barHeight: CGFloat = 18
        let track = PetEngine.track(
            stripWidth: islandWidth,
            stripHeight: islandHeight,
            wing: 38,
            cameraWidth: 72,
            floats: false,
            bodyHeight: islandHeight,
            side: side
        )

        ZStack(alignment: .top) {
            // Nền Wallpaper gradient nhẹ
            LinearGradient(
                colors: [Color.accentColor.opacity(0.28), Color.accentColor.opacity(0.06)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Thanh Menu Bar giả lập
            Rectangle()
                .fill(Color.black.opacity(0.22))
                .frame(height: barHeight)

            // Notch Tai thỏ
            NotchAttachedShape(topShoulder: 8, bottomRadius: 10)
                .fill(Color.black)
                .frame(width: islandWidth, height: islandHeight)
                .overlay(alignment: .center) {
                    PetLens(diameter: 4.5)
                }
                .overlay(alignment: .top) {
                    PetTrackView(
                        look: look,
                        track: track,
                        rests: true,
                        visit: visit,
                        mood: .idle,
                        reaction: reaction,
                        awake: awake
                    )
                    .frame(width: track.width, height: track.height)
                }
                .overlay(alignment: .topLeading) {
                    if !awake {
                        PetSleepZs(
                            origin: CGPoint(x: track.rest, y: track.baseline - track.size * 0.05),
                            size: track.size,
                            toward: track.mirrored ? -1 : 1
                        )
                    }
                }

            // Nhãn caption khi phản ứng
            if let caption {
                Label(caption.title, systemImage: caption.symbol)
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.regularMaterial, in: Capsule())
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 4)
                    .transition(.opacity.combined(with: .offset(y: 3)))
            }
        }
        .frame(width: width, height: 74, alignment: .top)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.white.opacity(0.1), lineWidth: 0.8))
    }
}

// MARK: - Subcomponents

private struct PetLens: View {
    let diameter: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(Color(white: 0.085))
            Circle().fill(Color(red: 0.10, green: 0.11, blue: 0.19)).padding(diameter * 0.26)
            Circle().fill(Color.white.opacity(0.24)).frame(width: diameter * 0.2, height: diameter * 0.2)
                .offset(x: -diameter * 0.1, y: -diameter * 0.1)
        }
        .frame(width: diameter, height: diameter)
    }
}

private struct PetSleepZs: View {
    let origin: CGPoint
    let size: CGFloat
    let toward: CGFloat

    private static let period: TimeInterval = 2.7

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate / Self.period
            ZStack(alignment: .topLeading) {
                ForEach(0..<3, id: \.self) { index in
                    z(phase: (time + Double(index) / 3).truncatingRemainder(dividingBy: 1))
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func z(phase: Double) -> some View {
        let share = CGFloat(phase)
        return Text(verbatim: "z")
            .font(.system(size: size * 0.42, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .scaleEffect(0.5 + 0.6 * share)
            .opacity(0.8 * sin(Double.pi * phase))
            .position(
                x: origin.x + toward * size * (0.6 + 0.9 * share),
                y: origin.y - size * 0.62 * share
            )
    }
}

/// Lưới bọc các chip phản hồi linh hoạt tự xuống dòng
private struct FlowLayoutLite: Layout {
    var spacing: CGFloat = 5

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
