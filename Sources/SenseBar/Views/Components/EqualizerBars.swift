import AppKit
import QuartzCore
import SwiftUI

// MARK: - NotchDecorativeClock (30fps CADisplayLink stepping)

@MainActor
final class DecorativeClock {
    static let rate: Float = 30

    private let step: (CFTimeInterval) -> Void
    private nonisolated(unsafe) var link: CADisplayLink?

    init(step: @escaping (CFTimeInterval) -> Void) {
        self.step = step
    }

    var isRunning: Bool { link != nil }

    func start(in view: NSView) {
        guard link == nil else { return }
        let target = Target(clock: self)
        let link = view.displayLink(target: target, selector: #selector(Target.fire(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(
            minimum: Self.rate / 2,
            maximum: Self.rate,
            preferred: Self.rate
        )
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    deinit {
        link?.invalidate()
    }

    @MainActor
    private final class Target: NSObject {
        weak var clock: DecorativeClock?
        init(clock: DecorativeClock) { self.clock = clock }
        @objc func fire(_ link: CADisplayLink) { clock?.step(link.targetTimestamp) }
    }

    static func swing(_ phase: Double) -> Double {
        let half = phase.truncatingRemainder(dividingBy: 2)
        let travelled = half < 0 ? half + 2 : half
        let out = travelled <= 1 ? travelled : 2 - travelled
        return (1 - cos(.pi * out)) / 2
    }
}

// MARK: - Native CALayer Equalizer (Stepped motion with organic heights)

public struct EqualizerBars: View {
    public var isPlaying: Bool = true
    public var bars: Int = 5
    public var barWidth: CGFloat = 2.2
    public var height: CGFloat = 14
    public var tint: Color = .white

    public init(isPlaying: Bool = true, bars: Int = 5, barWidth: CGFloat = 2.2, height: CGFloat = 14, tint: Color = .white) {
        self.isPlaying = isPlaying
        self.bars = bars
        self.barWidth = barWidth
        self.height = height
        self.tint = tint
    }

    public var body: some View {
        let count = max(1, bars)
        EqualizerBridge(
            animates: isPlaying,
            bars: count,
            barWidth: barWidth,
            height: height,
            tint: NSColor(tint)
        )
        .frame(width: CGFloat(count) * barWidth + CGFloat(count - 1) * barWidth * 0.85, height: height)
        .alignmentGuide(.firstTextBaseline) { $0[.bottom] }
        .alignmentGuide(.lastTextBaseline) { $0[.bottom] }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

private struct EqualizerBridge: NSViewRepresentable {
    let animates: Bool
    let bars: Int
    let barWidth: CGFloat
    let height: CGFloat
    let tint: NSColor

    func makeNSView(context: Context) -> EqualizerView {
        EqualizerView()
    }

    func updateNSView(_ view: EqualizerView, context: Context) {
        view.configure(
            animates: animates,
            bars: bars,
            barWidth: barWidth,
            height: height,
            tint: tint
        )
    }

    static func dismantleNSView(_ view: EqualizerView, coordinator: ()) {
        view.stop()
    }
}

final class EqualizerView: NSView {
    private nonisolated(unsafe) var visibilityObserver: NSObjectProtocol?
    private var bars: [CALayer] = []
    private var barWidth: CGFloat = 0
    private var height: CGFloat = 0
    private var animates = false
    private var swings: [(low: CGFloat, high: CGFloat, rise: Double, lead: Double)] = []
    private var motionStart: CFTimeInterval = 0
    private var joinedWave = false
    private lazy var clock = DecorativeClock { [weak self] time in self?.step(at: time) }
    private static let waveOrigin: CFTimeInterval = CACurrentMediaTime()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { nil }

    func configure(animates: Bool, bars count: Int, barWidth: CGFloat, height: CGFloat, tint: NSColor) {
        let count = max(1, count)
        self.animates = animates
        self.barWidth = barWidth
        self.height = height

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if bars.count != count {
            bars.forEach { $0.removeFromSuperlayer() }
            bars = (0..<count).map { _ in
                let bar = CALayer()
                layer?.addSublayer(bar)
                return bar
            }
        }
        for bar in bars {
            bar.backgroundColor = tint.cgColor
        }
        CATransaction.commit()
        updateBars()
    }

    func stop() {
        animates = false
        clock.stop()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let visibilityObserver { NotificationCenter.default.removeObserver(visibilityObserver) }
        visibilityObserver = window.map { window in
            NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification,
                object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateBars() }
            }
        }
        updateBars()
    }

    deinit {
        if let visibilityObserver { NotificationCenter.default.removeObserver(visibilityObserver) }
    }

    override func viewDidHide() { super.viewDidHide(); updateBars() }
    override func viewDidUnhide() { super.viewDidUnhide(); updateBars() }

    override func layout() {
        super.layout()
        updateBars()
    }

    private func updateBars() {
        let exposed = !isHiddenOrHasHiddenAncestor && window?.occlusionState.contains(.visible) == true
        let moving = animates && exposed
        let center = Double(bars.count - 1) / 2

        swings = bars.indices.map { index in
            let distance = abs(Double(index) - center) / max(1, center)
            let envelope = pow(1 - distance, 1.5)
            return (
                low: max(barWidth, height * (0.14 + envelope * 0.25)),
                high: max(barWidth, height * (0.14 + envelope * 0.88)),
                rise: .pi / (5.2 + Double(index) * 0.61),
                lead: Double(index) * 0.17
            )
        }

        let swinging = moving && swings.contains { $0.high > $0.low }
        if swinging, !joinedWave {
            motionStart = Self.waveOrigin
            joinedWave = true
        }

        let now = CACurrentMediaTime()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, bar) in bars.enumerated() {
            let resting = swinging ? swingHeight(index, at: now) : barWidth
            bar.bounds = CGRect(x: 0, y: 0, width: barWidth, height: resting)
            bar.position = CGPoint(x: CGFloat(index) * barWidth * 1.85 + barWidth / 2, y: bounds.midY)
            bar.cornerRadius = barWidth / 2
        }
        CATransaction.commit()

        if swinging {
            clock.start(in: self)
        } else {
            clock.stop()
        }
    }

    private func swingHeight(_ index: Int, at time: CFTimeInterval) -> CGFloat {
        guard index < swings.count else { return barWidth }
        let swing = swings[index]
        guard swing.high > swing.low else { return swing.low }
        let travel = DecorativeClock.swing((time - motionStart + swing.lead) / swing.rise)
        return swing.low + (swing.high - swing.low) * CGFloat(travel)
    }

    func step(at time: CFTimeInterval) {
        guard clock.isRunning else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, bar) in bars.enumerated() where index < swings.count {
            bar.bounds.size.height = swingHeight(index, at: time)
        }
        CATransaction.commit()
    }
}
