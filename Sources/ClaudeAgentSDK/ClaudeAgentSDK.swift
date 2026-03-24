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

    // MARK: - Streaming Input

    /// Create a streaming query where input is driven by an `AsyncStream`.
    ///
    /// The stream's messages are sent to the CLI as they arrive. The returned
    /// ``Query`` yields ``SDKMessage`` values from the CLI's responses.
    ///
    /// - Parameters:
    ///   - prompt: An async stream of user messages to send.
    ///   - options: Configuration options.
    /// - Returns: A ``Query`` that yields response messages.
    public static func query(
        prompt: AsyncStream<SDKUserMessage>,
        options: Options = Options()
    ) throws -> Query {
        #if os(macOS)
        let query = try createStreamingQuery(options: options)
        Task {
            for await message in prompt {
                try? await query.sendMessage(message)
            }
            query.endInput()
        }
        return query
        #else
        throw ClaudeAgentSDKError.unsupportedPlatform
        #endif
    }

    /// Create a streaming query where the caller manually sends messages.
    ///
    /// Use ``Query/sendMessage(_:)-1lbjd`` to send user messages and
    /// ``Query/endInput()`` when done. The returned ``Query`` yields
    /// response messages as an `AsyncSequence`.
    ///
    /// ```swift
    /// let query = try ClaudeAgentSDK.queryStreaming()
    /// try await query.sendMessage("Hello!")
    /// for try await message in query {
    ///     // handle messages...
    /// }
    /// ```
    public static func queryStreaming(
        options: Options = Options()
    ) throws -> Query {
        #if os(macOS)
        return try createStreamingQuery(options: options)
        #else
        throw ClaudeAgentSDKError.unsupportedPlatform
        #endif
    }

    // MARK: - V2 Session API

    /// Create a new multi-turn conversation session.
    ///
    /// The session stays alive across multiple `send()`/`stream()` cycles.
    ///
    /// ```swift
    /// let session = try await ClaudeAgentSDK.createSession(
    ///     options: SessionOptions(model: "claude-sonnet-4-6")
    /// )
    /// try await session.send("Hello!")
    /// for try await msg in session.stream() { ... }
    /// session.close()
    /// ```
    ///
    /// - Parameter options: Session configuration (model is required).
    /// - Returns: An initialized ``Session``.
    public static func createSession(
        options: SessionOptions
    ) throws -> Session {
        #if os(macOS)
        // Generate session ID upfront — the CLI won't emit an init message
        // until it receives the first user message in stream-json input mode.
        let sessionId = UUID().uuidString.lowercased()
        var opts = options.toOptions()
        opts.sessionId = sessionId
        let query = try createStreamingQuery(options: opts)
        return Session(sessionId: sessionId, query: query)
        #else
        throw ClaudeAgentSDKError.unsupportedPlatform
        #endif
    }

    /// Resume an existing session by ID.
    ///
    /// - Parameters:
    ///   - sessionId: The session ID to resume.
    ///   - options: Session configuration.
    /// - Returns: A resumed ``Session``.
    public static func resumeSession(
        _ sessionId: String,
        options: SessionOptions
    ) throws -> Session {
        #if os(macOS)
        let query = try createStreamingQuery(
            options: options.toOptions(resumeSessionId: sessionId)
        )
        return Session(sessionId: sessionId, query: query)
        #else
        throw ClaudeAgentSDKError.unsupportedPlatform
        #endif
    }

    /// One-shot prompt using the session protocol.
    ///
    /// Creates a session, sends the message, collects the result, and closes.
    ///
    /// - Parameters:
    ///   - message: The prompt text.
    ///   - options: Session configuration.
    /// - Returns: The query result.
    public static func prompt(
        _ message: String,
        options: SessionOptions
    ) async throws -> SDKResultMessage {
        #if os(macOS)
        let session = try createSession(options: options)
        defer { session.close() }

        try await session.send(message)

        for try await msg in session.stream() {
            if case .result(let result) = msg {
                return result
            }
        }

        throw ClaudeAgentSDKError.sessionError("No result received")
        #else
        throw ClaudeAgentSDKError.unsupportedPlatform
        #endif
    }

    // MARK: - Internal

    #if os(macOS)
    /// Shared helper to create a streaming-mode query (stdin stays open).
    internal static func createStreamingQuery(options: Options) throws -> Query {
        let executablePath = resolveExecutablePath(options: options)
        let arguments = CLIArgumentBuilder.buildArguments(
            options: options,
            prompt: nil,
            isStreaming: true
        )
        let environment = buildEnvironment(options: options)

        let transport = try ProcessTransport(
            executablePath: executablePath,
            arguments: arguments,
            cwd: options.cwd,
            environment: environment,
            stderrHandler: options.stderr
        )

        return Query(transport: transport, canUseTool: options.canUseTool)
    }
    #endif

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
