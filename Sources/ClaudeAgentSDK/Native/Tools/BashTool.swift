import Foundation

#if os(macOS)

/// Executes shell commands via `/bin/bash -c`.
public struct BashTool: AgentTool {
    public let name = "bash"
    public let description = "Run a bash shell command and return combined stdout+stderr output."

    public let inputSchema: AnyCodable = .object([
        "type": "object",
        "properties": .object([
            "command": .object([
                "type": "string",
                "description": "The shell command to execute"
            ]),
            "timeout": .object([
                "type": "integer",
                "description": "Timeout in seconds (default 120, max 600)"
            ])
        ]),
        "required": .array([.string("command")])
    ])

    public init() {}

    public func execute(input: [String: AnyCodable], context: ToolContext) async throws -> ToolOutput {
        guard let command = input.string("command") else {
            return .error("Missing required parameter: command")
        }

        if context.permissionMode == .readOnly {
            return .error("bash tool is disabled in read-only mode")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]
        process.currentDirectoryURL = URL(fileURLWithPath: context.workingDirectory)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { proc in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? "(binary output)"
                let exitCode = proc.terminationStatus
                let content = output.isEmpty ? "(no output)" : output
                let finalContent = exitCode == 0 ? content : "\(content)\nExit code: \(exitCode)"
                continuation.resume(returning: ToolOutput(content: finalContent, isError: exitCode != 0))
            }
        }
    }
}

#else

/// Stub implementation for non-macOS platforms.
public struct BashTool: AgentTool {
    public let name = "bash"
    public let description = "Run a bash shell command (macOS only)."
    public let inputSchema: AnyCodable = .object(["type": "object", "properties": .object([:]), "required": .array([])])
    public init() {}
    public func execute(input: [String: AnyCodable], context: ToolContext) async throws -> ToolOutput {
        .error("bash tool is only available on macOS")
    }
}

#endif
