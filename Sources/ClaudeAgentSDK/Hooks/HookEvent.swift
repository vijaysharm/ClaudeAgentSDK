import Foundation

/// All hook event types supported by the Claude Code CLI.
public enum HookEvent: String, Codable, Sendable, CaseIterable, Hashable {
    case preToolUse = "PreToolUse"
    case postToolUse = "PostToolUse"
    case postToolUseFailure = "PostToolUseFailure"
    case notification = "Notification"
    case userPromptSubmit = "UserPromptSubmit"
    case sessionStart = "SessionStart"
    case sessionEnd = "SessionEnd"
    case stop = "Stop"
    case stopFailure = "StopFailure"
    case subagentStart = "SubagentStart"
    case subagentStop = "SubagentStop"
    case preCompact = "PreCompact"
    case postCompact = "PostCompact"
    case permissionRequest = "PermissionRequest"
    case setup = "Setup"
    case teammateIdle = "TeammateIdle"
    case taskCompleted = "TaskCompleted"
    case elicitation = "Elicitation"
    case elicitationResult = "ElicitationResult"
    case configChange = "ConfigChange"
    case worktreeCreate = "WorktreeCreate"
    case worktreeRemove = "WorktreeRemove"
    case instructionsLoaded = "InstructionsLoaded"
}
