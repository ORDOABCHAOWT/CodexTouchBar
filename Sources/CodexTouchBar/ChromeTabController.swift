import AppKit
import Foundation

struct ChromeTabSnapshot: Equatable {
    let title: String
    let windowID: Int64
    let tabID: Int64
    let isActive: Bool
}

enum ChromeTabController {
    /// Chrome Automation calls are serialized away from AppKit's main thread.
    /// A physical Touch Bar press must never wait for an Apple Event round trip.
    private static let automationQueue = DispatchQueue(
        label: "com.whitney.CodexTouchBar.chrome-automation",
        qos: .userInitiated
    )

    static func refreshAsync(completion: @escaping ([ChromeTabSnapshot]?) -> Void) {
        automationQueue.async {
            let tabs = frontWindowTabs()
            DispatchQueue.main.async {
                completion(tabs)
            }
        }
    }

    static func activateAsync(
        windowID: Int64,
        tabID: Int64,
        completion: @escaping (Bool, [ChromeTabSnapshot]?) -> Void
    ) {
        automationQueue.async {
            let activated = activate(windowID: windowID, tabID: tabID)
            // Read the post-action state in the same serial queue. This keeps
            // a stale timer refresh from repainting the previously active tab.
            let tabs = activated ? frontWindowTabs() : nil
            DispatchQueue.main.async {
                completion(activated, tabs)
            }
        }
    }

    static func frontWindowTabs() -> [ChromeTabSnapshot]? {
        let source = """
        with timeout of 3 seconds
            tell application "Google Chrome"
                if (count of windows) is 0 then return {}
                set targetWindow to front window
                set targetWindowID to id of targetWindow as text
                set selectedIndex to active tab index of targetWindow
                set outputRows to {}
                repeat with tabIndex from 1 to (count of tabs of targetWindow)
                    set targetTab to tab tabIndex of targetWindow
                    set tabTitle to title of targetTab
                    set targetTabID to id of targetTab as text
                    set end of outputRows to {tabTitle, targetWindowID, targetTabID, (tabIndex is selectedIndex)}
                end repeat
                return outputRows
            end tell
        end timeout
        """

        var error: NSDictionary?
        guard
            let script = NSAppleScript(source: source),
            let result = script.executeAndReturnError(&error) as NSAppleEventDescriptor?,
            error == nil
        else {
            return nil
        }

        guard result.numberOfItems > 0 else { return [] }
        return (1...result.numberOfItems).compactMap { position in
            guard
                let row = result.atIndex(position),
                row.numberOfItems >= 4,
                let rawTitle = row.atIndex(1)?.stringValue,
                let windowIDText = row.atIndex(2)?.stringValue,
                let windowID = Int64(windowIDText),
                let tabIDText = row.atIndex(3)?.stringValue,
                let tabID = Int64(tabIDText),
                let activeDescriptor = row.atIndex(4)
            else { return nil }

            guard tabID > 0 else { return nil }
            return ChromeTabSnapshot(
                title: sanitizedTitle(rawTitle),
                windowID: windowID,
                tabID: tabID,
                isActive: activeDescriptor.booleanValue
            )
        }
    }

    @discardableResult
    static func activate(windowID: Int64, tabID: Int64) -> Bool {
        guard windowID > 0, tabID > 0 else { return false }
        let source = """
        with timeout of 3 seconds
            tell application "Google Chrome"
                if exists window id \(windowID) then
                    set targetWindow to window id \(windowID)
                    repeat with currentIndex from 1 to (count of tabs of targetWindow)
                        if (id of tab currentIndex of targetWindow as text) is "\(tabID)" then
                            set active tab index of targetWindow to currentIndex
                            set index of targetWindow to 1
                            activate
                            return true
                        end if
                    end repeat
                end if
                return false
            end tell
        end timeout
        """
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return false }
        let result = script.executeAndReturnError(&error)
        return error == nil && result.booleanValue
    }

    static func stressProbe(cycles: Int) -> (tabCount: Int, checkedSwitches: Int, restored: Bool)? {
        guard cycles > 0 else { return nil }
        return automationQueue.sync {
            guard
                let initialTabs = frontWindowTabs(),
                initialTabs.count > 1,
                let original = initialTabs.first(where: \.isActive)
            else { return nil }

            var checkedSwitches = 0
            for step in 0..<cycles {
                let target = initialTabs[(step + 1) % initialTabs.count]
                guard activate(windowID: target.windowID, tabID: target.tabID) else { break }
                guard let current = frontWindowTabs(), current.contains(where: {
                    $0.tabID == target.tabID && $0.isActive
                }) else { break }
                checkedSwitches += 1
            }

            let restored = activate(windowID: original.windowID, tabID: original.tabID)
                && (frontWindowTabs()?.contains(where: {
                    $0.tabID == original.tabID && $0.isActive
                }) ?? false)
            return (initialTabs.count, checkedSwitches, restored)
        }
    }

    private static func sanitizedTitle(_ rawTitle: String) -> String {
        let title = rawTitle
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "新标签页" : String(title.prefix(100))
    }
}
