import Foundation

/// System initialization message emitted at the start of a session.
public struct SDKSystemInitMessage: Codable, Sendable {
    public let agents: [String]?
    public let apiKeySource: ApiKeySource
    public let betas: [String]?
    public let claudeCodeVersion: String
    public let cwd: String
    public let tools: [String]
    public let mcpServers: [McpServerStatusBrief]
    public let model: String
    public let permissionMode: PermissionMode
    public let slashCommands: [String]
    public let outputStyle: String
    public let skills: [String]
    public let plugins: [PluginInfo]
    public let fastModeState: FastModeState?
    public let uuid: String
    public let sessionId: String

    /// Brief MCP server status in the init message.
    public struct McpServerStatusBrief: Codable, Sendable {
        public let name: String
        public let status: String
    }

    /// Plugin information in the init message.
    public struct PluginInfo: Codable, Sendable {
        public let name: String
        public let path: String
    }
}

/// Compact boundary message emitted during context compaction.
public struct SDKCompactBoundaryMessage: Codable, Sendable {
    public let compactMetadata: CompactMetadata
    public let uuid: String
    public let sessionId: String

    public struct CompactMetadata: Codable, Sendable {
        public let trigger: String
        public let preTokens: Int
        public let preservedSegment: PreservedSegment?

        public struct PreservedSegment: Codable, Sendable {
            public let headUuid: String
            public let anchorUuid: String
            public let tailUuid: String
        }
    }
}
