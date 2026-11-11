import Foundation

struct SessionOwner: Equatable {
    let pid: Int32
    let bundle: String
    var processStart: UInt64 = 0
}

struct SessionTicket: Equatable {
    let pid: Int32
    let revision: UUID
}

struct MediaRecord: Equatable {
    let identifier: String?
    let title: String
    let artist: String
    let album: String

    init?(_ fields: [String: Any]) {
        func text(_ key: String) -> String {
            (fields[key] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        title = text("kMRMediaRemoteNowPlayingInfoTitle")
        guard !title.isEmpty else { return nil }
        let item = text("kMRMediaRemoteNowPlayingInfoContentItemIdentifier")
        identifier = item.isEmpty || item.utf8.count > 512 || item.contains("\0") ? nil : item
        artist = text("kMRMediaRemoteNowPlayingInfoArtist")
        album = text("kMRMediaRemoteNowPlayingInfoAlbum")
    }
}

/// Value-only state machine. The bridge worker owns its mutations.
struct SessionLedger {
    struct Observation {
        let owner: SessionOwner
        let record: MediaRecord?
        let playing: Bool
        let presentationBundle: String

        init(owner: SessionOwner, record: MediaRecord?, playing: Bool, presentationBundle: String? = nil) {
            self.owner = owner
            self.record = record
            self.playing = playing
            self.presentationBundle = presentationBundle ?? owner.bundle
        }
    }

    private(set) var owner: SessionOwner?
    private(set) var record: MediaRecord?
    private(set) var ticket: SessionTicket?

    func choose(_ observations: [Observation], systemPID: Int32?, preferredBundleID: String = "auto") -> SessionOwner? {
        let eligible = observations.filter { entry in
            guard entry.owner.pid > 0, entry.record != nil else { return false }
            return preferredBundleID == "auto"
                || entry.presentationBundle.caseInsensitiveCompare(preferredBundleID) == .orderedSame
                || entry.owner.bundle.caseInsensitiveCompare(preferredBundleID) == .orderedSame
        }
        // Keep the followed session stable, but any playing session outranks pause.
        // App names/categories do not determine who owns the island.
        func rank(_ entry: Observation) -> Int {
            (entry.playing ? 1_000 : 0) + (entry.owner == owner ? 100 : 0)
                + (entry.owner.pid == systemPID ? 10 : 0)
        }
        return eligible.sorted {
            let left = rank($0), right = rank($1)
            return left == right ? $0.owner.pid < $1.owner.pid : left > right
        }.first?.owner
    }

    mutating func present(owner nextOwner: SessionOwner?, record nextRecord: MediaRecord?) -> SessionTicket? {
        guard let nextOwner, let nextRecord else {
            owner = nil
            record = nil
            ticket = nil
            return nil
        }
        if nextOwner != owner || nextRecord != record || ticket == nil {
            ticket = SessionTicket(pid: nextOwner.pid, revision: UUID())
        }
        owner = nextOwner
        record = nextRecord
        return ticket
    }

    func accepts(_ request: SessionTicket, owner freshOwner: SessionOwner, record freshRecord: MediaRecord?) -> Bool {
        request == ticket && owner == freshOwner && record == freshRecord && freshRecord != nil
    }

    static func playing(state: UInt32?, rate: Double) -> Bool {
        if state == 1 { return true }
        if let state, (2...4).contains(state) { return false }
        return rate.isFinite && rate > 0
    }
}
