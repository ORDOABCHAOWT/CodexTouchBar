import AppKit
import Foundation

enum ThreadNavigator {
    @discardableResult
    static func open(sessionID: String) -> Bool {
        guard !sessionID.isEmpty, sessionID.count <= 160 else { return false }
        var components = URLComponents()
        components.scheme = "codex"
        components.host = "threads"
        components.path = "/\(sessionID)"
        guard let url = components.url else { return false }
        return NSWorkspace.shared.open(url)
    }
}
