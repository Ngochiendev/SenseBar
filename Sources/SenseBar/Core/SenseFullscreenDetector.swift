// SPDX-License-Identifier: GPL-3.0-or-later
// SenseBar — Fullscreen & Space Detection

import AppKit
import CoreGraphics
import Foundation

// MARK: - Space Topology (Native macOS Fullscreen Spaces detection)

enum SenseSpaceTopology {
    private typealias ConnectionID = UInt32

    private static func symbol(_ name: String) -> UnsafeMutableRawPointer? {
        dlsym(UnsafeMutableRawPointer(bitPattern: -2), name)
    }

    private static let connection: ConnectionID = {
        typealias Function = @convention(c) () -> ConnectionID
        guard let symbol = symbol("CGSMainConnectionID") else { return 0 }
        return unsafeBitCast(symbol, to: Function.self)()
    }()

    private typealias CopyDisplaySpacesFunction = @convention(c) (ConnectionID) -> Unmanaged<CFArray>?
    private static let copyManagedDisplaySpaces: CopyDisplaySpacesFunction? = {
        guard let symbol = symbol("CGSCopyManagedDisplaySpaces") else { return nil }
        return unsafeBitCast(symbol, to: CopyDisplaySpacesFunction.self)
    }()

    static func isFullscreenSpace(on displayID: CGDirectDisplayID) -> Bool {
        guard connection != 0, let copyManagedDisplaySpaces,
              let displayDicts = copyManagedDisplaySpaces(connection)?.takeRetainedValue() as? [[String: Any]],
              !displayDicts.isEmpty
        else { return false }

        let uuidMap = displayIDsByUUID()
        for display in displayDicts {
            let uuidStr = display["Display Identifier"] as? String
            let matchedID = uuidStr.flatMap { uuidMap[$0] }
            if NSScreen.screensHaveSeparateSpaces {
                guard matchedID == displayID else { continue }
            }
            guard let spaceDictionaries = display["Spaces"] as? [[String: Any]],
                  let currentSpaceID = (display["Current Space"] as? [String: Any])?["id64"] as? NSNumber
            else { continue }

            let isCurrentSpaceFullscreen = spaceDictionaries.contains { space in
                (space["type"] as? NSNumber)?.intValue == 4 &&
                (space["id64"] as? NSNumber) == currentSpaceID
            }
            if isCurrentSpaceFullscreen {
                return true
            }
        }
        return false
    }

    private static func displayIDsByUUID() -> [String: CGDirectDisplayID] {
        var map: [String: CGDirectDisplayID] = [:]
        for screen in NSScreen.screens {
            guard let screenNum = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value,
                  let uuid = CGDisplayCreateUUIDFromDisplayID(screenNum)?.takeRetainedValue(),
                  let uuidStr = CFUUIDCreateString(nil, uuid) as String?
            else { continue }
            map[uuidStr] = screenNum
        }
        return map
    }
}

// MARK: - App Fullscreen Detection (YouTube in browser, VLC, Games, HTML5 fullscreen)

@MainActor
enum SenseAppFullscreen {
    struct WindowInfo: Equatable {
        let number: CGWindowID
        let ownerPID: pid_t
        let layer: Int
        let alpha: Double
        let bounds: CGRect
    }

    static func covers(_ window: CGRect, _ display: CGRect) -> Bool {
        guard !display.isEmpty else { return false }
        return window.insetBy(dx: -1, dy: -1).contains(display)
    }

    private static var confirmed = Set<CGWindowID>()

    static func coveredDisplays() -> Set<CGDirectDisplayID> {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        guard let entries = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                       kCGNullWindowID) as? [[String: Any]]
        else { return [] }
        let windows: [WindowInfo] = entries.compactMap { entry in
            guard let number = (entry[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let pid = (entry[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let layer = (entry[kCGWindowLayer as String] as? NSNumber)?.intValue,
                  let bounds = entry[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary)
            else { return nil }
            let alpha = (entry[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
            return WindowInfo(number: number, ownerPID: pid, layer: layer, alpha: alpha, bounds: rect)
        }
        let menuBarHidden = !NSApp.currentSystemPresentationOptions
            .intersection([.autoHideMenuBar, .hideMenuBar]).isEmpty
        let result = coveredDisplays(windows: windows,
                                     frontmostPID: NSWorkspace.shared.frontmostApplication?.processIdentifier,
                                     ownPID: ownPID, displays: activeDisplays(), menuBarHidden: menuBarHidden,
                                     confirmed: confirmed)
        confirmed = result.confirmed
        return result.displays
    }

    static func coveredDisplays(windows: [WindowInfo], frontmostPID: pid_t?, ownPID: pid_t,
                                displays: [CGDirectDisplayID: CGRect], menuBarHidden: Bool,
                                confirmed: Set<CGWindowID>)
        -> (displays: Set<CGDirectDisplayID>, confirmed: Set<CGWindowID>) {
        var covered = Set<CGDirectDisplayID>(), kept = Set<CGWindowID>()
        let frontmostWindow = windows.first(where: {
            $0.layer == 0 && $0.alpha > 0 && $0.ownerPID == frontmostPID
        })?.number
        for (id, frame) in displays {
            let front = windows.first(where: {
                $0.layer == 0 && $0.alpha > 0 && $0.ownerPID != ownPID && !$0.bounds.intersection(frame).isEmpty
            })?.ownerPID
            for window in windows where window.alpha > 0 && window.ownerPID != ownPID
                && covers(window.bounds, frame) {
                if window.layer > 0 {
                    if window.ownerPID == front || window.ownerPID == frontmostPID { covered.insert(id) }
                } else if window.layer == 0,
                          (window.ownerPID == frontmostPID && (menuBarHidden || window.bounds.contains(frame)))
                            || (confirmed.contains(window.number) && window.number != frontmostWindow) {
                    kept.insert(window.number)
                    if window.ownerPID == front || window.ownerPID == frontmostPID { covered.insert(id) }
                }
            }
        }
        return (covered, kept)
    }

    private static func activeDisplays() -> [CGDirectDisplayID: CGRect] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [:] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [:] }
        var frames: [CGDirectDisplayID: CGRect] = [:]
        for id in ids.prefix(Int(count)) { frames[id] = CGDisplayBounds(id) }
        return frames
    }
}

// MARK: - SenseFullscreenDetector

@MainActor
public enum SenseFullscreenDetector {
    public static func isFullscreen(on displayID: CGDirectDisplayID) -> Bool {
        // 1. Native macOS fullscreen Space
        if SenseSpaceTopology.isFullscreenSpace(on: displayID) {
            return true
        }
        // 2. Custom App Fullscreen / Media / YouTube in Browser
        if SenseAppFullscreen.coveredDisplays().contains(displayID) {
            return true
        }
        return false
    }

    public static func isFullscreen(on screen: NSScreen) -> Bool {
        isFullscreen(on: screen.displayID)
    }
}

