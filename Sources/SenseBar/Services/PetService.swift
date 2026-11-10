import AppKit
import Combine
import Foundation
import IOKit.ps
import SwiftUI

/// Dịch vụ quản lý vòng đời và tương tác của thú cưng (trên tai thỏ Notch & Dynamic Island).
@MainActor
final class PetService: ObservableObject {
    static let shared = PetService()

    @Published private(set) var isEnabled: Bool = true
    @Published private(set) var visitsEnabled: Bool = true
    @Published private(set) var look: PetLook = .standard
    @Published private(set) var side: PetSide = .left
    @Published private(set) var mood: PetMood = .idle
    @Published private(set) var currentVisit: PetVisit?
    @Published private(set) var currentReaction: PetReactionEvent?

    private var visitTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        syncPreferences()
        scheduleNextVisit()
        startPowerMonitoring()

        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncPreferences()
            }
            .store(in: &cancellables)
    }

    private func startPowerMonitoring() {
        MacPowerService.shared.$state.removeDuplicates()
            .scan((nil as MacPowerState?, nil as MacPowerState?)) { ($0.1, $1) }
            .sink { [weak self] before, next in
                guard let self, let before, let next else { return }
                if !before.external && next.external { self.react(.love) }
                if let old = before.percent, let level = next.percent,
                   old > 20, level <= 20, !next.external { self.react(.yawn) }
            }.store(in: &cancellables)
    }

    /// Đồng bộ cài đặt từ UserDefaults.
    func syncPreferences() {
        let defaults = UserDefaults.standard
        let wasEnabled = isEnabled
        isEnabled = defaults.bool(forKey: DefaultsKey.petEnabled)

        if !isEnabled {
            visitTimer?.invalidate()
            visitTimer = nil
            currentVisit = nil
            currentReaction = nil
            mood = .idle
        }

        let newVisits = defaults.bool(forKey: DefaultsKey.petVisits)
        if visitsEnabled != newVisits {
            visitsEnabled = newVisits
            if !newVisits {
                visitTimer?.invalidate()
                visitTimer = nil
                currentVisit = nil
            } else if isEnabled {
                scheduleNextVisit()
            }
        } else if !wasEnabled && isEnabled && visitsEnabled {
            scheduleNextVisit()
        }

        let styleStr = defaults.string(forKey: DefaultsKey.petStyle) ?? "minimal"
        let shapeStr = defaults.string(forKey: DefaultsKey.petShape) ?? "ball"
        let paletteStr = defaults.string(forKey: DefaultsKey.petPalette) ?? "pearl"
        let sideStr = defaults.string(forKey: DefaultsKey.petSide) ?? "left"

        look = PetLook(
            style: PetStyle(rawValue: styleStr) ?? .minimal,
            shape: PetShape(rawValue: shapeStr) ?? .ball,
            palette: PetPalette(rawValue: paletteStr) ?? .pearl
        )
        side = PetSide(rawValue: sideStr) ?? .left
    }

    /// Kích hoạt lượt đi dạo qua lại trên Notch hoặc Dynamic Island.
    /// - Parameters:
    ///   - kind: Kiểu đi dạo (qua lại hoặc nhảy).
    ///   - force: Bỏ qua kiểm tra cài đặt tắt đi dạo (dùng khi người dùng bấm thử nghiệm ở Cài đặt).
    func triggerVisit(kind: PetVisit.Kind = .lap, force: Bool = false) {
        guard isEnabled else { return }
        if !force && !visitsEnabled { return }

        let greeting = PetEngine.greeting()
        let visit = PetVisit(id: UUID(), kind: kind, greeting: greeting, start: CACurrentMediaTime())
        currentVisit = visit

        DispatchQueue.main.asyncAfter(deadline: .now() + visit.duration + 0.1) { [weak self] in
            guard let self, self.currentVisit?.id == visit.id else { return }
            self.currentVisit = nil
            if self.visitsEnabled {
                self.scheduleNextVisit()
            }
        }
    }

    /// Kích hoạt phản ứng cảm xúc của thú cưng (đồng bộ toàn hệ thống và Notch/Capsule).
    func triggerReaction(_ reaction: PetReaction) {
        guard isEnabled else { return }
        let event = PetReactionEvent(id: UUID(), reaction: reaction, start: CACurrentMediaTime())
        currentReaction = event

        switch reaction {
        case .love:
            mood = .love
        case .groove, .bounce, .celebrate:
            mood = .happy
        case .wakeUp:
            mood = .wink
        case .yawn, .hush:
            mood = .sleepy
        case .ready:
            mood = .determined
        default:
            mood = .happy
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + reaction.length) { [weak self] in
            guard let self else { return }
            if self.currentReaction?.id == event.id {
                self.currentReaction = nil
            }
            if self.mood != .idle {
                self.mood = .idle
            }
        }
    }

    /// Kích hoạt phản ứng cảm xúc tương thích ngược
    func react(_ reaction: PetReaction) {
        triggerReaction(reaction)
    }

    private func scheduleNextVisit() {
        visitTimer?.invalidate()
        visitTimer = nil
        guard isEnabled, visitsEnabled else { return }

        let delay = PetEngine.nextVisitDelay()
        visitTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isEnabled, self.visitsEnabled else { return }
                self.triggerVisit(kind: Bool.random() ? .lap : .pass)
            }
        }
    }
}
