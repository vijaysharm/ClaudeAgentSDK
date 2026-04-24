import Foundation

extension ClawAPI {

    /// HTTP status code sentinel used by ``ApiError/api`` variants.
    public struct StatusCode: Sendable, Equatable, Hashable, Codable, ExpressibleByIntegerLiteral {
        public let rawValue: Int

        public init(_ rawValue: Int) { self.rawValue = rawValue }
        public init(integerLiteral value: Int) { self.rawValue = value }

        public var isSuccess: Bool { (200..<300).contains(rawValue) }

        public static let unauthorized: StatusCode = 401
        public static let forbidden: StatusCode = 403
        public static let payloadTooLarge: StatusCode = 413
        public static let tooManyRequests: StatusCode = 429
        public static let internalServerError: StatusCode = 500
    }

    /// Transport-level error surface for provider clients.
    ///
    /// Mirrors the Rust `api::error::ApiError` enum including the classification
    /// helpers used by the rest of the codebase to decide whether to retry,
    /// escalate, or surface a hint to the user.
    public enum ApiError: Error, Sendable {
        case missingCredentials(provider: String, envVars: [String], hint: String?)
        case contextWindowExceeded(
            model: String,
            estimatedInputTokens: UInt32,
            requestedOutputTokens: UInt32,
            estimatedTotalTokens: UInt32,
            contextWindowTokens: UInt32
        )
        case expiredOAuthToken
        case auth(String)
        case invalidAPIKeyEnv(key: String, underlying: String)
        case http(underlying: String, isConnect: Bool, isTimeout: Bool, isRequest: Bool)
        case io(String)
        case json(provider: String, model: String, bodySnippet: String, detail: String)
        case api(
            status: StatusCode,
            errorType: String?,
            message: String?,
            requestId: String?,
            body: String,
            retryable: Bool,
            suggestedAction: String?
        )
        case retriesExhausted(attempts: UInt32, last: Box<ApiError>)
        case invalidSseFrame(String)
        case backoffOverflow(attempt: UInt32, baseDelayMs: UInt64)
        case requestBodySizeExceeded(estimatedBytes: Int, maxBytes: Int, provider: String)

        // MARK: - Ctors

        public static func missingCredentials(provider: String, envVars: [String]) -> ApiError {
            .missingCredentials(provider: provider, envVars: envVars, hint: nil)
        }

        public static func missingCredentials(
            provider: String, envVars: [String], hint: String?
        ) -> ApiError {
            ApiError.missingCredentials(provider: provider, envVars: envVars, hint: hint)
        }

        public static func jsonDeserialize(
            provider: String, model: String, body: String, detail: String
        ) -> ApiError {
            .json(
                provider: provider,
                model: model,
                bodySnippet: truncateBodySnippet(body, maxChars: 200),
                detail: detail
            )
        }

        // MARK: - Classification

        /// Whether this error should be retried by an outer retry loop.
        public var isRetryable: Bool {
            switch self {
            case .http(_, let isConnect, let isTimeout, let isRequest):
                return isConnect || isTimeout || isRequest
            case .api(_, _, _, _, _, let retryable, _):
                return retryable
            case .retriesExhausted(_, let last):
                return last.value.isRetryable
            default:
                return false
            }
        }

        public var requestId: String? {
            switch self {
            case .api(_, _, _, let rid, _, _, _): return rid
            case .retriesExhausted(_, let last): return last.value.requestId
            default: return nil
            }
        }

        /// Stable classification used by telemetry — values are never user-facing.
        public var safeFailureClass: String {
            if case .contextWindowExceeded = self { return "context_window" }
            if case .api(let s, _, _, _, _, _, _) = self,
               [400, 413, 422].contains(s.rawValue), isContextWindowFailure {
                return "context_window"
            }
            if case .retriesExhausted(_, let last) = self, last.value.isContextWindowFailure {
                return "context_window"
            }
            switch self {
            case .missingCredentials, .expiredOAuthToken, .auth:
                return "provider_auth"
            case .api(let status, _, _, _, _, _, _):
                if status.rawValue == 401 || status.rawValue == 403 { return "provider_auth" }
                if status.rawValue == 429 { return "provider_rate_limit" }
                if isGenericFatalWrapper { return "provider_internal" }
                return "provider_error"
            case .retriesExhausted(_, let last):
                if last.value.isGenericFatalWrapper { return "provider_retry_exhausted" }
                return "provider_error"
            case .http, .invalidSseFrame, .backoffOverflow:
                return "provider_transport"
            case .invalidAPIKeyEnv, .io, .json:
                return "runtime_io"
            case .requestBodySizeExceeded:
                return "request_size"
            case .contextWindowExceeded:
                return "context_window"
            }
        }

