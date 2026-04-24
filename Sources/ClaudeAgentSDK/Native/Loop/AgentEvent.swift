import Foundation

/// Events emitted by the native ``AgentLoop`` during a run.
public enum AgentEvent: Sendable {
    /// A text token streamed from the assistant.
    case textDelta(String)

    /// A thinking/reasoning token streamed from the assistant.
    case thinkingDelta(String)

    /// A tool call has started (name and parsed input are known).
    case toolUseStarted(id: String, name: String, input: [String: AnyCodable])

    /// Periodic timer tick while a tool is executing.
    case toolProgress(id: String, name: String, elapsedSeconds: Double)

    /// A tool finished executing.
    case toolResult(id: String, name: String, output: String, isError: Bool, durationMs: Int)

    /// A transient status message (e.g. "Thinking…").
    case status(String)

    /// The context was compacted between turns.
    case contextCompaction

    /// The API request is being retried after a transient failure.
    case apiRetry(attempt: Int, maxAttempts: Int, delaySeconds: Double)

    /// The API returned a rate-limit response.
    case rateLimited(resetsAt: Date?)

    /// The run completed successfully.
    case completed(AgentStats)

    /// The run stopped due to an error or policy (e.g. max turns).
    case failed(reason: String, errors: [String])
}

/// Aggregate statistics for a completed agent run.
public struct AgentStats: Sendable {
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheReadTokens: Int
    public let cacheWriteTokens: Int
    public let totalTokens: Int
    public let estimatedCostUsd: Double
    public let durationMs: Int
    public let numTurns: Int

    public init(
        inputTokens: Int,
        outputTokens: Int,
        cacheReadTokens: Int,
        cacheWriteTokens: Int,
        estimatedCostUsd: Double,
        durationMs: Int,
        numTurns: Int
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadTokens = cacheReadTokens
        self.cacheWriteTokens = cacheWriteTokens
        self.totalTokens = inputTokens + outputTokens
        self.estimatedCostUsd = estimatedCostUsd
        self.durationMs = durationMs
        self.numTurns = numTurns
    }
}
