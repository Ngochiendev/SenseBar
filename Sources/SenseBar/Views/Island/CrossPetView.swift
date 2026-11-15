import AppKit
import SwiftUI

/// Giữ nguyên giao diện gọi pet cũ; chỉ chuyển sang ảnh khi người dùng chọn CrossPet.
struct PetView: View {
    var look: PetLook
    var mood: PetMood = .idle
    var size: CGFloat
    var idles = true
    var cue: PetCue?
    var cueID = 0
    var reaction: PetReaction?

    var body: some View {
        if let character = look.style.crossPet {
            CrossPetSprite(character: character, mood: mood, reaction: reaction)
                .frame(width: size, height: size)
        } else {
            NativePetView(look: look, mood: mood, size: size, idles: idles,
                          cue: cue, cueID: cueID, reaction: reaction)
        }
    }
}

struct PetTrackView: View {
    var look: PetLook
    var track: PetTrack
    var rests: Bool
    var visit: PetVisit?
    var mood: PetMood = .idle
    var reaction: PetReactionEvent?
    var awake = true

    var body: some View {
        if let character = look.style.crossPet {
            CrossPetSprite(character: character, mood: awake ? mood : .sleeping,
                           reaction: reaction?.reaction, track: track, rests: rests)
                .frame(width: track.width, height: track.height)
        } else {
            NativePetTrackView(look: look, track: track, rests: rests, visit: visit,
                               mood: mood, reaction: reaction, awake: awake)
        }
    }
}

struct CrossPetSprite: NSViewRepresentable {
    let character: CrossPetCharacter
    var mood: PetMood = .idle
    var reaction: PetReaction?
    var head = true
    var track: PetTrack?
    var rests = true

    func makeNSView(context: Context) -> CrossPetHostView { CrossPetHostView(frame: .zero) }

    func updateNSView(_ host: CrossPetHostView, context: Context) {
        host.update(character: character, mood: mood, reaction: reaction, head: head,
                    track: track, rests: rests)
    }
}

/// Hiển thị một ảnh WebP tĩnh, căn sát đáy và thay biểu cảm theo trạng thái.
@MainActor
final class CrossPetHostView: NSView {
    private let sprite = CALayer()
    private let cameraMask = CAShapeLayer()
    private var track: PetTrack?
    private var rests = true
    private var base: CGImage?
    private var fullBodyReferenceSize = CGSize(width: 1, height: 1)
    private var signature = ""

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        sprite.contentsGravity = .resizeAspect
        sprite.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull(),
                          "anchorPoint": NSNull(), "onOrderIn": NSNull(), "onOrderOut": NSNull()]
        sprite.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        sprite.minificationFilter = .trilinear
        sprite.magnificationFilter = .linear
        layer?.addSublayer(sprite)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { nil }
    func update(character: CrossPetCharacter, mood: PetMood, reaction: PetReaction?, head: Bool,
                track: PetTrack?, rests: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let pose = character.pose(mood: mood, reaction: reaction, compact: head)
        let next = "\(character.rawValue)/\(pose)/\(head)"
        guard signature != next || self.track != track || self.rests != rests else { return }
        if signature != next {
            signature = next
            base = CrossPetArtwork.image(character, pose: pose, head: head)
            if !head, let reference = CrossPetArtwork.image(character, pose: "idle", head: false) {
                fullBodyReferenceSize = CGSize(width: reference.width, height: reference.height)
            }
            sprite.contents = base
        }
        self.track = track
        self.rests = rests
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        sprite.contentsScale = window?.backingScaleFactor ?? 2
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let track {
            let imageSize = base.map { CGSize(width: $0.width, height: $0.height) } ?? CGSize(width: 1, height: 1)
            let frame = CrossPetLayout.compactFrame(image: imageSize, track: track, rests: rests)
            sprite.anchorPoint = CGPoint(x: 0.5, y: 1)
            sprite.bounds = CGRect(origin: .zero, size: frame.size)
            sprite.position = CGPoint(x: frame.midX, y: frame.maxY)
            if let camera = track.hidden {
                let mask = CGMutablePath()
                mask.addRect(CGRect(x: 0, y: 0, width: camera.lowerBound, height: bounds.height))
                mask.addRect(CGRect(x: camera.upperBound, y: 0, width: max(0, bounds.width - camera.upperBound), height: bounds.height))
                cameraMask.frame = bounds
                cameraMask.path = mask
                layer?.mask = cameraMask
            } else { layer?.mask = nil }
        } else {
            let sourceSize = fullBodyReferenceSize
            let factor = min(bounds.width / sourceSize.width, bounds.height / sourceSize.height)
            sprite.anchorPoint = CGPoint(x: 0.5, y: 1)
            sprite.bounds = CGRect(x: 0, y: 0, width: sourceSize.width * factor, height: sourceSize.height * factor)
            sprite.position = CGPoint(x: bounds.midX, y: bounds.maxY)
            layer?.mask = nil
        }
        CATransaction.commit()
    }
}
