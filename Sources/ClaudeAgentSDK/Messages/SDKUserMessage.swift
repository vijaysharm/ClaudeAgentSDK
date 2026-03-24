import Foundation

/// Priority for user messages in streaming mode.
public enum MessagePriority: String, Codable, Sendable {
    case now
    case next
    case later
}

/// A user message sent to Claude.
public struct SDKUserMessage: Codable, Sendable {
    /// The message content (MessageParam equivalent).
    public let message: AnyCodable
    /// Tool use ID if this message is a tool result.
    public let parentToolUseId: String?
    /// Whether this is a synthetic (non-user-originated) message.
    public let isSynthetic: Bool?
    /// Tool use result data.
    public let toolUseResult: AnyCodable?
    /// Message priority for queuing.
    public let priority: MessagePriority?
    /// ISO timestamp when the message was created.
    public let timestamp: String?
    /// Unique message identifier.
    public let uuid: String?
    /// Session this message belongs to.
    public let sessionId: String

    /// Creates a simple text user message.
    public static func text(
        _ text: String,
        sessionId: String = ""
    ) -> SDKUserMessage {
        SDKUserMessage(
            message: .object([
                "role": .string("user"),
                "content": .string(text)
            ]),
            parentToolUseId: nil,
            isSynthetic: nil,
            toolUseResult: nil,
            priority: nil,
            timestamp: nil,
            uuid: nil,
            sessionId: sessionId
        )
    }
}

/// A replayed user message (from session resume).
public struct SDKUserMessageReplay: Codable, Sendable {
    public let message: AnyCodable
    public let parentToolUseId: String?
    public let isSynthetic: Bool?
    public let toolUseResult: AnyCodable?
    public let priority: MessagePriority?
    public let timestamp: String?
    public let uuid: String
    public let sessionId: String
    public let isReplay: Bool
}
