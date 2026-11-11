import AppKit
import Darwin

/// A process lifetime is independent of Launch Services registration (WebKit helpers,
/// command-line players). Never accept a recycled PID as the same media session.
enum MediaProcessIdentity {
    static func bundle(running: String?, registered: String?) -> String? {
        [running, registered].compactMap { value -> String? in
            guard let value else { return nil }
            let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty || text.utf8.count > 512 || text.contains("\0") ? nil : text
        }.first
    }

    static func startTime(_ pid: Int32) -> UInt64? {
        guard pid > 0 else { return nil }
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size,
              info.pbi_start_tvsec > 0 else { return nil }
        return info.pbi_start_tvsec * 1_000_000 + info.pbi_start_tvusec
    }

    static func owner(pid: Int32, registeredBundle: String?) -> SessionOwner? {
        guard let start = startTime(pid) else { return nil }
        let app = NSRunningApplication(processIdentifier: pid)
        let running = app?.bundleIdentifier ?? app?.bundleURL.flatMap { Bundle(url: $0)?.bundleIdentifier }
        guard let bundle = bundle(running: running, registered: registeredBundle) else { return nil }
        return SessionOwner(pid: pid, bundle: bundle, processStart: start)
    }

    static func presentation(pid: Int32, ownerBundle: String, parentBundle: String?) -> String {
        if let parent = bundle(running: parentBundle, registered: nil) { return parent }
        let app = NSRunningApplication(processIdentifier: pid)
        if app?.activationPolicy == .regular, let bundle = app?.bundleIdentifier { return bundle }
        // Nested helper bundles may live inside the browser's .app. Walking the
        // bundle path avoids mislabelling a terminal-launched player as Terminal.
        if var location = app?.bundleURL {
            var enclosing: String?
            for _ in 0..<16 {
                if location.pathExtension == "app", let bundle = Bundle(url: location)?.bundleIdentifier {
                    enclosing = bundle
                }
                let next = location.deletingLastPathComponent()
                if next == location { break }
                location = next
            }
            if let enclosing { return enclosing }
        }
        return ownerBundle
    }
}
