import Foundation

// MARK: - Errors

/// Errors thrown by ``ClaudeAgent``.
public enum AgentError: Error, LocalizedError {
    case missingAPIKey
    case maxTurnsReached(Int)
    case toolNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "No API key provided. Set ANTHROPIC_API_KEY or pass apiKey in AgentOptions."
        case .maxTurnsReached(let n):
            return "Agent stopped after \(n) turns (maxTurns limit)."
        case .toolNotFound(let name):
            return "Tool not found: \(name)"
        }
    }
}

// MARK: - ClaudeAgent

/// A native Swift agent that makes direct Anthropic API calls — no `claude` binary required.
///
/// ```swift
/// let agent = try ClaudeAgent()
/// for try await event in agent.run("What files are in the current directory?") {
///     if case .textDelta(let text) = event { print(text, terminator: "") }
/// }
/// ```
///
/// For a ready-made terminal experience:
/// ```swift
/// let agent = try ClaudeAgent()
/// try await agent.runInTerminal("Explain the Package.swift in this repo")
/// ```
public final class ClaudeAgent: Sendable {
    private let loop: AgentLoop

    /// Create a new agent with the given options.
    ///
    /// - Throws: ``AgentError/missingAPIKey`` if no API key is found.
    public init(options: AgentOptions = AgentOptions()) throws {
        self.loop = try AgentLoop(options: options)
    }

    /// Run the agent on a prompt, returning a stream of ``AgentEvent`` values.
    public func run(_ prompt: String) -> AsyncThrowingStream<AgentEvent, Error> {
        loop.run(prompt: prompt)
    }

    /// Reset the conversation history so the next `run()` starts fresh.
    public func reset() async {
        await loop.reset()
    }

    // MARK: - Terminal Convenience

    /// Run the agent and render output to the terminal using ``TerminalRenderer``.
    public func runInTerminal(
        _ prompt: String,
        config: TerminalRenderer.Config = .default
    ) async throws {
        let renderer = TerminalRenderer(config: config)
        try await renderer.render(loop.run(prompt: prompt))
    }

    /// Run an interactive REPL in the terminal, keeping conversation history between turns.
    ///
    /// Type `exit` or `quit` to end the session, or send EOF (Ctrl+D).
    public func runInteractiveTerminal(
        rendererConfig: TerminalRenderer.Config = .default,
        inputPrompt: String = "> "
    ) async throws {
        let renderer = TerminalRenderer(config: rendererConfig)
        let promptData = Data(inputPrompt.utf8)

        while true {
            FileHandle.standardOutput.write(promptData)
            guard let line = readLine(strippingNewline: true) else { break }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if trimmed == "exit" || trimmed == "quit" { break }

            try await renderer.render(loop.run(prompt: trimmed))
        }
    }
}
