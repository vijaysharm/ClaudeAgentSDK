import Foundation

extension ClawRuntime {

    public enum ValidationResult: Sendable, Equatable {
        case allow
        case block(reason: String)
        case warn(message: String)
    }

    public enum CommandIntent: Sendable, Equatable {
        case readOnly
        case write
        case destructive
        case network
        case processManagement
        case packageManagement
        case systemAdmin
        case unknown
    }

    public enum BashValidator {

        public static let writeCommands: Set<String> = [
            "cp", "mv", "rm", "mkdir", "rmdir", "touch", "chmod", "chown",
            "chgrp", "ln", "install", "tee", "truncate", "shred", "mkfifo",
            "mknod", "dd",
        ]
        public static let stateModifyingCommands: Set<String> = [
            "apt", "apt-get", "yum", "dnf", "pacman", "brew", "pip", "pip3",
            "npm", "yarn", "pnpm", "bun", "cargo", "gem", "go", "rustup",
            "docker", "systemctl", "service", "mount", "umount", "kill",
            "pkill", "killall", "reboot", "shutdown", "halt", "poweroff",
            "useradd", "userdel", "usermod", "groupadd", "groupdel",
            "crontab", "at",
        ]
        public static let writeRedirections = [">", ">>", ">&"]
        public static let gitReadOnlySubcommands: Set<String> = [
            "status", "log", "diff", "show", "branch", "tag", "stash",
            "remote", "fetch", "ls-files", "ls-tree", "cat-file",
            "rev-parse", "describe", "shortlog", "blame", "bisect",
            "reflog", "config",
        ]
        public static let destructivePatterns: [(String, String)] = [
            ("rm -rf /", "destructive 'rm -rf /' pattern"),
            ("rm -rf ~", "destructive 'rm -rf ~' pattern"),
            ("rm -rf *", "destructive 'rm -rf *' pattern"),
            ("rm -rf .", "destructive 'rm -rf .' pattern"),
            ("mkfs", "filesystem creation command"),
            ("dd if=", "'dd if=...' overwrites block devices"),
            ("> /dev/sd", "writing to raw block device"),
            ("chmod -R 777", "overly permissive chmod -R 777"),
            ("chmod -R 000", "overly restrictive chmod -R 000"),
            (":(){ :|:& };:", "fork bomb"),
        ]
        public static let alwaysDestructive: Set<String> = ["shred", "wipefs"]
        public static let semanticReadOnly: Set<String> = PermissionEnforcer.readOnlyCommands

        public static func validateReadOnly(_ command: String, mode: PermissionMode) -> ValidationResult {
            guard mode == .readOnly else { return .allow }
            let stripped = stripLeadingEnvAssignments(command)
            let first = firstToken(stripped)
            if first == "sudo" {
                // validate the inner command under the same mode
                let rest = stripped.dropFirst(first.count).trimmingCharacters(in: .whitespaces)
                return validateReadOnly(rest, mode: mode)
            }
            if writeCommands.contains(first) || stateModifyingCommands.contains(first) {
                return .block(reason: "command '\(first)' is not allowed in read-only mode")
            }
            for redir in writeRedirections where stripped.contains(" \(redir) ") {
                return .block(reason: "redirection '\(redir)' is not allowed in read-only mode")
            }
            if first == "git" {
                // require a read-only subcommand
                let parts = stripped.split(separator: " ").map(String.init)
                if parts.count >= 2, !gitReadOnlySubcommands.contains(parts[1]) {
                    return .block(reason: "git subcommand '\(parts[1])' is not read-only")
                }
            }
            return .allow
        }

        public static func checkDestructive(_ command: String) -> ValidationResult {
            for (needle, msg) in destructivePatterns where command.contains(needle) {
                return .warn(message: msg)
            }
            if command.contains("rm -rf") {
                return .warn(message: "'rm -rf' on a broad target")
            }
            for cmd in alwaysDestructive where command.contains(cmd) {
                return .warn(message: "'\(cmd)' is always destructive")
            }
            return .allow
        }

        public static func validateSed(_ command: String, mode: PermissionMode) -> ValidationResult {
            if mode == .readOnly, command.contains(" -i") {
                return .block(reason: "'sed -i' in-place edit is not allowed in read-only mode")
            }
            return .allow
        }

        public static func validatePaths(_ command: String, workspace: String) -> ValidationResult {
            if command.contains("../") { return .warn(message: "command references '../' — potential path escape") }
            if command.contains("~/") || command.contains("$HOME") {
                return .warn(message: "command references user home directory")
            }
            _ = workspace
            return .allow
        }

        public static func validate(_ command: String, mode: PermissionMode, workspace: String) -> ValidationResult {
            switch validateReadOnly(command, mode: mode) {
            case .block, .warn: return validateReadOnly(command, mode: mode)
            case .allow: break
            }
            switch validateSed(command, mode: mode) {
            case .block, .warn: return validateSed(command, mode: mode)
            case .allow: break
            }
            switch checkDestructive(command) {
            case .block, .warn: return checkDestructive(command)
            case .allow: break
            }
            return validatePaths(command, workspace: workspace)
        }

        public static func classify(_ command: String) -> CommandIntent {
            let stripped = stripLeadingEnvAssignments(command)
            let first = firstToken(stripped)
            if semanticReadOnly.contains(first) {
                if first == "sed", stripped.contains(" -i") { return .write }
                return .readOnly
            }
            if first == "rm" || alwaysDestructive.contains(first) { return .destructive }
            if writeCommands.contains(first) { return .write }
            if stateModifyingCommands.contains(first) { return .packageManagement }
            if first == "git" {
                let parts = stripped.split(separator: " ").map(String.init)
                if parts.count >= 2, gitReadOnlySubcommands.contains(parts[1]) { return .readOnly }
                return .write
            }
            return .unknown
        }

        // MARK: - Helpers

        static func firstToken(_ command: String) -> String {
            command.split(separator: " ", omittingEmptySubsequences: true)
                .first.map(String.init) ?? ""
        }

        static func stripLeadingEnvAssignments(_ command: String) -> String {
            var s = command
            while let eq = s.firstIndex(of: "=") {
                let name = s[..<eq]
                guard !name.isEmpty, name.allSatisfy({
                    $0.isLetter || $0.isNumber || $0 == "_"
                }) else { break }
                // advance past value (until whitespace)
                guard let space = s[eq...].firstIndex(of: " ") else { break }
                s = String(s[s.index(after: space)...])
            }
            return s
        }
    }
}
