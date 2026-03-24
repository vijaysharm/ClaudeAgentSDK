import Foundation

/// The Claude Agent SDK for Swift.
///
/// Provides programmatic access to Claude Code's capabilities by spawning the Claude Code
/// CLI and communicating with it over stdin/stdout using JSON streams.
///
/// ## Usage
///
/// ```swift
/// import ClaudeAgentSDK
///
/// let q = ClaudeAgentSDK.query(
///     prompt: "What files are in the current directory?",
///     options: Options(model: "claude-sonnet-4-6")
/// )
///
/// for try await message in q {
///     switch message {
///     case .result(.success(let result)):
///         print(result.result)
///     default:
///         break
///     }
/// }
/// ```
///
/// - Note: Process spawning is only available on macOS. On iOS, the library compiles
///   but `query()` will throw ``ClaudeAgentSDKError/unsupportedPlatform``.
public enum ClaudeAgentSDK {

    /// The default path to the Claude Code CLI executable.
    public static let defaultExecutablePath = "/usr/local/bin/claude"

    /// Create a query against the Claude Code CLI.
    ///
    /// - Parameters:
    ///   - prompt: The prompt to send to Claude.
    ///   - options: Configuration options for the query.
    /// - Returns: A ``Query`` that yields ``SDKMessage`` values.
    /// - Throws: ``ClaudeAgentSDKError/unsupportedPlatform`` on iOS,
    ///           ``ClaudeAgentSDKError/emptyPrompt`` if the prompt is empty.
    ///
    /// - Precondition: `prompt` must not be empty.
    public static func query(
        prompt: String,
        options: Options = Options()
    ) throws -> Query {
        precondition(!prompt.isEmpty, "Prompt must not be empty")

        #if os(macOS)
        let executablePath = resolveExecutablePath(options: options)
        let arguments = CLIArgumentBuilder.buildArguments(
            options: options,
            prompt: prompt,
            isStreaming: options.canUseTool != nil
        )

        let environment = buildEnvironment(options: options)

        let transport = try ProcessTransport(
            executablePath: executablePath,
            arguments: arguments,
            cwd: options.cwd,
            environment: environment,
            stderrHandler: options.stderr
        )

        // If we have streaming input (for permission callbacks), we need stream-json input
        if options.canUseTool != nil {
            // In streaming mode, the prompt is sent as the first user message
            let query = Query(transport: transport, canUseTool: options.canUseTool)
            Task {
                let userMessage = SDKUserMessage.text(prompt)
                try? await query.writeUserMessage(userMessage)
                transport.endInput()
            }
            return query
        }

        // Non-streaming: close stdin immediately so the CLI doesn't wait for input
        transport.endInput()
        return Query(transport: transport, canUseTool: nil)
        #else
        throw ClaudeAgentSDKError.unsupportedPlatform
        #endif
    }

    // MARK: - Internal

    #if os(macOS)
    private static func resolveExecutablePath(options: Options) -> String {
        if let path = options.pathToClaudeCodeExecutable {
            return path
        }

        // Try common locations
        let candidates = [
            "/usr/local/bin/claude",
            "\(NSHomeDirectory())/.local/bin/claude",
            "/opt/homebrew/bin/claude",
        ]

        for candidate in candidates {
            if FileManager.default.fileExists(atPath: candidate) {
                return candidate
            }
        }

        return defaultExecutablePath
    }

    private static func buildEnvironment(options: Options) -> [String: String]? {
        var env = options.env ?? ProcessInfo.processInfo.environment

        // Set SDK identification
        env["CLAUDE_AGENT_SDK"] = "swift"
        env["CLAUDE_AGENT_SDK_VERSION"] = "0.1.0"

        return env
    }
    #endif
}
