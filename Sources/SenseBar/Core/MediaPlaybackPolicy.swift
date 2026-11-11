import Foundation

struct BrowserPlaybackActivity: Equatable {
    let bundleID: String
    let appName: String
    let pid: Int
}

struct AudioOutputActivity: Equatable {
    let bundleID: String
    let appName: String
    let pid: Int
}

struct MediaPlaybackResolution: Equatable {
    let title: String
    let bundleID: String
    let appName: String
    let pid: Int
    let isPlaying: Bool
    let usesRemoteMetadata: Bool
}

/// Ưu tiên Media Session chuẩn từ hệ thống; chỉ fallback appName khi autoplay không công bố session.
enum MediaPlaybackPolicy {
    static func resolve(title: String, bundleID: String, appName: String, pid: Int,
                        isPlaying: Bool, browsers: [BrowserPlaybackActivity],
                        audioOutputs: [AudioOutputActivity] = [], preferredSource: String = "auto") -> MediaPlaybackResolution? {
        if preferredSource != "auto", title.isEmpty,
           let output = audioOutputs.first(where: { $0.bundleID.caseInsensitiveCompare(preferredSource) == .orderedSame }) {
            return MediaPlaybackResolution(title: output.appName, bundleID: output.bundleID,
                appName: output.appName, pid: output.pid, isPlaying: true, usesRemoteMetadata: false)
        }
        if preferredSource != "auto", preferredSource.caseInsensitiveCompare(bundleID) != .orderedSame {
            return nil
        }
        let matching = browsers.first { $0.bundleID.caseInsensitiveCompare(bundleID) == .orderedSame }

        // A paused recording remains a real session and must retain its controls.
        if !title.isEmpty {
            return MediaPlaybackResolution(title: title, bundleID: bundleID, appName: appName,
                pid: pid, isPlaying: isPlaying, usesRemoteMetadata: true)
        }

        // Pinning is a read-only selection, never a reason to follow another app.
        if preferredSource != "auto" { return nil }

        // Trình duyệt đang chạy
        if let browser = matching ?? browsers.first {
            return MediaPlaybackResolution(title: browser.appName,
                bundleID: browser.bundleID, appName: browser.appName, pid: browser.pid,
                isPlaying: true, usesRemoteMetadata: false)
        }

        // Audio-only apps are exposed automatically only when the choice is unambiguous.
        // Their identity never grants MediaRemote transport or timeline capabilities.
        if audioOutputs.count == 1, let output = audioOutputs.first {
            return MediaPlaybackResolution(title: output.appName, bundleID: output.bundleID,
                appName: output.appName, pid: output.pid, isPlaying: true, usesRemoteMetadata: false)
        }

        guard isPlaying, !bundleID.isEmpty else { return nil }
        return MediaPlaybackResolution(title: appName,
            bundleID: bundleID, appName: appName, pid: pid, isPlaying: true, usesRemoteMetadata: false)
    }
}
