import Foundation

/// Emitted when a hook starts executing.
public struct SDKHookStartedMessage: Codable, Sendable {
    public let hookId: String
    public let hookName: String
    public let hookEvent: String
    public let uuid: String
    public let sessionId: String
}

/// Emitted with hook progress (stdout/stderr output).
public struct SDKHookProgressMessage: Codable, Sendable {
    public let hookId: String
    public let hookName: String
    public let hookEvent: String
    public let stdout: String
    public let stderr: String
    public let output: String
    public let uuid: String
    public let sessionId: String
}

/// Emitted when a hook completes.
public struct SDKHookResponseMessage: Codable, Sendable {
    public let hookId: String
    public let hookName: String
    public let hookEvent: String
    public let output: String
    public let stdout: String
    public let stderr: String
    public let exitCode: Int?
    public let outcome: String
    public let uuid: String
    public let sessionId: String
}
