import AppKit
import Combine
import Foundation

extension Notification.Name {
    /// Nguồn tải nội bộ báo lỗi để thú cưng hiển thị phản ứng tương ứng.
    static let petDownloadFailed = Notification.Name("SenseBar.PetDownloadFailed")
}

/// Dịch vụ quản lý vòng đời và tương tác của thú cưng (trên tai thỏ Notch & Dynamic Island).
@MainActor
final class PetService: ObservableObject {
    static let shared = PetService()

    @Published private(set) var isEnabled: Bool = false
    @Published private(set) var visitsEnabled: Bool = true
    @Published private(set) var look: PetLook = .standard
    @Published private(set) var side: PetSide = .left
    @Published private(set) var mood: PetMood = .idle
    @Published private(set) var currentVisit: PetVisit?
    @Published private(set) var currentReaction: PetReactionEvent?
    @Published private(set) var currentStatusCue: PetStatusCue?
    var hasActivePresentation: Bool {
        currentReaction != nil || (!isMediaPlaying && (currentVisit != nil || mood == .sleeping))
    }
    private var activityTimer: Timer?
    private var sessionActive = true
    private var isMediaPlaying = false
    private var lastGreeting = Date.distantPast
    private var idleResetUptime = ProcessInfo.processInfo.systemUptime
    private var statusCueTask: Task<Void, Never>?
    private var automaticGreetingID: UUID?

    /// Hiển thị tia sét cùng hoạt cảnh vui khi cắm sạc hoặc bấm thử.
    func chargingConnected() { present(.charging, reaction: .love, cue: .charging) }

    /// Phản ứng khi tác vụ tải do SenseBar quản lý báo lỗi.
    func downloadFailed() { present(.downloadError, reaction: .confused, cue: .downloadError) }

    private var idleMood: PetMood {
        let systemIdle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .null)
        let sinceReset = max(0, ProcessInfo.processInfo.systemUptime - idleResetUptime)
        return PetEngine.idleMood(systemIdle: systemIdle, sinceReset: sinceReset, isMediaPlaying: isMediaPlaying)
    }

    private func startActivityMonitoring() {
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.publisher(for: NSWorkspace.willSleepNotification)
            .merge(with: workspace.publisher(for: NSWorkspace.sessionDidResignActiveNotification))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.sessionActive = false }.store(in: &cancellables)
        workspace.publisher(for: NSWorkspace.didWakeNotification)
            .merge(with: workspace.publisher(for: NSWorkspace.sessionDidBecomeActiveNotification))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.sessionActive = true
                self?.greet()
            }.store(in: &cancellables)
        NotificationCenter.default.publisher(for: .petDownloadFailed)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.downloadFailed() }.store(in: &cancellables)
        MusicService.shared.$track
            .map { $0?.isPlaying == true }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] playing in
                guard let self else { return }
                self.isMediaPlaying = playing
                if playing {
                    if let greetingID = self.automaticGreetingID, self.currentReaction?.id == greetingID {
                        self.currentReaction = nil
                        self.automaticGreetingID = nil
                        self.statusCueTask?.cancel()
                        self.currentStatusCue = nil
                        self.mood = .idle
                    }
                    self.visitTimer?.invalidate()
                    self.visitTimer = nil
                    self.currentVisit = nil
                    if self.mood == .sleeping { self.mood = .idle }
                    if self.currentStatusCue == .sleeping {
                        self.statusCueTask?.cancel()
                        self.currentStatusCue = nil
                    }
                } else {
                    self.idleResetUptime = ProcessInfo.processInfo.systemUptime
                    self.scheduleNextVisit()
                }
            }
            .store(in: &cancellables)
        if isEnabled { startIdleTimer(); greet() }
    }

    private func startIdleTimer() {
        guard activityTimer == nil else { return }
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isEnabled, self.sessionActive,
                      self.currentReaction == nil, self.currentVisit == nil else { return }
                let nextMood = self.idleMood
                if nextMood == .sleeping, self.mood != .sleeping { self.showStatus(.sleeping) }
                self.mood = nextMood
            }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        activityTimer = timer
    }

    private func greet() {
        guard isEnabled else { return }
        idleResetUptime = ProcessInfo.processInfo.systemUptime
        guard !isMediaPlaying, MusicService.shared.track?.isPlaying != true else { return }
        guard Date().timeIntervalSince(lastGreeting) > 10 else { return }
        lastGreeting = Date()
        present(.wink, reaction: .wakeUp, cue: .greeting, automatic: true)
    }

    private func present(_ nextMood: PetMood, reaction: PetReaction, cue: PetStatusCue, automatic: Bool = false) {
        guard isEnabled else { return }
        currentVisit = nil
        let event = PetReactionEvent(id: UUID(), reaction: reaction, start: CACurrentMediaTime())
        mood = nextMood
        currentReaction = event
        automaticGreetingID = automatic ? event.id : nil
        showStatus(cue)
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self, self.currentReaction?.id == event.id else { return }
            self.currentReaction = nil
            self.automaticGreetingID = nil
            self.mood = self.idleMood
        }
    }

    private func showStatus(_ cue: PetStatusCue) {
        statusCueTask?.cancel()
        currentStatusCue = cue
        statusCueTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(2_500)) } catch { return }
            self?.currentStatusCue = nil
        }
    }

    private var visitTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        syncPreferences()
        scheduleNextVisit()
        startPowerMonitoring()
        startActivityMonitoring()

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
                if !before.external && next.external { self.chargingConnected() }
                if let old = before.percent, let level = next.percent,
                   old > 20, level <= 20, !next.external { self.triggerReaction(.yawn) }
            }.store(in: &cancellables)
    }

    /// Đồng bộ cài đặt từ UserDefaults.
    func syncPreferences() {
        let defaults = UserDefaults.standard
        let wasEnabled = isEnabled
        isEnabled = defaults.bool(forKey: DefaultsKey.petEnabled)

        if !isEnabled {
            activityTimer?.invalidate()
            activityTimer = nil
            visitTimer?.invalidate()
            visitTimer = nil
            currentVisit = nil
            currentReaction = nil
            automaticGreetingID = nil
            currentStatusCue = nil
            statusCueTask?.cancel()
            mood = .idle
        }

        if isEnabled { startIdleTimer() }
        if !wasEnabled && isEnabled { greet() }

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
        guard !isMediaPlaying else { scheduleNextVisit(); return }
        guard force || (currentReaction == nil && idleMood != .sleeping) else { scheduleNextVisit(); return }
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
        let nextMood: PetMood
        let cue: PetStatusCue
        switch reaction {
        case .love: (nextMood, cue) = (.love, .love)
        case .wakeUp: (nextMood, cue) = (.wink, .greeting)
        case .confused: (nextMood, cue) = (.downloadError, .downloadError)
        case .yawn: (nextMood, cue) = (.exhausted, .lowBattery)
        case .hush: (nextMood, cue) = (.muted, .muted)
        case .ready: (nextMood, cue) = (.determined, .ready)
        case .celebrate: (nextMood, cue) = (.happy, .downloaded)
        case .groove: (nextMood, cue) = (.happy, .dancing)
        default: (nextMood, cue) = (.happy, .ready)
        }
        present(nextMood, reaction: reaction, cue: cue)
    }

    private func scheduleNextVisit() {
        visitTimer?.invalidate()
        visitTimer = nil
        guard isEnabled, visitsEnabled, !isMediaPlaying else { return }

        let delay = PetEngine.nextVisitDelay()
        visitTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isEnabled, self.visitsEnabled else { return }
                self.triggerVisit(kind: Bool.random() ? .lap : .pass)
            }
        }
    }
}