        /// True if the error carries one of the known "something went wrong" generic server wrappers.
        public var isGenericFatalWrapper: Bool {
            switch self {
            case .api(_, _, let msg, _, let body, _, _):
                return looksLikeGenericFatalWrapper(msg ?? "") || looksLikeGenericFatalWrapper(body)
            default: return false
            }
        }

        /// True if the error appears to be a context-window exhaustion.
        public var isContextWindowFailure: Bool {
            switch self {
            case .contextWindowExceeded: return true
            case .api(let status, _, let msg, _, let body, _, _):
                let code = status.rawValue
                guard [400, 413, 422].contains(code) else { return false }
                return looksLikeContextWindowError(msg ?? "") || looksLikeContextWindowError(body)
            default: return false
            }
        }
    }

    // MARK: - Box helper (for recursive enums)

    /// Indirect box used by ``ApiError/retriesExhausted(attempts:last:)`` — Swift
    /// enum cases can't recursively contain themselves without an indirection.
    public final class Box<Wrapped: Sendable>: Sendable {
        public let value: Wrapped
        public init(_ value: Wrapped) { self.value = value }
    }

    // MARK: - Helpers

    private static let genericFatalMarkers = [
        "something went wrong while processing your request",
        "please try again, or use /new to start a fresh session",
    ]

    private static let contextWindowMarkers = [
        "maximum context length",
        "context window",
        "context length",
        "too many tokens",
        "prompt is too long",
        "input is too long",
        "request is too large",
    ]

    static func looksLikeGenericFatalWrapper(_ text: String) -> Bool {
        let lower = text.lowercased()
        return genericFatalMarkers.contains { lower.contains($0) }
    }

    static func looksLikeContextWindowError(_ text: String) -> Bool {
        let lower = text.lowercased()
        return contextWindowMarkers.contains { lower.contains($0) }
    }

    /// Unicode-scalar-safe truncation used by JSON body snippets.
    static func truncateBodySnippet(_ body: String, maxChars: Int) -> String {
        if body.count <= maxChars { return body }
        let end = body.index(body.startIndex, offsetBy: maxChars)
        return String(body[body.startIndex..<end]) + "…"
    }
}

extension ClawAPI.ApiError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingCredentials(let provider, let env, let hint):
            let hintSuffix = hint.map { " — hint: \($0)" } ?? ""
            return "missing \(provider) credentials (set one of: \(env.joined(separator: ", ")))\(hintSuffix)"
        case .contextWindowExceeded(let model, let input, let out, let total, let ctx):
            return "context window exceeded for \(model): input=\(input) requested_output=\(out) total=\(total) ctx=\(ctx)"
        case .expiredOAuthToken:
            return "OAuth token has expired"
        case .auth(let msg):
            return "authentication failed: \(msg)"
        case .invalidAPIKeyEnv(let key, let err):
            return "invalid API key env (\(key)): \(err)"
        case .http(let u, _, _, _):
            return "http transport error: \(u)"
        case .io(let msg):
            return "io error: \(msg)"
        case .json(let provider, let model, let body, let detail):
            return "json decode error [\(provider)/\(model)]: \(detail) (body=\(body))"
        case .api(let status, let et, let msg, let rid, _, _, _):
            let parts: [String?] = [
                "api returned \(status.rawValue)",
                et.map { "(\($0))" },
                rid.map { "[trace \($0)]" },
                msg.map { ": \($0)" },
            ]
            return parts.compactMap { $0 }.joined(separator: " ")
        case .retriesExhausted(let attempts, let last):
            return "retries exhausted after \(attempts) attempts: \(last.value.errorDescription ?? "")"
        case .invalidSseFrame(let reason):
            return "invalid SSE frame: \(reason)"
        case .backoffOverflow(let attempt, let base):
            return "backoff overflow (attempt=\(attempt), base_ms=\(base))"
        case .requestBodySizeExceeded(let bytes, let max, let provider):
            return "\(provider) request body size \(bytes) bytes exceeds \(max) bytes"
        }
    }
}
