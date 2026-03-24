import Foundation

/// Configuration options for creating a V2 session.
///
/// A slimmed-down version of ``Options`` where `model` is required.
public struct SessionOptions: Sendable {
    /// Claude model to use (required).
    public let model: String

    /// Current working directory for the session.
    public var cwd: String?

    /// Path to the Claude Code executable.
    public var pathToClaudeCodeExecutable: String?

    /// Environment variables for the Claude Code process.
    public var env: [String: String]?

    /// Tool names that are auto-allowed without permission prompting.
    public var allowedTools: [String]?

    /// Tool names that are disallowed.
    public var disallowedTools: [String]?

    /// Permission handler for controlling tool usage.
    public var canUseTool: CanUseTool?

    /// Permission mode for the session.
    public var permissionMode: PermissionMode?

    /// Additional directories Claude can access.
    public var additionalDirectories: [String]?

    /// System prompt configuration.
    public var systemPrompt: SystemPrompt?

    /// Maximum conversation turns.
    public var maxTurns: Int?

    /// Maximum budget in USD.
    public var maxBudgetUsd: Double?

    /// Controls thinking/reasoning behavior.
    public var thinking: ThinkingConfig?

    /// Response effort level.
    public var effort: Effort?

    /// Callback for stderr output.
    public var stderr: (@Sendable (String) -> Void)?

    public init(
        model: String,
        cwd: String? = nil,
        pathToClaudeCodeExecutable: String? = nil,
        env: [String: String]? = nil,
        allowedTools: [String]? = nil,
        disallowedTools: [String]? = nil,
        canUseTool: CanUseTool? = nil,
        permissionMode: PermissionMode? = nil,
        additionalDirectories: [String]? = nil,
        systemPrompt: SystemPrompt? = nil,
        maxTurns: Int? = nil,
        maxBudgetUsd: Double? = nil,
        thinking: ThinkingConfig? = nil,
        effort: Effort? = nil,
        stderr: (@Sendable (String) -> Void)? = nil
    ) {
        self.model = model
        self.cwd = cwd
        self.pathToClaudeCodeExecutable = pathToClaudeCodeExecutable
        self.env = env
        self.allowedTools = allowedTools
        self.disallowedTools = disallowedTools
        self.canUseTool = canUseTool
        self.permissionMode = permissionMode
        self.additionalDirectories = additionalDirectories
        self.systemPrompt = systemPrompt
        self.maxTurns = maxTurns
        self.maxBudgetUsd = maxBudgetUsd
        self.thinking = thinking
        self.effort = effort
        self.stderr = stderr
    }

    /// Convert to a full ``Options`` struct for internal use.
    func toOptions(resumeSessionId: String? = nil) -> Options {
        Options(
            model: model,
            cwd: cwd,
            systemPrompt: systemPrompt,
            permissionMode: permissionMode,
            allowedTools: allowedTools,
            disallowedTools: disallowedTools,
            additionalDirectories: additionalDirectories,
            maxTurns: maxTurns,
            maxBudgetUsd: maxBudgetUsd,
            thinking: thinking,
            effort: effort,
            resume: resumeSessionId,
            env: env,
            pathToClaudeCodeExecutable: pathToClaudeCodeExecutable,
            canUseTool: canUseTool,
            stderr: stderr
        )
    }
}
