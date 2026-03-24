import Foundation

/// Base input common to all hook events.
public struct BaseHookInput: Codable, Sendable {
    public let sessionId: String
    public let transcriptPath: String
    public let cwd: String
    public let permissionMode: String?
    public let agentId: String?
    public let agentType: String?
    public let hookEventName: String
}

/// Callback for responding to hook events.
///
/// - Parameters:
///   - input: The base hook input with session context.
///   - eventData: Event-specific fields as a dictionary.
///   - toolUseID: The tool use ID, if applicable.
/// - Returns: The hook output controlling behavior.
public typealias HookCallback = @Sendable (
    _ input: BaseHookInput,
    _ eventData: [String: AnyCodable],
    _ toolUseID: String?
) async throws -> HookJSONOutput

/// Matcher + callback pair for hook registration.
///
/// ```swift
/// HookCallbackMatcher(
///     matcher: "Bash",  // Only match Bash tool events
///     hooks: [{ input, data, _ in .sync(SyncHookOutput(decision: "approve")) }]
/// )
/// ```
public struct HookCallbackMatcher: Sendable {
    /// Optional pattern to match (e.g., tool names for PreToolUse).
    public var matcher: String?
    /// The callbacks to invoke when the event fires.
    public var hooks: [HookCallback]
    /// Timeout in seconds for all hooks in this matcher.
    public var timeout: TimeInterval?

    public init(
        matcher: String? = nil,
        hooks: [HookCallback],
        timeout: TimeInterval? = nil
    ) {
        self.matcher = matcher
        self.hooks = hooks
        self.timeout = timeout
    }
}

/// Output from a hook callback.
public enum HookJSONOutput: Sendable {
    /// Synchronous hook output that controls behavior.
    case sync(SyncHookOutput)
    /// Asynchronous hook that runs in the background.
    case async(timeout: TimeInterval? = nil)
}

/// Synchronous hook output controlling execution behavior.
public struct SyncHookOutput: Codable, Sendable {
    /// Whether execution should continue.
    public var `continue`: Bool?
    /// Whether to suppress the hook's output.
    public var suppressOutput: Bool?
    /// Reason to stop execution.
    public var stopReason: String?
    /// Decision: "approve" or "block".
    public var decision: String?
    /// System message to inject.
    public var systemMessage: String?
    /// Reason for the decision.
    public var reason: String?
    /// Event-specific output fields.
    public var hookSpecificOutput: [String: AnyCodable]?

    public init(
        `continue`: Bool? = nil,
        suppressOutput: Bool? = nil,
        stopReason: String? = nil,
        decision: String? = nil,
        systemMessage: String? = nil,
        reason: String? = nil,
        hookSpecificOutput: [String: AnyCodable]? = nil
    ) {
        self.`continue` = `continue`
        self.suppressOutput = suppressOutput
        self.stopReason = stopReason
        self.decision = decision
        self.systemMessage = systemMessage
        self.reason = reason
        self.hookSpecificOutput = hookSpecificOutput
    }
}
