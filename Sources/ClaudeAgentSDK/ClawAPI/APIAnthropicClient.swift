import Foundation

extension ClawAPI {

    // MARK: - Auth

    /// Authentication source for an Anthropic client.
    public enum AuthSource: Sendable, Equatable {
        case none
        case apiKey(String)
        case bearerToken(String)
        case apiKeyAndBearer(apiKey: String, bearerToken: String)

        public var apiKey: String? {
            switch self {
            case .apiKey(let k), .apiKeyAndBearer(let k, _): return k
            default: return nil
            }
        }

        public var bearerToken: String? {
            switch self {
            case .bearerToken(let t), .apiKeyAndBearer(_, let t): return t
            default: return nil
            }
        }

        public var maskedAuthorizationHeader: String {
            bearerToken != nil ? "Bearer [REDACTED]" : "<absent>"
        }

        /// Apply the auth headers to a URLRequest.
        public func apply(to request: inout URLRequest) {
            if let k = apiKey { request.setValue(k, forHTTPHeaderField: "x-api-key") }
            if let t = bearerToken { request.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        }

        /// Read auth from the given environment. Throws if both tokens are missing.
        public static func fromEnvironment(
            _ env: [String: String] = ProcessInfo.processInfo.environment
        ) throws -> AuthSource {
            let apiKey = ClawAPI.envOrDotenv(env, key: "ANTHROPIC_API_KEY")
            let bearer = ClawAPI.envOrDotenv(env, key: "ANTHROPIC_AUTH_TOKEN")
            switch (apiKey.isEmpty, bearer.isEmpty) {
            case (false, false): return .apiKeyAndBearer(apiKey: apiKey, bearerToken: bearer)
            case (false, true): return .apiKey(apiKey)
            case (true, false): return .bearerToken(bearer)
            case (true, true): throw ClawAPI.anthropicMissingCredentialsError(env)
            }
        }
    }

    // MARK: - OAuth token

    public struct OAuthTokenSet: Codable, Sendable, Equatable {
        public var accessToken: String
        public var refreshToken: String?
        public var expiresAt: UInt64?
        public var scopes: [String]

        public init(
            accessToken: String,
            refreshToken: String? = nil,
            expiresAt: UInt64? = nil,
            scopes: [String] = []
        ) {
            self.accessToken = accessToken
            self.refreshToken = refreshToken
            self.expiresAt = expiresAt
            self.scopes = scopes
        }

        private enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresAt = "expires_at"
            case scopes
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            accessToken = try c.decode(String.self, forKey: .accessToken)
            refreshToken = try c.decodeIfPresent(String.self, forKey: .refreshToken)
            expiresAt = try c.decodeIfPresent(UInt64.self, forKey: .expiresAt)
            scopes = try c.decodeIfPresent([String].self, forKey: .scopes) ?? []
        }

        public var asAuthSource: AuthSource { .bearerToken(accessToken) }
    }

    public static func oauthTokenIsExpired(_ token: OAuthTokenSet) -> Bool {
        guard let exp = token.expiresAt else { return false }
        return exp <= UInt64(Date().timeIntervalSince1970)
    }

    // MARK: - Client

    /// Retry policy for the Anthropic client.
    public struct RetryPolicy: Sendable, Equatable {
        public var maxRetries: UInt32 = 8
        public var initialBackoff: TimeInterval = 1
        public var maxBackoff: TimeInterval = 128

        public init(
            maxRetries: UInt32 = 8,
            initialBackoff: TimeInterval = 1,
            maxBackoff: TimeInterval = 128
        ) {
            self.maxRetries = maxRetries
            self.initialBackoff = initialBackoff
            self.maxBackoff = maxBackoff
        }
    }

    /// Anthropic HTTP client with retry + optional prompt cache.
    public final class AnthropicClient: @unchecked Sendable {
        public let http: URLSession
        public let auth: AuthSource
        public let baseURL: String
        public let retryPolicy: RetryPolicy
        public let promptCache: PromptCache?
        private let betas: [String]
        private let extraBody: [String: AnyCodable]

