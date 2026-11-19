import AppKit
import ObjectiveC

/// Runtime boundary for Apple's optional MediaRemote interfaces.
struct MediaRemoteEndpoint {
    let owner: SessionOwner
    let presentationBundle: String
    let path: NSObject
    var ownsSystemSession = false

    var alive: Bool {
        guard MediaProcessIdentity.startTime(owner.pid) == owner.processStart else { return false }
        // WebKit helpers can outlive Safari; their cached session must not outlive the host app.
        if presentationBundle != owner.bundle {
            return NSRunningApplication.runningApplications(withBundleIdentifier: presentationBundle)
                .contains { !$0.isTerminated }
        }
        return true
    }

    init?(pid: Int32, parentBundle: String?, registeredBundle: String? = nil) {
        guard let identity = MediaProcessIdentity.owner(pid: pid, registeredBundle: registeredBundle),
              let clientType = NSClassFromString("MRClient"),
              let routeType = NSClassFromString("MRPlayerPath") else { return nil }
        let allocate = NSSelectorFromString("alloc")
        let initialize = NSSelectorFromString("initWithBundleIdentifier:")
        let local = NSSelectorFromString("localPlayerPath")
        guard class_getClassMethod(clientType, allocate) != nil,
              class_getInstanceMethod(clientType, initialize) != nil,
              class_getClassMethod(routeType, local) != nil else { return nil }
        guard let instance = (clientType as AnyObject).perform(allocate)?.takeRetainedValue(),
              let client = instance.perform(initialize, with: identity.bundle)?.takeUnretainedValue() as? NSObject,
              let template = (routeType as AnyObject).perform(local)?.takeUnretainedValue() as? NSCopying,
              let route = template.copy(with: nil) as? NSObject else { return nil }
        let process = NSSelectorFromString("setProcessIdentifier:")
        let attach = NSSelectorFromString("setClient:")
        let active = NSSelectorFromString("setPlayer:")
        guard client.responds(to: process), route.responds(to: attach), route.responds(to: active) else { return nil }
        typealias ProcessSetter = @convention(c) (AnyObject, Selector, Int32) -> Void
        let setter = unsafeBitCast(client.method(for: process), to: ProcessSetter.self)
        setter(client, process, pid)
        route.perform(attach, with: client)
        route.perform(active, with: nil)
        owner = identity
        path = route
        presentationBundle = MediaProcessIdentity.presentation(pid: pid, ownerBundle: identity.bundle, parentBundle: parentBundle)
    }
}

/// Callbacks can arrive after a deadline. Each read owns its storage until completion.
final class RemoteResult<Value> {
    private let lock = NSLock()
    private var value: Value

    init(_ initial: Value) { value = initial }
    func update(_ transform: (inout Value) -> Void) { lock.withLock { transform(&value) } }
    func read() -> Value { lock.withLock { value } }
}

struct MediaRemoteClient {
    let pid: Int32
    let bundle: String?
    let parentBundle: String?
}

enum MediaRemoteIO {
    private static let replies = DispatchQueue(label: "com.ngochiendev.sensebar.media-replies")

    static func constant(_ key: String) -> String? {
        guard let mediaRemoteHandle, let symbol = dlsym(mediaRemoteHandle, key) else { return nil }
        return symbol.assumingMemoryBound(to: NSString?.self).pointee as String?
    }

    static func discover(includeClients: Bool = true) -> (current: Int32?, clients: [MediaRemoteClient]) {
        typealias One = @convention(c) (DispatchQueue, @escaping @convention(block) (AnyObject?) -> Void) -> Void
        typealias Many = @convention(c) (DispatchQueue, @escaping @convention(block) (NSArray?) -> Void) -> Void
        typealias Process = @convention(c) (AnyObject) -> Int32
        typealias Parent = @convention(c) (AnyObject) -> Unmanaged<CFString>?
        let result = RemoteResult<(Int32?, [MediaRemoteClient])>((nil, []))
        let bundle = resolveSymbol(mediaRemoteHandle, "MRNowPlayingClientGetBundleIdentifier", as: Parent.self)
        let parent = resolveSymbol(mediaRemoteHandle, "MRNowPlayingClientGetParentAppBundleIdentifier", as: Parent.self)
        guard let process = resolveSymbol(mediaRemoteHandle, "MRNowPlayingClientGetProcessIdentifier", as: Process.self) else { return result.read() }
        func describe(_ client: AnyObject) -> MediaRemoteClient {
            MediaRemoteClient(pid: process(client), bundle: bundle?(client)?.takeUnretainedValue() as String?,
                              parentBundle: parent?(client)?.takeUnretainedValue() as String?)
        }
        let completion = DispatchGroup()
        if let one = resolveSymbol(mediaRemoteHandle, "MRMediaRemoteGetNowPlayingClient", as: One.self) {
            completion.enter()
            one(replies) { client in
                result.update {
                    $0.0 = client.map(process)
                    if let client { $0.1.append(describe(client)) }
                }
                completion.leave()
            }
        }
        if includeClients, let many = resolveSymbol(mediaRemoteHandle, "MRMediaRemoteGetNowPlayingClients", as: Many.self) {
            completion.enter()
            many(replies) { clients in
                let entries = (clients as? [AnyObject] ?? []).prefix(16).map(describe)
                result.update { $0.1.append(contentsOf: entries) }
                completion.leave()
            }
        }
        _ = completion.wait(timeout: .now() + 0.5)
        return result.read()
    }

