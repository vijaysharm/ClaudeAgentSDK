import Foundation

/// An in-process MCP server that runs within the SDK.
///
/// SDK MCP servers expose tools to the Claude Code CLI without needing
/// an external process. Tool calls are dispatched via the control protocol.
///
/// ```swift
/// let server = createSdkMcpServer(
///     name: "my-tools",
///     tools: [
///         tool("greet", description: "Say hello", inputSchema: [:]) { _ in
///             .text("Hello!")
///         }
///     ]
/// )
/// ```
public actor SdkMcpServer {
    /// Server name.
    public let name: String
    /// Server version.
    public let version: String
    private let tools: [String: SdkMcpToolDefinition]

    init(name: String, version: String, tools: [SdkMcpToolDefinition]) {
        self.name = name
        self.version = version
        self.tools = Dictionary(uniqueKeysWithValues: tools.map { ($0.name, $0) })
    }

    /// List available tools as JSON schema definitions.
    public func listTools() -> [[String: AnyCodable]] {
        tools.values.map { tool in
            [
                "name": .string(tool.name),
                "description": .string(tool.description),
                "inputSchema": .object(tool.inputSchema),
            ]
        }
    }

    /// Call a tool by name with the given input.
    ///
    /// - Parameters:
    ///   - name: The tool name.
    ///   - input: The tool input parameters.
    /// - Returns: The tool result.
    /// - Throws: `ClaudeAgentSDKError.controlRequestError` if the tool is not found.
    public func callTool(name: String, input: [String: AnyCodable]) async throws -> SdkMcpToolResult {
        guard let tool = tools[name] else {
            throw ClaudeAgentSDKError.controlRequestError("Unknown MCP tool: \(name)")
        }
        return try await tool.handler(input)
    }
}

/// Create an in-process MCP server.
///
/// - Parameters:
///   - name: Server name.
///   - version: Server version (defaults to "1.0.0").
///   - tools: Array of tool definitions.
/// - Returns: A new `SdkMcpServer` instance.
public func createSdkMcpServer(
    name: String,
    version: String = "1.0.0",
    tools: [SdkMcpToolDefinition]
) -> SdkMcpServer {
    SdkMcpServer(name: name, version: version, tools: tools)
}

/// Config for an SDK (in-process) MCP server.
public struct McpSdkServerConfig: Codable, Sendable {
    public let type: String
    public let name: String

    public init(name: String) {
        self.type = "sdk"
        self.name = name
    }
}
