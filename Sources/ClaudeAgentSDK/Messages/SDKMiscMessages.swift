import Foundation

/// Tool progress notification.
public struct SDKToolProgressMessage: Codable, Sendable {
    public let toolUseId: String
    public let toolName: String
    public let parentToolUseId: String?
    public let elapsedTimeSeconds: Double
    public let taskId: String?
    public let uuid: String
    public let sessionId: String
}

/// Summary of tool uses.
public struct SDKToolUseSummaryMessage: Codable, Sendable {
    public let summary: String
    public let precedingToolUseIds: [String]
    public let uuid: String
    public let sessionId: String
}

/// Rate limit event.
public struct SDKRateLimitEvent: Codable, Sendable {
    public let rateLimitInfo: SDKRateLimitInfo
    public let uuid: String
    public let sessionId: String
}

/// Rate limit information for claude.ai subscription users.
public struct SDKRateLimitInfo: Codable, Sendable {
    public let status: String
    public let resetsAt: Double?
    public let rateLimitType: String?
    public let utilization: Double?
    public let overageStatus: String?
    public let overageResetsAt: Double?
    public let overageDisabledReason: String?
    public let isUsingOverage: Bool?
    public let surpassedThreshold: Double?
}

/// Partial streaming assistant message.
public struct SDKPartialAssistantMessage: Codable, Sendable {
    public let event: AnyCodable
    public let parentToolUseId: String?
    public let uuid: String
    public let sessionId: String
}

/// Authentication status message.
public struct SDKAuthStatusMessage: Codable, Sendable {
    public let isAuthenticating: Bool
    public let output: [String]
    public let error: String?
    public let uuid: String
    public let sessionId: String
}

/// Predicted next user prompt.
public struct SDKPromptSuggestionMessage: Codable, Sendable {
    public let suggestion: String
    public let uuid: String
    public let sessionId: String
}

/// Files persisted event.
public struct SDKFilesPersistedEvent: Codable, Sendable {
    public let files: [PersistedFile]
    public let failed: [FailedFile]
    public let processedAt: String
    public let uuid: String
    public let sessionId: String

    public struct PersistedFile: Codable, Sendable {
        public let filename: String
        public let fileId: String
    }

    public struct FailedFile: Codable, Sendable {
        public let filename: String
        public let error: String
    }
}

/// Output from a local slash command.
public struct SDKLocalCommandOutputMessage: Codable, Sendable {
    public let content: String
    public let uuid: String
    public let sessionId: String
}

/// Elicitation complete message.
public struct SDKElicitationCompleteMessage: Codable, Sendable {
    public let mcpServerName: String
    public let elicitationId: String
    public let uuid: String
    public let sessionId: String
}
