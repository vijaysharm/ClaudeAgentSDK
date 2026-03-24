import Foundation

/// Result of an MCP tool call.
public struct SdkMcpToolResult: Sendable {
    /// The content blocks returned by the tool.
    public let content: [AnyCodable]
    /// Whether the result represents an error.
    public let isError: Bool?

    public init(content: [AnyCodable], isError: Bool? = nil) {
        self.content = content
        self.isError = isError
    }

    /// Create a text result.
    public static func text(_ text: String) -> SdkMcpToolResult {
        SdkMcpToolResult(content: [.object(["type": "text", "text": .string(text)])])
    }

    /// Create an error result.
    public static func error(_ message: String) -> SdkMcpToolResult {
        SdkMcpToolResult(
            content: [.object(["type": "text", "text": .string(message)])],
            isError: true
        )
    }
}

/// Handler for an SDK MCP tool call.
public typealias SdkMcpToolHandler = @Sendable (
    _ input: [String: AnyCodable]
) async throws -> SdkMcpToolResult

/// Definition of a tool provided by an SDK MCP server.
///
/// ```swift
/// let myTool = tool(
///     "get_weather",
///     description: "Get current weather for a city",
///     inputSchema: [
///         "type": "object",
///         "properties": [
///             "city": ["type": "string", "description": "City name"]
///         ],
///         "required": ["city"]
///     ]
/// ) { input in
///     let city = input["city"]?.stringValue ?? "unknown"
///     return .text("Weather in \(city): Sunny, 72F")
/// }
/// ```
public struct SdkMcpToolDefinition: Sendable {
    /// Tool name.
    public let name: String
    /// Description of what the tool does.
    public let description: String
    /// JSON Schema for the tool's input parameters.
    public let inputSchema: [String: AnyCodable]
    /// The handler function called when the tool is invoked.
    public let handler: SdkMcpToolHandler

    public init(
        name: String,
        description: String,
        inputSchema: [String: AnyCodable],
        handler: @escaping SdkMcpToolHandler
    ) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
        self.handler = handler
    }
}

/// Convenience builder for creating tool definitions.
///
/// ```swift
/// let myTool = tool("greet", description: "Say hello", inputSchema: [:]) { _ in
///     .text("Hello!")
/// }
/// ```
public func tool(
    _ name: String,
    description: String,
    inputSchema: [String: AnyCodable],
    handler: @escaping SdkMcpToolHandler
) -> SdkMcpToolDefinition {
    SdkMcpToolDefinition(
        name: name,
        description: description,
        inputSchema: inputSchema,
        handler: handler
    )
}
