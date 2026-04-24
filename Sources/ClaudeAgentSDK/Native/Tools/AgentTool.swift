import Foundation

// MARK: - Protocol

/// A tool that the native agent can call.
public protocol AgentTool: Sendable {
    var name: String { get }
    var description: String { get }
    var inputSchema: AnyCodable { get }
    func execute(input: [String: AnyCodable], context: ToolContext) async throws -> ToolOutput
}

// MARK: - Context

/// Runtime context passed to every tool execution.
public struct ToolContext: Sendable {
    public let workingDirectory: String
    public let permissionMode: AgentPermissionMode

    public init(workingDirectory: String, permissionMode: AgentPermissionMode) {
        self.workingDirectory = workingDirectory
        self.permissionMode = permissionMode
    }
}

// MARK: - Output

/// The result of a tool call.
public struct ToolOutput: Sendable {
    public let content: String
    public let isError: Bool

    public init(content: String, isError: Bool = false) {
        self.content = content
        self.isError = isError
    }

    public static func error(_ message: String) -> ToolOutput {
        ToolOutput(content: message, isError: true)
    }
}

// MARK: - Default Tool Set

/// Returns the standard set of built-in tools.
public func defaultAgentTools() -> [any AgentTool] {
    [
        BashTool(),
        ReadFileTool(),
        WriteFileTool(),
        EditFileTool(),
        GlobTool(),
        GrepTool(),
        WebFetchTool(),
    ]
}

// MARK: - Helpers

/// Convert an `AnyCodable` value to a flat `[String: AnyCodable]` dictionary.
/// Returns an empty dict if the value is not an object.
func inputDict(_ value: AnyCodable) -> [String: AnyCodable] {
    guard case .object(let dict) = value else { return [:] }
    return dict
}

extension [String: AnyCodable] {
    func string(_ key: String) -> String? { self[key]?.stringValue }
    func int(_ key: String) -> Int? { self[key]?.intValue }
    func bool(_ key: String) -> Bool? { self[key]?.boolValue }
}
