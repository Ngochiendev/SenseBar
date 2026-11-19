import AppKit
import Foundation

/// Confined to the bridge worker; UI requests carry immutable session tickets.
final class MediaSessionCoordinator {
    nonisolated(unsafe) static let shared = MediaSessionCoordinator()
    private var ledger = SessionLedger()
    private var presented: MediaRemoteEndpoint?
    private let callbacks = DispatchQueue(label: "com.ngochiendev.sensebar.media-scan")
    private(set) var preferredBundleID: String = "auto"
    var isAutomatic: Bool { preferredBundleID == "auto" }
    private(set) var availableSources: [[String: Any]] = []
    private(set) var closedBrowserBundles: Set<String> = []

    func setPreferredSource(_ bundleID: String) {
        let normalized = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        preferredBundleID = normalized.isEmpty ? "auto" : normalized
        presented = nil
        _ = ledger.present(owner: nil, record: nil)
    }

    func choose() -> MediaRemoteEndpoint? {
        closedBrowserBundles = BrowserWindowSnapshot.closedBundles()
        let directory = MediaRemoteIO.discover()
        var seen = Set<Int32>()
        let preferred = [directory.current, ledger.owner?.pid].compactMap { $0 }
        let candidates = (preferred + directory.clients.map(\.pid)).filter { $0 > 0 && seen.insert($0).inserted }
        let endpoints: [MediaRemoteEndpoint] = candidates.prefix(16).compactMap { pid in
            let client = directory.clients.first { $0.pid == pid }
            guard var endpoint = MediaRemoteEndpoint(pid: pid, parentBundle: client?.parentBundle,
                                                    registeredBundle: client?.bundle), endpoint.alive,
                  !closedBrowserBundles.contains(endpoint.presentationBundle) else { return nil }
            endpoint.ownsSystemSession = pid == directory.current
            return endpoint
        }

        struct Reading {
            var fields: [String: Any] = [:]
            var state: UInt32?
        }
        let group = DispatchGroup()
        let readings = endpoints.map { endpoint -> RemoteResult<Reading> in
            let result = RemoteResult(Reading())
            group.enter()
            MediaRemoteIO.metadata(endpoint, artwork: false, queue: callbacks) { fields in
                result.update { $0.fields = fields as? [String: Any] ?? [:] }
                group.leave()
            }
            group.enter()
            MediaRemoteIO.state(endpoint, queue: callbacks) { state in
                result.update { $0.state = state }
                group.leave()
            }
            return result
        }
        _ = group.wait(timeout: .now() + 1)
        let observations = zip(endpoints, readings).map { endpoint, result in
            let read = result.read()
            let rate = (read.fields["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? NSNumber)?.doubleValue ?? 0
            return SessionLedger.Observation(owner: endpoint.owner, record: MediaRecord(read.fields),
                                             playing: SessionLedger.playing(state: read.state, rate: rate),
                                             presentationBundle: endpoint.presentationBundle)
        }

        var sources: [[String: Any]] = []
        var sourceIndexes: [String: Int] = [:]
        for (endpoint, observation) in zip(endpoints, observations) {
            guard observation.record != nil || observation.playing else { continue }
            let bundle = endpoint.presentationBundle
            guard !bundle.isEmpty else { continue }
            if let index = sourceIndexes[bundle] {
                if observation.playing { sources[index]["isPlaying"] = true }
                continue
            }
            let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first
                ?? NSRunningApplication(processIdentifier: endpoint.owner.pid)
            let name = app?.localizedName ?? bundle
            sourceIndexes[bundle] = sources.count
            sources.append(["bundleID": bundle, "appName": name, "isPlaying": observation.playing])
        }
        self.availableSources = sources.sorted {
            ($0["appName"] as? String ?? "") < ($1["appName"] as? String ?? "")
        }

        let choice = ledger.choose(observations, systemPID: directory.current, preferredBundleID: preferredBundleID)
        return endpoints.first(where: { $0.owner == choice })
    }

    func present(_ endpoint: MediaRemoteEndpoint?, fields: [String: Any]) -> SessionTicket? {
        presented = endpoint
        return ledger.present(owner: endpoint?.owner, record: MediaRecord(fields))
    }

    func perform(_ request: PlaybackRequest) -> Bool {
        guard let endpoint = presented, endpoint.alive, ledger.ticket == request.context else { return false }
        struct Validation {
            var record: MediaRecord?
            var state: UInt32?
            var commands: Set<Int32>?
        }
        let fresh = RemoteResult(Validation())
        let completion = DispatchGroup()
        completion.enter()
        MediaRemoteIO.metadata(endpoint, artwork: false, queue: callbacks) { fields in
            fresh.update { $0.record = (fields as? [String: Any]).flatMap(MediaRecord.init) }
            completion.leave()
        }
        completion.enter()
        MediaRemoteIO.state(endpoint, queue: callbacks) { state in
            fresh.update { $0.state = state }
            completion.leave()
        }
        completion.enter()
        MediaRemoteIO.commands(endpoint, queue: callbacks) { commands in
            fresh.update { $0.commands = commands }
            completion.leave()
        }
        guard completion.wait(timeout: .now() + 0.8) == .success else { return false }
        let reading = fresh.read()
        guard ledger.accepts(request.context, owner: endpoint.owner, record: reading.record) else { return false }
        let playing: Bool? = reading.state.flatMap { state in
            switch state { case 1: return true; case 2...4: return false; default: return nil }
        }
        if (request.command == 0 && playing == true) || (request.command == 1 && playing == false) { return true }
        guard let command = request.nativeCommand(supported: reading.commands, playing: playing) else { return false }
        return MediaRemoteIO.deliver(request, command: command, endpoint: endpoint, item: ledger.record?.identifier)
    }
}
