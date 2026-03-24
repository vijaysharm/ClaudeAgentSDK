import Foundation

/// MCP server configuration using stdio transport.
public struct McpStdioServerConfig: Codable, Sendable {
    public let type: String?
    public let command: String
    public let args: [String]?
    public let env: [String: String]?

    public init(command: String, args: [String]? = nil, env: [String: String]? = nil) {
        self.type = "stdio"
        self.command = command
        self.args = args
        self.env = env
    }
}

/// MCP server configuration using SSE transport.
public struct McpSSEServerConfig: Codable, Sendable {
    public let type: String
    public let url: String
    public let headers: [String: String]?

    public init(url: String, headers: [String: String]? = nil) {
        self.type = "sse"
        self.url = url
        self.headers = headers
    }
}

/// MCP server configuration using HTTP transport.
public struct McpHttpServerConfig: Codable, Sendable {
    public let type: String
    public let url: String
    public let headers: [String: String]?

    public init(url: String, headers: [String: String]? = nil) {
        self.type = "http"
        self.url = url
        self.headers = headers
    }
}

/// Union of MCP server configuration types.
public enum McpServerConfig: Codable, Sendable {
    case stdio(McpStdioServerConfig)
    case sse(McpSSEServerConfig)
    case http(McpHttpServerConfig)

    private enum CodingKeys: String, CodingKey {
        case type
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decodeIfPresent(String.self, forKey: .type)
        switch type {
        case "sse":
            self = .sse(try McpSSEServerConfig(from: decoder))
        case "http":
            self = .http(try McpHttpServerConfig(from: decoder))
        default:
            self = .stdio(try McpStdioServerConfig(from: decoder))
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .stdio(let config):
            try config.encode(to: encoder)
        case .sse(let config):
            try config.encode(to: encoder)
        case .http(let config):
            try config.encode(to: encoder)
        }
    }
}
