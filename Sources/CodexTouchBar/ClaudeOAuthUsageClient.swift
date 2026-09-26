import CodexTouchBarCore
import Foundation
import Security

/// Reads the Claude Code OAuth token from Keychain without prompting. The
/// token exists only in memory for the duration of one request and is never
/// logged, persisted, or exposed to the UI.
final class ClaudeOAuthUsageClient {
    private static let keychainQueue = DispatchQueue(label: "com.whitney.CodexTouchBar.claude-keychain")
    enum ClientError: LocalizedError {
        case credentialsUnavailable, accessRequired, missingCredentials
        case expired
        case unauthorized
        case rateLimited
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .credentialsUnavailable: return "Claude 登录凭据不可用，请在 Claude Code 中重新登录"
            case .accessRequired: return "请在菜单中连接 Claude 用量并允许钥匙串访问"
            case .missingCredentials: return "未找到 Claude 登录凭据，请在 Claude Code 中重新登录"
            case .expired: return "Claude 登录已过期，请在 Claude Code 中重新登录"
            case .unauthorized: return "Claude 用量请求未获授权，请重新登录"
            case .rateLimited: return "Claude 用量请求过于频繁，稍后自动重试"
            case .invalidResponse: return "Claude 用量服务返回了无法识别的数据"
            }
        }
    }

    private struct Credentials: Decodable {
        struct OAuth: Decodable {
            let accessToken: String
            let expiresAt: Double?
        }
        let claudeAiOauth: OAuth
    }

    func fetch(allowAuthenticationUI: Bool = false, progress: ((String) -> Void)? = nil) async throws -> [QuotaWindow] {
        progress?("开始读取凭据")
        let (token, expiresAt) = try readCredentials(allowAuthenticationUI: allowAuthenticationUI, progress: progress)
        progress?("凭据读取完成")
        if let expiresAt, expiresAt.isFinite, expiresAt > 0, Date().timeIntervalSince1970 * 1000 >= expiresAt {
            throw ClientError.expired
        }
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 8
        let session = URLSession(configuration: configuration, delegate: RedirectDenyingDelegate(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        progress?("开始请求用量")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClientError.invalidResponse }
        progress?("收到 HTTP \(http.statusCode)")
        if http.statusCode == 401 || http.statusCode == 403 { throw ClientError.unauthorized }
        if http.statusCode == 429 { throw ClientError.rateLimited }
        guard (200..<300).contains(http.statusCode), let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClientError.invalidResponse
        }
        return try ClaudeUsageParser.parseOAuthUsage(object)
    }

    private func readCredentials(allowAuthenticationUI: Bool, progress: ((String) -> Void)? = nil) throws -> (String, Double?) {
        // SecKeychainFindGenericPassword matches the native lookup used by
        // macOS Keychain tooling. The interaction flag is process-global, so
        // serialize this short lookup and restore the caller's setting.
        let service = Array("Claude Code-credentials".utf8)
        let account = Array(NSUserName().utf8)
        var passwordLength: UInt32 = 0
        var passwordData: UnsafeMutableRawPointer?
        let status: OSStatus = Self.keychainQueue.sync {
            var previous = DarwinBoolean(true)
            guard SecKeychainGetUserInteractionAllowed(&previous) == errSecSuccess,
                  SecKeychainSetUserInteractionAllowed(allowAuthenticationUI) == errSecSuccess else {
                return errSecInteractionNotAllowed
            }
            defer { SecKeychainSetUserInteractionAllowed(previous.boolValue) }
            return SecKeychainFindGenericPassword(nil, UInt32(service.count), service, UInt32(account.count), account, &passwordLength, &passwordData, nil)
        }
        progress?("钥匙串状态 \(status)")
        if status == errSecInteractionNotAllowed || (!allowAuthenticationUI && status == errSecAuthFailed) { throw ClientError.accessRequired }
        if status == errSecItemNotFound { throw ClientError.missingCredentials }
        guard status == errSecSuccess, let passwordData else { throw ClientError.credentialsUnavailable }
        let data = Data(bytes: passwordData, count: Int(passwordLength))
        SecKeychainItemFreeContent(nil, passwordData)
        guard passwordLength > 0 else { throw ClientError.credentialsUnavailable }
        let credentials: Credentials
        do { credentials = try JSONDecoder().decode(Credentials.self, from: data) }
        catch { throw ClientError.credentialsUnavailable }
        guard !credentials.claudeAiOauth.accessToken.isEmpty else { throw ClientError.credentialsUnavailable }
        return (credentials.claudeAiOauth.accessToken, credentials.claudeAiOauth.expiresAt)
    }
}

private final class RedirectDenyingDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
