import Foundation

/// Task notification message (completed/failed/stopped).
public struct SDKTaskNotificationMessage: Codable, Sendable {
    public let taskId: String
    public let toolUseId: String?
    public let status: String
    public let outputFile: String
    public let summary: String
    public let usage: TaskUsage?
    public let uuid: String
    public let sessionId: String

    public struct TaskUsage: Codable, Sendable {
        public let totalTokens: Int
        public let toolUses: Int
        public let durationMs: Int
    }
}

/// Task started message.
public struct SDKTaskStartedMessage: Codable, Sendable {
    public let taskId: String
    public let toolUseId: String?
    public let description: String
    public let taskType: String?
    public let prompt: String?
    public let uuid: String
    public let sessionId: String
}

/// Task progress message.
public struct SDKTaskProgressMessage: Codable, Sendable {
    public let taskId: String
    public let toolUseId: String?
    public let description: String
    public let usage: SDKTaskNotificationMessage.TaskUsage
    public let lastToolName: String?
    public let summary: String?
    public let uuid: String
    public let sessionId: String
}
