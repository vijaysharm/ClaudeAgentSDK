import Foundation

/// System prompt configuration.
public enum SystemPrompt: Sendable {
    /// Use a custom system prompt string.
    case custom(String)
    /// Use Claude Code's default system prompt.
    case preset
    /// Use Claude Code's default system prompt with appended instructions.
    case presetWithAppend(String)
}

/// Tool configuration for the session.
public enum ToolsConfig: Sendable {
    /// Specific tool names to make available.
    case specific([String])
    /// Use all default Claude Code tools.
    case preset
}

/// Configuration options for the `query()` function.
///
/// All properties are optional with sensible defaults.
public struct Options: Sendable {
    /// Claude model to use (e.g., "claude-sonnet-4-6", "claude-opus-4-6").
    public var model: String?

    /// Current working directory for the session.
    public var cwd: String?

    /// System prompt configuration.
    public var systemPrompt: SystemPrompt?

    /// Permission mode for the session.
    public var permissionMode: PermissionMode?

    /// Must be true when using `permissionMode: .bypassPermissions`.
    public var allowDangerouslySkipPermissions: Bool?

    /// Tool configuration.
    public var tools: ToolsConfig?

    /// Tool names that are auto-allowed without permission prompting.
    public var allowedTools: [String]?

    /// Tool names that are disallowed.
    public var disallowedTools: [String]?

    /// Additional directories Claude can access.
    public var additionalDirectories: [String]?

    /// Maximum conversation turns.
    public var maxTurns: Int?

    /// Maximum budget in USD.
    public var maxBudgetUsd: Double?

    /// Controls thinking/reasoning behavior.
    public var thinking: ThinkingConfig?

    /// Response effort level.
    public var effort: Effort?

    /// Maximum thinking tokens (deprecated — use `thinking`).
    public var maxThinkingTokens: Int?

    /// Include partial/streaming message events.
    public var includePartialMessages: Bool?

    /// Session ID to resume.
    public var resume: String?

    /// Use a specific session ID.
    public var sessionId: String?

    /// Continue the most recent conversation.
    public var continueSession: Bool?

    /// Fork session when resuming.
    public var forkSession: Bool?

    /// MCP server configurations.
    public var mcpServers: [String: McpServerConfig]?

    /// Agent name for the main thread.
    public var agent: String?

    /// Custom subagent definitions.
    public var agents: [String: AgentDefinition]?

    /// Environment variables for the Claude Code process.
    public var env: [String: String]?

    /// Enable debug mode.
    public var debug: Bool?

    /// Write debug logs to a specific file path.
    public var debugFile: String?

    /// Path to the Claude Code executable.
    public var pathToClaudeCodeExecutable: String?

    /// Setting sources to load.
    public var settingSources: [SettingSource]?

    /// Additional settings to apply (serialized as `--settings <JSON>`).
    public var settings: Settings?

    /// Output format for structured responses.
    public var outputFormat: OutputFormat?

    /// Fallback model if primary is unavailable.
    public var fallbackModel: String?

    /// Additional CLI arguments (keys without `--`, values or nil for flags).
    public var extraArgs: [String: String?]?

    /// Disable session persistence.
    public var persistSession: Bool?

    /// Enable beta features.
    public var betas: [String]?

    /// Enable prompt suggestions.
    public var promptSuggestions: Bool?

    /// Enable subagent progress summaries.
    public var agentProgressSummaries: Bool?

    /// Enable file checkpointing.
    public var enableFileCheckpointing: Bool?

    /// Enforce strict MCP config validation.
    public var strictMcpConfig: Bool?

    // MARK: - Callbacks (not serializable)

    /// Hook callbacks for responding to events during execution.
    public var hooks: [HookEvent: [HookCallbackMatcher]]?

    /// Permission handler for controlling tool usage.
    public var canUseTool: CanUseTool?

    /// Callback for stderr output.
    public var stderr: (@Sendable (String) -> Void)?

    public init(
        model: String? = nil,
        cwd: String? = nil,
        systemPrompt: SystemPrompt? = nil,
        permissionMode: PermissionMode? = nil,
        allowDangerouslySkipPermissions: Bool? = nil,
        tools: ToolsConfig? = nil,
        allowedTools: [String]? = nil,
        disallowedTools: [String]? = nil,
        additionalDirectories: [String]? = nil,
        maxTurns: Int? = nil,
        maxBudgetUsd: Double? = nil,
        thinking: ThinkingConfig? = nil,
        effort: Effort? = nil,
        maxThinkingTokens: Int? = nil,
        includePartialMessages: Bool? = nil,
        resume: String? = nil,
        sessionId: String? = nil,
        continueSession: Bool? = nil,
        forkSession: Bool? = nil,
        mcpServers: [String: McpServerConfig]? = nil,
        agent: String? = nil,
        agents: [String: AgentDefinition]? = nil,
        env: [String: String]? = nil,
        debug: Bool? = nil,
        debugFile: String? = nil,
        pathToClaudeCodeExecutable: String? = nil,
        settingSources: [SettingSource]? = nil,
        settings: Settings? = nil,
        outputFormat: OutputFormat? = nil,
        fallbackModel: String? = nil,
        extraArgs: [String: String?]? = nil,
        persistSession: Bool? = nil,
        betas: [String]? = nil,
        promptSuggestions: Bool? = nil,
        agentProgressSummaries: Bool? = nil,
        enableFileCheckpointing: Bool? = nil,
        strictMcpConfig: Bool? = nil,
        hooks: [HookEvent: [HookCallbackMatcher]]? = nil,
        canUseTool: CanUseTool? = nil,
        stderr: (@Sendable (String) -> Void)? = nil
    ) {
        self.model = model
        self.cwd = cwd
        self.systemPrompt = systemPrompt
        self.permissionMode = permissionMode
        self.allowDangerouslySkipPermissions = allowDangerouslySkipPermissions
        self.tools = tools
        self.allowedTools = allowedTools
        self.disallowedTools = disallowedTools
        self.additionalDirectories = additionalDirectories
        self.maxTurns = maxTurns
        self.maxBudgetUsd = maxBudgetUsd
        self.thinking = thinking
        self.effort = effort
        self.maxThinkingTokens = maxThinkingTokens
        self.includePartialMessages = includePartialMessages
        self.resume = resume
        self.sessionId = sessionId
        self.continueSession = continueSession
        self.forkSession = forkSession
        self.mcpServers = mcpServers
        self.agent = agent
        self.agents = agents
        self.env = env
        self.debug = debug
        self.debugFile = debugFile
        self.pathToClaudeCodeExecutable = pathToClaudeCodeExecutable
        self.settingSources = settingSources
        self.settings = settings
        self.outputFormat = outputFormat
        self.fallbackModel = fallbackModel
        self.extraArgs = extraArgs
        self.persistSession = persistSession
        self.betas = betas
        self.promptSuggestions = promptSuggestions
        self.agentProgressSummaries = agentProgressSummaries
        self.enableFileCheckpointing = enableFileCheckpointing
        self.strictMcpConfig = strictMcpConfig
        self.hooks = hooks
        self.canUseTool = canUseTool
        self.stderr = stderr
    }
}
