import AppKit
import CoreAudio
import Darwin

/// Đọc trạng thái output của app UI để bổ sung browser autoplay và nguồn audio-only.
/// Không tạo process tap, không đọc mẫu âm thanh và không yêu cầu quyền thu âm.
enum BrowserAudioSnapshot {
    struct Result {
        let browsers: [[String: Any]]
        let applications: [[String: Any]]
    }
    private typealias ResponsibilityResolver = @convention(c) (pid_t) -> pid_t
    private static let responsibility: ResponsibilityResolver? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid") else { return nil }
        return unsafeBitCast(symbol, to: ResponsibilityResolver.self)
    }()

    static func read() -> Result {
        guard #available(macOS 14.4, *) else { return Result(browsers: [], applications: []) }
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var bytes: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &bytes) == noErr,
              bytes > 0, bytes <= 1_048_576 else { return Result(browsers: [], applications: []) }
        var objects = [AudioObjectID](repeating: 0, count: Int(bytes) / MemoryLayout<AudioObjectID>.size)
        let status = objects.withUnsafeMutableBytes { buffer in
            AudioObjectGetPropertyData(system, &address, 0, nil, &bytes, buffer.baseAddress!)
        }
        guard status == noErr else { return Result(browsers: [], applications: []) }
        var applications: [String: [String: Any]] = [:]
        var browsers: [String: [String: Any]] = [:]
        for object in objects.prefix(Int(bytes) / MemoryLayout<AudioObjectID>.size) {
            var running: UInt32 = 0
            guard property(object, kAudioProcessPropertyIsRunningOutput, value: &running), running != 0 else { continue }
            var pid: pid_t = 0
            guard property(object, kAudioProcessPropertyPID, value: &pid), pid > 0 else { continue }
            if let app = regularOwner(pid), let bundle = app.bundleIdentifier {
                applications[bundle] = ["bundleID": bundle, "appName": app.localizedName ?? bundle,
                                        "pid": Int(app.processIdentifier)]
            }
            if let app = browserOwner(pid), let bundle = app.bundleIdentifier {
                browsers[bundle] = ["bundleID": bundle, "appName": app.localizedName ?? bundle,
                                    "pid": Int(app.processIdentifier)]
            }
        }
        let all = applications.sorted { $0.key < $1.key }.map(\.value)
        return Result(browsers: browsers.sorted { $0.key < $1.key }.map(\.value), applications: all)
    }

    private static func regularOwner(_ pid: pid_t) -> NSRunningApplication? {
        let responsible = responsibility?(pid) ?? pid
        for start in Set([pid, responsible]) {
            var current = start
            for _ in 0..<8 {
                guard current > 1 else { break }
                if let app = NSRunningApplication(processIdentifier: current),
                   app.activationPolicy == .regular, app.bundleIdentifier != nil {
                    return app
                }
                var info = proc_bsdinfo()
                let size = Int32(MemoryLayout<proc_bsdinfo>.size)
                guard proc_pidinfo(current, PROC_PIDTBSDINFO, 0, &info, size) == size else { break }
                current = pid_t(info.pbi_ppid)
            }
        }
        return nil
    }

    private static func browserOwner(_ pid: pid_t) -> NSRunningApplication? {
        let responsible = responsibility?(pid) ?? pid
        for start in Set([pid, responsible]) {
            var current = start
            for _ in 0..<8 {
                guard current > 1 else { break }
                if let app = NSRunningApplication(processIdentifier: current),
                   app.activationPolicy == .regular, let bundle = app.bundleIdentifier,
                   isBrowser(bundle) { return app }
                var info = proc_bsdinfo()
                let size = Int32(MemoryLayout<proc_bsdinfo>.size)
                guard proc_pidinfo(current, PROC_PIDTBSDINFO, 0, &info, size) == size else { break }
                current = pid_t(info.pbi_ppid)
            }
        }
        return nil
    }

    private static func isBrowser(_ bundle: String) -> Bool {
        let id = bundle.lowercased()
        return ["com.google.chrome", "com.apple.safari", "org.mozilla.firefox", "com.brave.browser",
                "company.thebrowser.browser", "com.microsoft.edgemac", "com.operasoftware.opera",
                "com.vivaldi.vivaldi", "app.zen-browser.zen"].contains { id == $0 || id.hasPrefix($0 + ".") }
    }

    private static func property<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, value: inout T) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<T>.size)
        return withUnsafeMutableBytes(of: &value) { buffer in
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, buffer.baseAddress!) == noErr
        }
    }
}
