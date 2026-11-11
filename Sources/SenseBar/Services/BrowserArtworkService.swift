import AppKit
import Compression
import Foundation

/// Improves missing or small Zen covers using its local session and public
/// YouTube thumbnails, with Apple's catalog as a YouTube Music fallback.
@MainActor
final class BrowserArtworkService {
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var wanted: String?
    private var covers: [String: NSImage] = [:]
    private var order: [String] = []

    static func needsCover(_ image: NSImage?) -> Bool {
        guard let image, let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return true }
        return min(cg.width, cg.height) < 300
    }

    func cached(title: String, artist: String, bundleID: String) -> NSImage? {
        covers[[bundleID, artist, title].joined(separator: "\n")]
    }

    func cancel() {
        generation = UUID()
        task?.cancel()
        task = nil
        wanted = nil
    }

    func load(title: String, artist: String, bundleID: String, completion: @escaping @MainActor (NSImage?) -> Void) {
        let key = [bundleID, artist, title].joined(separator: "\n")
        guard wanted != key else { return }
        cancel()
        guard Self.supports(bundleID) else { return }
        wanted = key
        if let image = covers[key] { completion(image); return }
        let current = generation
        let started = Date()
        task = Task {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 8
            configuration.httpMaximumConnectionsPerHost = 1
            let session = URLSession(configuration: configuration, delegate: ThumbnailDelegate(), delegateQueue: nil)
            defer { session.invalidateAndCancel() }
            for delay in [0, 2, 3, 5, 8, 12, 30] {
                if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
                guard !Task.isCancelled, generation == current else { return }
                let result = await Task.detached(priority: .utility) {
                    Self.findVideoID(matching: title, started: started)
                }.value
                var image: NSImage?
                if let videoID = result.videoID {
                    for quality in ["maxresdefault", "mqdefault"] {
                        guard let url = URL(string: "https://i.ytimg.com/vi/\(videoID)/\(quality).jpg") else { continue }
                        if let data = await Self.download(url, session: session), let found = NSImage(data: data) {
                            image = Self.square(found)
                            break
                        }
                    }
                } else if result.hasYouTubeMusic, !artist.isEmpty {
                    image = await Self.catalogArtwork(title: title, artist: artist, session: session)
                }
                guard !Task.isCancelled, generation == current else { return }
                if let image {
                    covers[key] = image
                    order.removeAll { $0 == key }
                    order.append(key)
                    while order.count > 8 { covers.removeValue(forKey: order.removeFirst()) }
                    completion(image)
                    return
                }
            }
        }
    }

    private static func download(_ url: URL, session: URLSession) async -> Data? {
        do {
            let (bytes, response) = try await session.bytes(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  response.expectedContentLength <= 4_194_304 else { return nil }
            var data = Data()
            for try await byte in bytes {
                guard !Task.isCancelled, data.count < 4_194_304 else { return nil }
                data.append(byte)
            }
            return data
        } catch { return nil }
    }

    private static func catalogArtwork(title: String, artist: String, session: URLSession) async -> NSImage? {
        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [URLQueryItem(name: "term", value: artist + " " + title),
                                 URLQueryItem(name: "entity", value: "song"), URLQueryItem(name: "limit", value: "10")]
        guard let url = components.url, let data = await download(url, session: session),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        for item in root["results"] as? [[String: Any]] ?? [] {
            guard normalized(item["trackName"] as? String ?? "") == normalized(title),
                  normalized(item["artistName"] as? String ?? "") == normalized(artist),
                  let address = item["artworkUrl100"] as? String,
                  let url = URL(string: address.replacingOccurrences(of: "100x100", with: "600x600")),
                  url.scheme == "https", url.host?.hasSuffix(".mzstatic.com") == true,
                  let data = await download(url, session: session), let image = NSImage(data: data) else { continue }
            return image
        }
        return nil
    }

    private static func square(_ image: NSImage) -> NSImage {
        let side = min(image.size.width, image.size.height)
        guard side > 0 else { return image }
        let result = NSImage(size: NSSize(width: 320, height: 320))
        result.lockFocus()
        image.draw(in: NSRect(x: 0, y: 0, width: 320, height: 320),
                   from: NSRect(x: (image.size.width - side) / 2, y: (image.size.height - side) / 2,
                                width: side, height: side), operation: .copy, fraction: 1)
        result.unlockFocus()
        return result
    }

    nonisolated static func videoID(from url: URL) -> String? {
        let host = url.host?.lowercased() ?? ""
        var candidate: String?
        if host == "youtu.be" { candidate = url.pathComponents.dropFirst().first }
        if host == "youtube.com" || host.hasSuffix(".youtube.com") {
            if url.path == "/watch" {
                candidate = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "v" }?.value
            } else if ["shorts", "live", "embed"].contains(url.pathComponents.dropFirst().first ?? "") {
                candidate = url.pathComponents.dropFirst(2).first
            }
        }
        guard let value = candidate, value.count == 11,
              value.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_")).contains($0) }) else { return nil }
        return value
    }

    static func supports(_ bundleID: String) -> Bool {
        bundleID.caseInsensitiveCompare("app.zen-browser.zen") == .orderedSame
    }

    nonisolated private static func findVideoID(matching title: String, started: Date) -> (videoID: String?, hasYouTubeMusic: Bool) {
        let wanted = normalized(title)
        guard !wanted.isEmpty else { return (nil, false) }
        var hasMusic = false
        for root in sessionRoots() {
            guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey],
                                                                  options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            let files = enumerator.compactMap { $0 as? URL }.filter {
                $0.lastPathComponent == "recovery.jsonlz4" || $0.lastPathComponent == "sessionstore.jsonlz4"
            }.sorted { modificationDate($0) > modificationDate($1) }.prefix(8)
            for file in files {
                guard let attributes = try? file.resourceValues(forKeys: [.fileSizeKey]),
                      let size = attributes.fileSize, size <= 32_000_000,
                      let compressed = try? Data(contentsOf: file, options: [.mappedIfSafe]),
                      compressed.count <= 32_000_000, let json = decodeSession(compressed),
                      let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
                      let windows = root["windows"] as? [[String: Any]] else { continue }
                for window in windows {
                    for tab in window["tabs"] as? [[String: Any]] ?? [] {
                        let entries = tab["entries"] as? [[String: Any]] ?? []
                        let index = (tab["index"] as? Int ?? entries.count) - 1
                        guard entries.indices.contains(index) else { continue }
                        let entry = entries[index]
                            guard let rawURL = entry["url"] as? String, let url = URL(string: rawURL) else { continue }
                            if url.host == "music.youtube.com", modificationDate(file) >= started { hasMusic = true }
                            guard let videoID = videoID(from: url) else { continue }
                            let tabTitle = normalized(entry["title"] as? String ?? "")
                            if !tabTitle.isEmpty, tabTitle == wanted { return (videoID, hasMusic) }
                    }
                }
            }
        }
        return (nil, hasMusic)
    }

    nonisolated private static func sessionRoots() -> [URL] {
        let support = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return [support.appendingPathComponent("zen/Profiles")]
    }

    nonisolated static func decodeSession(_ data: Data) -> Data? {
        let magic = Data([0x6d, 0x6f, 0x7a, 0x4c, 0x7a, 0x34, 0x30, 0x00])
        guard data.count > 12, data.starts(with: magic) else { return nil }
        let source = data.dropFirst(12)
        let capacity = data[8..<12].enumerated().reduce(0) { $0 | (Int($1.element) << (8 * $1.offset)) }
        guard capacity > 0, capacity <= 64_000_000 else { return nil }
            var output = Data(count: capacity)
            let decoded = output.withUnsafeMutableBytes { destination in
                source.withUnsafeBytes { input in
                    compression_decode_buffer(destination.bindMemory(to: UInt8.self).baseAddress!, capacity,
                                              input.bindMemory(to: UInt8.self).baseAddress!, source.count, nil, COMPRESSION_LZ4_RAW)
                }
            }
            return decoded == capacity ? output : nil
    }

    nonisolated private static func normalized(_ value: String) -> String {
        value.lowercased().replacingOccurrences(of: " - youtube", with: "")
            .replacingOccurrences(of: " – youtube", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func modificationDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
}

private final class ThumbnailDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
