import AppKit
import CodexTouchBarCore
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

    @discardableResult
    static func open(route: TaskRoute) -> Bool {
        guard route.supported else { return false }
        guard !route.requiresAccessibility else { return false }
        switch route.provider {
        case .codex: return open(sessionID: route.identifier)
        case .claude:
            guard !route.identifier.isEmpty, route.identifier.count <= 160 else { return false }
            guard route.category == .code || route.category == .cowork,
                  route.identifier.hasPrefix("local_"), UUID(uuidString: String(route.identifier.dropFirst(6))) != nil else { return false }
            var components = URLComponents()
            components.scheme = "claude"
            components.host = "claude.ai"
            components.path = route.category == .cowork ? "/cowork/\(route.identifier)" : "/epitaxy/\(route.identifier)"
            guard let url = components.url else { return false }
            return NSWorkspace.shared.open(url)
        }
    }
}