    static func metadata(_ endpoint: MediaRemoteEndpoint, artwork: Bool, queue: DispatchQueue,
                         receive: @escaping (NSDictionary?) -> Void) {
        guard endpoint.alive else { receive(nil); return }
        playerMetadata(endpoint, artwork: artwork, queue: queue) { fields in
            if (fields as? [String: Any]).flatMap(MediaRecord.init) != nil {
                receive(fields)
                return
            }
            guard endpoint.ownsSystemSession, endpoint.alive,
                  discover(includeClients: false).current == endpoint.owner.pid,
                  let fetch = resolveSymbol(mediaRemoteHandle, "MRMediaRemoteGetNowPlayingInfo", as: CurrentInfo.self) else {
                receive(nil)
                return
            }
            fetch(queue) { fallback in
                // Global metadata is usable only while the same process owns it.
                guard endpoint.alive, discover(includeClients: false).current == endpoint.owner.pid else {
                    receive(nil)
                    return
                }
                receive(fallback)
            }
        }
    }

    private typealias CurrentInfo = @convention(c) (DispatchQueue, @escaping @convention(block) (NSDictionary?) -> Void) -> Void

    private static func playerMetadata(_ endpoint: MediaRemoteEndpoint, artwork: Bool, queue: DispatchQueue,
                                       receive: @escaping (NSDictionary?) -> Void) {
        typealias Fetch = @convention(c) (AnyObject, Bool, DispatchQueue,
            @escaping @convention(block) (NSDictionary?, UnsafeRawPointer?) -> Void) -> Void
        typealias Image = @convention(c) (UnsafeRawPointer) -> Unmanaged<CFData>?
        guard endpoint.alive, let fetch = resolveSymbol(mediaRemoteHandle, "MRMediaRemoteGetNowPlayingInfoForPlayer", as: Fetch.self) else { receive(nil); return }
        fetch(endpoint.path, artwork, queue) { fields, image in
            var payload = fields as? [String: Any]
            if artwork, let image, let copy = resolveSymbol(mediaRemoteHandle, "MRNowPlayingArtworkCopyImageData", as: Image.self) {
                payload?["kMRMediaRemoteNowPlayingInfoArtworkData"] = copy(image)?.takeRetainedValue() as Data?
            }
            receive(payload.map { $0 as NSDictionary })
        }
    }

    static func state(_ endpoint: MediaRemoteEndpoint, queue: DispatchQueue, receive: @escaping (UInt32?) -> Void) {
        typealias Fetch = @convention(c) (AnyObject, DispatchQueue, @escaping @convention(block) (UInt32) -> Void) -> Void
        guard endpoint.alive, let fetch = resolveSymbol(mediaRemoteHandle, "MRMediaRemoteGetPlaybackStateForPlayer", as: Fetch.self) else { receive(nil); return }
        fetch(endpoint.path, queue) { receive($0) }
    }

    static func commands(_ endpoint: MediaRemoteEndpoint, queue: DispatchQueue, receive: @escaping (Set<Int32>?) -> Void) {
        typealias Fetch = @convention(c) (AnyObject, DispatchQueue, @escaping @convention(block) (NSArray?) -> Void) -> Void
        typealias Identifier = @convention(c) (AnyObject) -> Int32
        typealias Enabled = @convention(c) (AnyObject) -> Bool
        guard endpoint.alive,
              let fetch = resolveSymbol(mediaRemoteHandle, "MRMediaRemoteGetSupportedCommandsForPlayer", as: Fetch.self),
              let identifier = resolveSymbol(mediaRemoteHandle, "MRMediaRemoteCommandInfoGetCommand", as: Identifier.self),
              let enabled = resolveSymbol(mediaRemoteHandle, "MRMediaRemoteCommandInfoGetEnabled", as: Enabled.self) else {
            receive(nil)
            return
        }
        fetch(endpoint.path, queue) { commands in
            receive((commands as? [AnyObject]).map { Set($0.filter(enabled).map(identifier)) })
        }
    }

    static func deliver(_ request: PlaybackRequest, command: Int32, endpoint: MediaRemoteEndpoint, item: String?) -> Bool {
        typealias Deliver = @convention(c) (Int32, CFDictionary?, AnyObject, UInt32, DispatchQueue,
            @escaping @convention(block) (UInt32, NSArray?) -> Void) -> Bool
        // Unprivileged requests may be redirected by macOS: require current ownership.
        guard endpoint.alive, discover(includeClients: false).current == endpoint.owner.pid,
              let deliver = resolveSymbol(mediaRemoteHandle, "MRMediaRemoteSendCommandToPlayer", as: Deliver.self) else { return false }
        var options: [String: Any] = [:]
        if let position = request.position {
            guard let positionKey = constant("kMRMediaRemoteOptionPlaybackPosition") else { return false }
            options[positionKey] = position
        }
        if let item, let itemKey = constant("kMRMediaRemoteOptionNowPlayingContentItemID") { options[itemKey] = item }
        let completion = DispatchGroup()
        let accepted = RemoteResult(false)
        completion.enter()
        let queued = deliver(command, options.isEmpty ? nil : options as CFDictionary,
                             endpoint.path, 0, replies) { error, responses in
            accepted.update {
                $0 = error == 0 && (responses as? [NSNumber])?.contains { $0.intValue == 0 } == true
            }
            completion.leave()
        }
        guard queued, completion.wait(timeout: .now() + 0.8) == .success else { return false }
        return accepted.read()
    }
}
