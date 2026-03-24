import Foundation

/// Status update message.
public struct SDKStatusMessage: Codable, Sendable {
    public let status: String?
    public let permissionMode: PermissionMode?
    public let uuid: String
    public let sessionId: String
}

/// Emitted when an API request fails with a retryable error.
public struct SDKAPIRetryMessage: Codable, Sendable {
    public let attempt: Int
    public let maxRetries: Int
    public let retryDelayMs: Int
    public let errorStatus: Int?
    public let error: SDKAssistantMessageError
    public let uuid: String
    public let sessionId: String
}
