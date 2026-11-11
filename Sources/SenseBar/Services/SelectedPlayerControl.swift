import AppKit
import ApplicationServices
import Carbon

struct SelectedPlayerTarget: Equatable, Sendable {
    let bundleID: String
    let pid: Int32
    let launched: Date
    let title: String
    let artist: String
    let advertisedNext: Bool
    let advertisedPrevious: Bool

    @MainActor
    init?(_ track: NowPlayingTrack) {
        guard !track.title.isEmpty,
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: track.bundleID).first,
              let launched = app.launchDate else { return nil }
        bundleID = track.bundleID
        pid = app.processIdentifier
        self.launched = launched
        title = track.title
        artist = track.artist
        advertisedNext = track.playerSupportsNext
        advertisedPrevious = track.playerSupportsPrevious
    }

    var alive: Bool {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return false }
        return !app.isTerminated && app.bundleIdentifier == bundleID && app.launchDate == launched
    }
}

struct SelectedPlayerCapabilities: Sendable {
    var play = false
    var pause = false
    var next = false
    var previous = false
}

/// Serial, bounded discovery and delivery outside the UI thread. Browser actions
/// use the selected app's matching web area; no global media keys are posted.
actor SelectedPlayerControl {
    private var lastTarget: SelectedPlayerTarget?
    private var lastCapabilities = SelectedPlayerCapabilities()
    private struct BrowserButtons {
        var elements: [String: AXUIElement] = [:]
        var ambiguous = Set<String>()

        mutating func add(_ command: String, _ element: AXUIElement) {
            if elements[command] != nil { ambiguous.insert(command) }
            elements[command] = element
        }

        func button(_ command: String) -> AXUIElement? {
            ambiguous.contains(command) ? nil : elements[command]
        }
    }

    func capabilities(for target: SelectedPlayerTarget) -> SelectedPlayerCapabilities {
        guard !Task.isCancelled, target.alive else { return SelectedPlayerCapabilities() }
        if Self.eventClass(target.bundleID) != nil {
            return SelectedPlayerCapabilities(play: true, pause: true, next: true, previous: true)
        }
        let buttons = browserButtons(target)
        let visible = SelectedPlayerCapabilities(play: buttons.button("play") != nil,
            pause: buttons.button("pause") != nil, next: buttons.button("next") != nil,
            previous: buttons.button("previous") != nil)
        if visible.play || visible.pause {
            lastTarget = target
            lastCapabilities = visible
            return visible
        }
        guard mediaTab(target) != nil else { return visible }
        // The matching YouTube tab is backgrounded. Resolve its actual buttons
        // on the user's click; discovery must never change the selected tab.
        return SelectedPlayerCapabilities(play: true, pause: true,
            next: target.advertisedNext || (lastTarget == target && lastCapabilities.next),
            previous: target.advertisedPrevious || (lastTarget == target && lastCapabilities.previous))
    }

    func perform(_ command: String, target: SelectedPlayerTarget) -> Bool {
        guard !Task.isCancelled, target.alive else { return false }
        if let eventClass = Self.eventClass(target.bundleID) {
            return sendAppleEvent(command, eventClass: eventClass, target: target)
        }
        // Resolve again at click time: a cached AX element may belong to an old page.
        var buttons = browserButtons(target)
        if buttons.button(command) == nil, let tabs = mediaTab(target) {
            guard !Task.isCancelled, target.alive,
                  AXUIElementPerformAction(tabs.media, kAXPressAction as CFString) == .success else { return false }
            defer {
                let stillSelected = (value(tabs.media, kAXValueAttribute) as? NSNumber)?.boolValue == true
                let selectedAttribute = value(tabs.media, kAXSelectedAttribute) as? Bool == true
                if target.alive, stillSelected || selectedAttribute, let previous = tabs.previous {
                    _ = AXUIElementPerformAction(previous, kAXPressAction as CFString)
                }
            }
            // AXPress selects within this browser without activating another app.
            // A tab being restored from suspension may need time to expose controls.
            for _ in 0..<5 {
                guard !Task.isCancelled, target.alive else { return false }
                buttons = browserButtons(target)
                if buttons.button(command) != nil { break }
                Thread.sleep(forTimeInterval: 0.1)
            }
            guard !Task.isCancelled, target.alive, let button = buttons.button(command) else { return false }
            return press(button, target: target)
        }
        guard !Task.isCancelled, target.alive, let button = buttons.button(command) else { return false }
        return press(button, target: target)
    }

    private func press(_ button: AXUIElement, target: SelectedPlayerTarget) -> Bool {
        var actions: CFArray?
        _ = AXUIElementCopyActionNames(button, &actions)
        if (actions as? [String])?.contains(kAXPressAction) == true {
            return AXUIElementPerformAction(button, kAXPressAction as CFString) == .success
        }
        // Chromium sometimes exposes web buttons as focusable but omits AXPress.
        // Space activates the verified button; both events go only to this PID.
        guard target.alive else { return false }
        let focused = AXUIElementSetAttributeValue(button, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        Thread.sleep(forTimeInterval: 0.1)
        let hasFocus = value(button, kAXFocusedAttribute) as? Bool == true
        guard focused == .success, hasFocus,
              let down = CGEvent(keyboardEventSource: nil, virtualKey: 49, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: 49, keyDown: false) else { return false }
        down.flags = []
        up.flags = []
        down.postToPid(target.pid)
        up.postToPid(target.pid)
        Thread.sleep(forTimeInterval: 0.1)
        return true
    }

    nonisolated static func browserCommand(for label: String) -> String? {
        let value = normalized(label)
        // Only transport labels with YouTube's keyboard hints qualify. Generic
        // "Play" labels elsewhere can start an advert or a recommended video.
        if ["play k", "phat k", "play keyboard shortcut k", "phat phim tat k"].contains(value) { return "play" }
        if ["pause k", "tam dung k", "pause keyboard shortcut k", "tam dung phim tat k"].contains(value) { return "pause" }
        if value == "next shift n" || value == "next keyboard shortcut shift n"
            || value == "tiep theo shift n" || value == "tiep theo phim tat shift n" { return "next" }
        if value == "previous shift p" || value == "previous keyboard shortcut shift p"
            || value == "truoc do shift p" || value == "truoc shift p"
            || value == "truoc do phim tat shift p" { return "previous" }
        return nil
    }

    nonisolated static func matchesPage(_ page: String, track: String) -> Bool {
        let expected = normalized(track)
        let cleanedPage = page.replacingOccurrences(of: #"^\(\d+\+?\)\s*"#, with: "", options: .regularExpression)
        let actual = normalized(cleanedPage)
        guard expected.count >= 8 else { return actual == expected && !expected.isEmpty }
        return actual == expected || actual.hasPrefix(expected + " ")
    }

    nonisolated private static func normalized(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }

    private func browserButtons(_ target: SelectedPlayerTarget) -> BrowserButtons {
        var result = BrowserButtons()
        guard AXIsProcessTrusted(), target.alive else { return result }
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.1)
        let root = AXUIElementCreateApplication(target.pid)
        let deadline = ProcessInfo.processInfo.systemUptime + 0.8
        var stack: [(AXUIElement, Bool)] = [(root, false)]
        var visited = 0
        var matchingPages = 0
        while let (element, inPlayer) = stack.popLast(), visited < 2500,
              !Task.isCancelled, ProcessInfo.processInfo.systemUptime < deadline {
            visited += 1
            let role = value(element, kAXRoleAttribute) as? String ?? ""
            if role == kAXMenuBarRole { continue }
            var matches = inPlayer
            if role == "AXWebArea" {
                let title = value(element, kAXTitleAttribute) as? String ?? ""
                let description = value(element, kAXDescriptionAttribute) as? String ?? ""
                matches = Self.matchesPage(title.isEmpty ? description : title, track: target.title)
                if !matches { continue }
                matchingPages += 1
                if matchingPages > 1 { return BrowserButtons() }
            }
            if matches, role == kAXButtonRole, value(element, kAXEnabledAttribute) as? Bool != false {
                let labels = [value(element, kAXTitleAttribute), value(element, kAXDescriptionAttribute),
                              value(element, kAXHelpAttribute)].compactMap { $0 as? String }
                if let command = labels.compactMap(Self.browserCommand).first {
                    var actions: CFArray?
                    var focusable = DarwinBoolean(false)
                    _ = AXUIElementIsAttributeSettable(element, kAXFocusedAttribute as CFString, &focusable)
                    if AXUIElementCopyActionNames(element, &actions) == .success,
                       (actions as? [String])?.contains(kAXPressAction) == true || focusable.boolValue {
                        result.add(command, element)
                    }
                }
            }
            let children = value(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
            stack.append(contentsOf: children.prefix(2500).reversed().map { ($0, matches) })
        }
        // A partial traversal cannot establish that the target is unambiguous.
        return !Task.isCancelled && stack.isEmpty ? result : BrowserButtons()
    }

    private func value(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success else { return nil }
        return result
    }

    private func mediaTab(_ target: SelectedPlayerTarget) -> (media: AXUIElement, previous: AXUIElement?)? {
        guard AXIsProcessTrusted(), target.alive else { return nil }
        let deadline = ProcessInfo.processInfo.systemUptime + 0.6
        var stack = [AXUIElementCreateApplication(target.pid)]
        var found: [(media: AXUIElement, previous: AXUIElement?)] = []
        var visited = 0
        while let element = stack.popLast(), visited < 2000,
              !Task.isCancelled, ProcessInfo.processInfo.systemUptime < deadline {
            visited += 1
            let role = value(element, kAXRoleAttribute) as? String ?? ""
            if role == "AXWebArea" || role == kAXMenuBarRole { continue }
            let children = value(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
            if role == "AXTabGroup" {
                var tabs = children
                var matches: [AXUIElement] = []
                var previous: AXUIElement?
                while let tab = tabs.popLast(), visited < 2000,
                      !Task.isCancelled, ProcessInfo.processInfo.systemUptime < deadline {
                    visited += 1
                    let tabRole = value(tab, kAXRoleAttribute) as? String ?? ""
                    if tabRole == kAXRadioButtonRole {
                        let selectedValue = (value(tab, kAXValueAttribute) as? NSNumber)?.boolValue == true
                        let selectedAttribute = value(tab, kAXSelectedAttribute) as? Bool == true
                        if selectedValue || selectedAttribute { previous = tab }
                        let labels = [value(tab, kAXTitleAttribute), value(tab, kAXDescriptionAttribute)]
                            .compactMap { $0 as? String }
                        if labels.contains(where: { Self.matchesPage($0, track: target.title)
                            && Self.normalized($0).contains("youtube") }) { matches.append(tab) }
                    } else if tabRole != "AXWebArea" {
                        tabs += value(tab, kAXChildrenAttribute) as? [AXUIElement] ?? []
                    }
                }
                guard tabs.isEmpty else { return nil }
                for match in matches { found.append((match, previous)) }
            } else { stack += children }
        }
        guard !Task.isCancelled, stack.isEmpty, found.count == 1 else { return nil }
        return found.first
    }

    nonisolated private static func eventClass(_ bundle: String) -> String? {
        switch bundle.lowercased() {
        case "com.spotify.client": return "spfy"
        case "com.apple.music": return "hook"
        default: return nil
        }
    }

    private func sendAppleEvent(_ command: String, eventClass: String, target: SelectedPlayerTarget) -> Bool {
        let eventID: String
        switch command {
        case "play": eventID = "Play"
        case "pause": eventID = "Paus"
        case "next": eventID = "Next"
        case "previous": eventID = "Prev"
        default: return false
        }
        func code(_ value: String) -> UInt32 { value.utf8.reduce(0) { ($0 << 8) | UInt32($1) } }
        let event = NSAppleEventDescriptor.appleEvent(withEventClass: code(eventClass), eventID: code(eventID),
            targetDescriptor: NSAppleEventDescriptor(processIdentifier: target.pid),
            returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        var reply = AppleEvent()
        let status = AESendMessage(event.aeDesc, &reply, AESendMode(kAEWaitReply | kAECanInteract), 120)
        defer { AEDisposeDesc(&reply) }
        guard status == noErr else { return false }
        let descriptor = NSAppleEventDescriptor(aeDescNoCopy: &reply)
        // aeDescNoCopy takes ownership, so detach the stack copy from disposal.
        reply = AppleEvent()
        return descriptor.paramDescriptor(forKeyword: AEKeyword(keyErrorNumber))?.int32Value ?? 0 == 0
    }
}
