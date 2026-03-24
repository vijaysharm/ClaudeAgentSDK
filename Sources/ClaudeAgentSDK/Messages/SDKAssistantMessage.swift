import Foundation

/// Error types for assistant messages.
public enum SDKAssistantMessageError: String, Codable, Sendable {
    case authenticationFailed = "authentication_failed"
    case billingError = "billing_error"
    case rateLimit = "rate_limit"
    case invalidRequest = "invalid_request"
    case serverError = "server_error"
    case unknown
    case maxOutputTokens = "max_output_tokens"
}

/// An assistant (Claude) message.
public struct SDKAssistantMessage: Codable, Sendable {
    /// The full message object from the Anthropic API (BetaMessage equivalent).
    public let message: AnyCodable
    /// Tool use ID if this message was generated within a tool call.
    public let parentToolUseId: String?
    /// Error type, if the message had an error.
    public let error: SDKAssistantMessageError?
    /// Unique message identifier.
    public let uuid: String
    /// Session this message belongs to.
    public let sessionId: String
}