        public init(
            auth: AuthSource,
            baseURL: String = "https://api.anthropic.com",
            retryPolicy: RetryPolicy = RetryPolicy(),
            http: URLSession = ClawAPI.makeHTTPClient(),
            promptCache: PromptCache? = nil,
            betas: [String] = [
                "claude-code-20250219",
                "prompt-caching-scope-2026-01-05",
            ],
            extraBody: [String: AnyCodable] = [:]
        ) {
            self.auth = auth
            self.baseURL = baseURL
            self.retryPolicy = retryPolicy
            self.http = http
            self.promptCache = promptCache
            self.betas = betas
            self.extraBody = extraBody
        }

        public convenience init(apiKey: String) {
            self.init(auth: .apiKey(apiKey))
        }

        public convenience init(
            fromEnvironment env: [String: String] = ProcessInfo.processInfo.environment
        ) throws {
            let auth = try AuthSource.fromEnvironment(env)
            let baseURL = ClawAPI.envOrDotenv(env, key: "ANTHROPIC_BASE_URL")
            self.init(
                auth: auth,
                baseURL: baseURL.isEmpty ? "https://api.anthropic.com" : baseURL
            )
        }

        public func withBaseURL(_ url: String) -> AnthropicClient {
            AnthropicClient(
                auth: auth, baseURL: url, retryPolicy: retryPolicy,
                http: http, promptCache: promptCache, betas: betas, extraBody: extraBody
            )
        }

        public func withPromptCache(_ cache: PromptCache?) -> AnthropicClient {
            AnthropicClient(
                auth: auth, baseURL: baseURL, retryPolicy: retryPolicy,
                http: http, promptCache: cache, betas: betas, extraBody: extraBody
            )
        }

        // MARK: Public API

        /// Non-streaming completion. Honors the prompt cache if configured.
        public func sendMessage(_ request: MessageRequest) async throws -> MessageResponse {
            var req = request
            req.stream = false

            if let cache = promptCache, let cached = await cache.lookupCompletion(req) {
                return cached
            }
            try ClawAPI.preflightMessageRequest(req)
            let (data, response) = try await sendWithRetry(req)
            let body = String(data: data, encoding: .utf8) ?? ""
            var decoded: MessageResponse
            do {
                decoded = try JSONDecoder().decode(MessageResponse.self, from: data)
            } catch {
                throw ApiError.jsonDeserialize(
                    provider: "Anthropic", model: req.model,
                    body: body, detail: String(describing: error)
                )
            }
            if decoded.requestId == nil, let rid = response.value(
                forHTTPHeaderField: "request-id"
            ) ?? response.value(forHTTPHeaderField: "x-request-id") {
                decoded.requestId = rid
            }
            if let cache = promptCache {
                _ = await cache.recordResponse(req, response: decoded)
            }
            return decoded
        }

