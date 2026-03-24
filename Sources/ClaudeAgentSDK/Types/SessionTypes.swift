import Foundation

/// Session metadata returned by listSessions and getSessionInfo.
public struct SDKSessionInfo: Codable, Sendable {
    public let sessionId: String
    public let summary: String
    public let lastModified: Double
    public let fileSize: Int?
    public let customTitle: String?
    public let firstPrompt: String?
    public let gitBranch: String?
    public let cwd: String?
    public let tag: String?
    public let createdAt: Double?
}

/// A user or assistant message from a session transcript.
public struct SessionMessage: Codable, Sendable {
    public let type: String
    public let uuid: String
    public let sessionId: String
    public let message: AnyCodable
    public let parentToolUseId: String?
}

/// Available slash command / skill.
public struct SlashCommand: Codable, Sendable {
    public let name: String
    public let description: String
    public let isUserInvocable: Bool
    public let argumentHint: String
}

/// Setting source for which settings to load.
public enum SettingSource: String, Codable, Sendable {
    case user
    case project
    case local
}
