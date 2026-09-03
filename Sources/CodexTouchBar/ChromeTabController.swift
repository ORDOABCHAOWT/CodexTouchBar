import AppKit
import Foundation

struct ChromeTabSnapshot: Equatable {
    let title: String
    let windowID: Int64
    let tabIndex: Int
    let isActive: Bool
}

enum ChromeTabController {
    static func frontWindowTabs() -> [ChromeTabSnapshot]? {
        let source = """
        tell application "Google Chrome"
            if (count of windows) is 0 then return {}
            set targetWindow to front window
            set targetWindowID to id of targetWindow as text
            set selectedIndex to active tab index of targetWindow
            set outputRows to {}
            repeat with tabIndex from 1 to (count of tabs of targetWindow)
                set tabTitle to title of tab tabIndex of targetWindow
                set end of outputRows to {tabTitle, targetWindowID, tabIndex, (tabIndex is selectedIndex)}
            end repeat
            return outputRows
        end tell
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
                let indexDescriptor = row.atIndex(3),
                let activeDescriptor = row.atIndex(4)
            else { return nil }

            let tabIndex = Int(indexDescriptor.int32Value)
            guard tabIndex > 0 else { return nil }
            return ChromeTabSnapshot(
                title: sanitizedTitle(rawTitle),
                windowID: windowID,
                tabIndex: tabIndex,
                isActive: activeDescriptor.booleanValue
            )
        }
    }

    @discardableResult
    static func activate(windowID: Int64, tabIndex: Int) -> Bool {
        guard windowID > 0, tabIndex > 0 else { return false }
        let source = """
        tell application "Google Chrome"
            if exists window id \(windowID) then
                set active tab index of window id \(windowID) to \(tabIndex)
                set index of window id \(windowID) to 1
                activate
            end if
        end tell
        """
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return false }
        _ = script.executeAndReturnError(&error)
        return error == nil
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