        /// Streaming completion. Returns an `AsyncThrowingStream` of
        /// ``ClawAPI/StreamEvent`` values.
        public func streamMessage(_ request: MessageRequest) -> AsyncThrowingStream<StreamEvent, Error> {
            let req = request.withStreaming()
            return AsyncThrowingStream { continuation in
                Task {
                    do {
                        try ClawAPI.preflightMessageRequest(req)
                        let urlReq = try self.buildRequest(req)
                        let (bytes, response) = try await self.http.bytes(for: urlReq)
                        try self.enforceStatus(response: response, body: Data())
                        let parser = SseParser(provider: "Anthropic", model: req.model)
                        var latestUsage: Usage?
                        for try await line in bytes.lines {
                            let chunk = Data((line + "\n").utf8)
                            let events = try parser.push(chunk)
                            for e in events {
                                if case .messageDelta(let delta) = e {
                                    latestUsage = delta.usage
                                }
                                continuation.yield(e)
                            }
                        }
                        for e in try parser.finish() {
                            continuation.yield(e)
                        }
                        if let cache = self.promptCache, let u = latestUsage {
                            _ = await cache.recordUsage(req, usage: u)
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
            }
        }

        // MARK: - Internals

        private func buildRequest(_ request: MessageRequest) throws -> URLRequest {
            let urlString = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                + "/v1/messages"
            guard let url = URL(string: urlString) else {
                throw ApiError.io("invalid baseURL: \(urlString)")
            }

            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            if !betas.isEmpty {
                req.setValue(betas.joined(separator: ","), forHTTPHeaderField: "anthropic-beta")
            }
            req.setValue("claude-code-swift/1.0", forHTTPHeaderField: "User-Agent")
            auth.apply(to: &req)

            // Body: request + extraBody merged
            var bodyJson: [String: AnyCodable] = [:]
            if let data = try? JSONEncoder().encode(request),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                for (k, v) in obj {
                    bodyJson[k] = Self.anyCodable(from: v)
                }
            }
            for (k, v) in extraBody { bodyJson[k] = v }
            stripUnsupportedBetaBodyFields(&bodyJson)
            req.httpBody = try JSONEncoder().encode(bodyJson)
            return req
        }

        private func sendWithRetry(
            _ request: MessageRequest
        ) async throws -> (Data, HTTPURLResponse) {
            var delay = retryPolicy.initialBackoff
            let maxAttempts = retryPolicy.maxRetries + 1
            var lastError: ApiError = .io("no attempts")
            for attempt in 1...maxAttempts {
                do {
                    let urlReq = try buildRequest(request)
                    let (data, resp) = try await http.data(for: urlReq)
                    guard let http = resp as? HTTPURLResponse else {
                        throw ApiError.http(
                            underlying: "non-HTTP response", isConnect: false,
                            isTimeout: false, isRequest: true
                        )
                    }
                    try enforceStatus(response: resp, body: data)
                    return (data, http)
                } catch let err as ApiError {
                    lastError = err
                    guard err.isRetryable, attempt < maxAttempts else {
                        if attempt < maxAttempts { continue }
                        throw err
                    }
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    delay = min(delay * 2, retryPolicy.maxBackoff)
                } catch {
                    lastError = .http(
                        underlying: String(describing: error),
                        isConnect: false, isTimeout: false, isRequest: true
                    )
                    guard lastError.isRetryable, attempt < maxAttempts else { throw lastError }
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    delay = min(delay * 2, retryPolicy.maxBackoff)
                }
            }
            throw lastError
        }

        private func enforceStatus(response: URLResponse, body: Data) throws {
            guard let http = response as? HTTPURLResponse else { return }
            let status = StatusCode(http.statusCode)
            if status.isSuccess { return }
            let retryable = [408, 409, 429, 500, 502, 503, 504].contains(http.statusCode)
            var errorType: String?
            var message: String?
            if let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
               let err = obj["error"] as? [String: Any] {
                errorType = err["type"] as? String
                message = err["message"] as? String
            }
            let rid = http.value(forHTTPHeaderField: "request-id")
                ?? http.value(forHTTPHeaderField: "x-request-id")
            throw ApiError.api(
                status: status,
                errorType: errorType,
                message: message,
                requestId: rid,
                body: String(data: body, encoding: .utf8) ?? "",
                retryable: retryable,
                suggestedAction: Self.suggestedAction(for: http.statusCode)
            )
        }

        static func suggestedAction(for code: Int) -> String? {
            switch code {
            case 401: return "Check API key is set correctly and has not expired"
            case 403: return "Verify API key has required permissions for this operation"
            case 413: return "Reduce prompt size or context window before retrying"
            case 429: return "Wait a moment before retrying; consider reducing request rate"
            case 500: return "Provider server error - retry after a brief wait"
            case 502, 503, 504: return "Provider gateway error - retry after a brief wait"
            default: return nil
            }
        }

        private func stripUnsupportedBetaBodyFields(_ obj: inout [String: AnyCodable]) {
            obj.removeValue(forKey: "betas")
            obj.removeValue(forKey: "frequency_penalty")
            obj.removeValue(forKey: "presence_penalty")
            if case .array(let arr) = obj["stop"] ?? .null, !arr.isEmpty {
                obj["stop_sequences"] = .array(arr)
                obj.removeValue(forKey: "stop")
            }
        }

        private static func anyCodable(from value: Any) -> AnyCodable {
            if value is NSNull { return .null }
            if let b = value as? Bool { return .bool(b) }
            if let i = value as? Int { return .int(i) }
            if let d = value as? Double { return .double(d) }
            if let s = value as? String { return .string(s) }
            if let a = value as? [Any] { return .array(a.map(anyCodable(from:))) }
            if let o = value as? [String: Any] {
                var dict: [String: AnyCodable] = [:]
                for (k, v) in o { dict[k] = anyCodable(from: v) }
                return .object(dict)
            }
            return .null
        }
    }
}
