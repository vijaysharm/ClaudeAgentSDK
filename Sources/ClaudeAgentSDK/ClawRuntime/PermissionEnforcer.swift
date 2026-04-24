import Foundation

extension ClawRuntime {

    public enum EnforcementResult: Sendable, Equatable, Codable {
        case allowed
        case denied(tool: String, activeMode: String, requiredMode: String, reason: String)

        public var isAllowed: Bool {
            if case .allowed = self { return true }
            return false
        }

        public enum CodingKeys: String, CodingKey {
            case outcome, tool, activeMode, requiredMode, reason
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let outcome = try c.decode(String.self, forKey: .outcome)
            switch outcome {
            case "allowed": self = .allowed
            case "denied":
                self = .denied(
                    tool: try c.decode(String.self, forKey: .tool),
                    activeMode: try c.decode(String.self, forKey: .activeMode),
                    requiredMode: try c.decode(String.self, forKey: .requiredMode),
                    reason: try c.decode(String.self, forKey: .reason)
                )
            default: throw DecodingError.dataCorruptedError(forKey: .outcome, in: c, debugDescription: "unknown outcome \(outcome)")
            }
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .allowed: try c.encode("allowed", forKey: .outcome)
            case .denied(let t, let a, let r, let reason):
                try c.encode("denied", forKey: .outcome)
                try c.encode(t, forKey: .tool)
                try c.encode(a, forKey: .activeMode)
                try c.encode(r, forKey: .requiredMode)
                try c.encode(reason, forKey: .reason)
            }
        }
    }

    /// Convenience wrapper around ``PermissionPolicy`` with quick-path
    /// classifiers for file writes and bash commands.
    public final class PermissionEnforcer: @unchecked Sendable {
        public let policy: PermissionPolicy

        public init(_ policy: PermissionPolicy) { self.policy = policy }

        public var activeMode: PermissionMode { policy.activeMode }

        public func check(tool: String, input: String) -> EnforcementResult {
            // Prompt mode always defers.
            if policy.activeMode == .prompt { return .allowed }
            switch policy.authorize(tool: tool, input: input, prompter: nil) {
            case .allow: return .allowed
            case .deny(let reason):
                return .denied(
                    tool: tool,
                    activeMode: policy.activeMode.rawValue,
                    requiredMode: policy.requiredMode(for: tool).rawValue,
                    reason: reason
                )
            }
        }

        public func isAllowed(tool: String, input: String) -> Bool {
            check(tool: tool, input: input).isAllowed
        }

        public func checkWithRequiredMode(
            tool: String, input: String, required: PermissionMode
        ) -> EnforcementResult {
            if policy.activeMode == .prompt { return .allowed }
            if policy.activeMode >= required { return .allowed }
            return .denied(
                tool: tool,
                activeMode: policy.activeMode.rawValue,
                requiredMode: required.rawValue,
                reason: "tool '\(tool)' requires \(required.rawValue) permission; current mode is \(policy.activeMode.rawValue)"
            )
        }

        public func checkFileWrite(path: String, workspaceRoot: String) -> EnforcementResult {
            switch policy.activeMode {
            case .readOnly:
                return .denied(
                    tool: "write_file", activeMode: "read-only",
                    requiredMode: "workspace-write",
                    reason: "file writes are not allowed in read-only mode"
                )
            case .workspaceWrite:
                return Self.isWithinWorkspace(path, root: workspaceRoot)
                    ? .allowed
                    : .denied(
                        tool: "write_file", activeMode: "workspace-write",
                        requiredMode: "danger-full-access",
                        reason: "path is outside the workspace: \(path)"
                    )
            case .allow, .dangerFullAccess:
                return .allowed
            case .prompt:
                return .denied(
                    tool: "write_file", activeMode: "prompt",
                    requiredMode: "workspace-write",
                    reason: "file writes require user confirmation in prompt mode"
                )
            }
        }

        public func checkBash(command: String) -> EnforcementResult {
            switch policy.activeMode {
            case .readOnly:
                if Self.isReadOnlyCommand(command) { return .allowed }
                return .denied(
                    tool: "bash", activeMode: "read-only",
                    requiredMode: "workspace-write",
                    reason: "non-read-only command blocked in read-only mode: \(command)"
                )
            case .prompt:
                return .denied(
                    tool: "bash", activeMode: "prompt",
                    requiredMode: "workspace-write",
                    reason: "bash commands require user confirmation in prompt mode"
                )
            default: return .allowed
            }
        }

        // MARK: - Helpers

        static func isWithinWorkspace(_ path: String, root: String) -> Bool {
            let absolute = path.hasPrefix("/") ? path : (root as NSString).appendingPathComponent(path)
            let rootSlash = root.hasSuffix("/") ? root : root + "/"
            return absolute == root || absolute.hasPrefix(rootSlash)
        }

        static let readOnlyCommands: Set<String> = [
            "cat", "head", "tail", "less", "more", "grep", "egrep", "fgrep",
            "find", "which", "whereis", "whatis", "man", "info", "file",
            "stat", "du", "df", "free", "uptime", "uname", "hostname",
            "whoami", "id", "groups", "env", "printenv", "echo", "printf",
            "date", "cal", "bc", "expr", "test", "true", "false", "pwd",
            "tree", "diff", "cmp", "md5sum", "sha256sum", "sha1sum", "xxd",
            "od", "hexdump", "strings", "readlink", "realpath", "basename",
            "dirname", "seq", "yes", "tput", "column", "jq", "yq", "ls",
            "wc", "sort", "uniq", "git", "gh", "python", "python3",
        ]

        static func isReadOnlyCommand(_ command: String) -> Bool {
            let lower = command.lowercased()
            if lower.contains(" -i ") || lower.contains(" --in-place")
                || lower.contains(" > ") || lower.contains(" >> ") {
                return false
            }
            guard let first = command
                .split(separator: " ", omittingEmptySubsequences: true)
                .first.map(String.init) else { return false }
            let name = (first as NSString).lastPathComponent
            return readOnlyCommands.contains(name)
        }
    }
}
