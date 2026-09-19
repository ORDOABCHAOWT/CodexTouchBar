import CodexTouchBarCore
import Foundation
import Security

/// Polls Claude's usage endpoint using the OAuth token Claude Code stores in
/// the login keychain. The token is read on demand, kept only for the duration
/// of a request, and never written anywhere by this app.
final class ClaudeUsageClient {
    var onQuotas: (([QuotaWindow]) -> Void)?
    var onError: ((String) -> Void)?

    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let keychainService = "Claude Code-credentials"
    private let queue = DispatchQueue(label: "com.whitney.CodexTouchBar.claude-usage")
    private let session: URLSession
    private var timer: DispatchSourceTimer?
    private var isStopped = false
    private var inFlight = false

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.httpAdditionalHeaders = ["User-Agent": "CodexTouchBar"]
        session = URLSession(configuration: configuration)
    }

    func start() {
        queue.async { [weak self] in
            guard let self, timer == nil else { return }
            isStopped = false
            refresh()
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + 120, repeating: 120)
            timer.setEventHandler { [weak self] in self?.refresh() }
            timer.resume()
            self.timer = timer
        }
    }

    func stop() {
        queue.sync {
            isStopped = true
            timer?.cancel()
            timer = nil
        }
    }

    deinit { stop() }

    /// Refreshes immediately, used when Claude comes to the front so the
    /// numbers are current rather than up to two minutes stale.
    func refreshNow() {
        queue.async { [weak self] in self?.refresh() }
    }

    private func refresh() {
        guard !isStopped, !inFlight else { return }
        guard let token = Self.readAccessToken() else {
            emitError("未找到 Claude 登录信息")
            return
        }
        inFlight = true

        var request = URLRequest(url: Self.usageURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // Claude Code sends this beta header on OAuth requests.
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

        session.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            queue.async {
                self.inFlight = false
                guard !self.isStopped else { return }
                if error != nil {
                    self.emitError("Claude 额度请求失败")
                    return
                }
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard status == 200 else {
                    self.emitError(status == 401 ? "Claude 登录已过期" : "Claude 额度不可用 (\(status))")
                    return
                }
                guard let data, let parsed = try? ClaudeUsageParser.parse(data: data) else {
                    self.emitError("Claude 额度解析失败")
                    return
                }
                let windows = parsed.windows
                DispatchQueue.main.async { self.onQuotas?(windows) }
            }
        }.resume()
    }

    private func emitError(_ message: String) {
        DispatchQueue.main.async { [weak self] in self?.onError?(message) }
    }

    /// Reads the `accessToken` from the `claudeAiOauth` entry Claude Code keeps
    /// in the login keychain. Returns nil whenever the entry is absent or the
    /// user declines access, which surfaces as a normal "not signed in" state.
    private static func readAccessToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        // The entry stores { claudeAiOauth: { accessToken: ... } }; fall back to
        // a flat shape so a format change degrades to "not signed in".
        if let oauth = object["claudeAiOauth"] as? [String: Any],
           let token = oauth["accessToken"] as? String, !token.isEmpty {
            return token
        }
        if let token = object["accessToken"] as? String, !token.isEmpty { return token }
        return nil
    }
}
