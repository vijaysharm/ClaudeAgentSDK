import Foundation

/// Permission modes for the native agent.
public enum AgentPermissionMode: Sendable {
    /// Standard mode — tool calls may prompt before execution.
    case `default`
    /// Read-only mode — write/execute tools are disabled.
    case readOnly
    /// All tools execute without permission prompting.
    case bypassPermissions
}

/// Configuration for ``ClaudeAgent`` / ``AgentLoop``.
public struct AgentOptions: Sendable {
    /// Claude model identifier.
    public var model: String

    /// Maximum tokens to generate per turn.
    public var maxTokens: Int

    /// Anthropic API key. Falls back to `ANTHROPIC_API_KEY` environment variable.
    public var apiKey: String?

    /// Base URL for the Anthropic API.
    public var apiBaseURL: URL

    /// How many times to retry on transient HTTP errors.
    public var maxRetries: Int

    /// Tools available to the agent. Defaults to all built-in tools.
    public var tools: [any AgentTool]

    /// Working directory for file and shell tools.
    public var workingDirectory: String?

    /// Maximum number of agentic loop turns before stopping.
    public var maxTurns: Int?

    /// System prompt override.
    public var systemPrompt: String?

    /// Enable extended thinking / reasoning blocks.
    public var thinkingEnabled: Bool

    /// Budget tokens for the thinking block.
    public var thinkingBudgetTokens: Int

    /// Permission mode controlling which tools may execute.
    public var permissionMode: AgentPermissionMode

    public init(
        model: String = "claude-sonnet-4-6",
        maxTokens: Int = 8096,
        apiKey: String? = nil,
        apiBaseURL: URL = URL(string: "https://api.anthropic.com")!,
        maxRetries: Int = 3,
        tools: [any AgentTool]? = nil,
        workingDirectory: String? = nil,
        maxTurns: Int? = nil,
        systemPrompt: String? = nil,
        thinkingEnabled: Bool = false,
        thinkingBudgetTokens: Int = 8000,
        permissionMode: AgentPermissionMode = .default
    ) {
        self.model = model
        self.maxTokens = maxTokens
        self.apiKey = apiKey
        self.apiBaseURL = apiBaseURL
        self.maxRetries = maxRetries
        self.tools = tools ?? defaultAgentTools()
        self.workingDirectory = workingDirectory
        self.maxTurns = maxTurns
        self.systemPrompt = systemPrompt
        self.thinkingEnabled = thinkingEnabled
        self.thinkingBudgetTokens = thinkingBudgetTokens
        self.permissionMode = permissionMode
    }
}
