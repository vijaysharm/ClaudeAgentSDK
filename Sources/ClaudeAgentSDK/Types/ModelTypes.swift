import Foundation

/// Information about an available model.
public struct ModelInfo: Codable, Sendable {
    public let value: String
    public let displayName: String
    public let description: String
    public let supportsEffort: Bool?
    public let supportedEffortLevels: [Effort]?
    public let supportsAdaptiveThinking: Bool?
    public let supportsFastMode: Bool?
    public let supportsAutoMode: Bool?
}

/// Effort level for responses.
public enum Effort: String, Codable, Sendable {
    case low
    case medium
    case high
    case max
}

/// Usage statistics for a specific model.
public struct ModelUsage: Codable, Sendable {
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheReadInputTokens: Int
    public let cacheCreationInputTokens: Int
    public let webSearchRequests: Int
    public let costUSD: Double
    public let contextWindow: Int
    public let maxOutputTokens: Int
}

/// Information about the logged in user's account.
public struct AccountInfo: Codable, Sendable {
    public let email: String?
    public let organization: String?
    public let subscriptionType: String?
    public let tokenSource: String?
    public let apiKeySource: String?
    public let apiProvider: APIProvider?
}

/// Active API backend.
public enum APIProvider: String, Codable, Sendable {
    case firstParty
    case bedrock
    case vertex
    case foundry
}

/// Non-nullable usage statistics.
public struct NonNullableUsage: Codable, Sendable {
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheCreationInputTokens: Int
    public let cacheReadInputTokens: Int
    public let serverToolUse: ServerToolUse?
    public let serviceTier: String?
    public let cacheCreation: CacheCreation?

    public struct ServerToolUse: Codable, Sendable {
        public let webSearchRequests: Int
        public let webFetchRequests: Int
    }

    public struct CacheCreation: Codable, Sendable {
        public let ephemeral1HInputTokens: Int
        public let ephemeral5MInputTokens: Int
    }
}

/// Source of the API key.
public enum ApiKeySource: String, Codable, Sendable {
    case user
    case project
    case org
    case temporary
    case oauth
    case none
}

/// Fast mode state.
public enum FastModeState: String, Codable, Sendable {
    case off
    case cooldown
    case on
}
