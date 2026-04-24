import Foundation

extension ClawRuntime {

    public enum PermissionMode: String, Sendable, Codable, Equatable, Comparable {
        case readOnly = "read-only"
        case workspaceWrite = "workspace-write"
        case dangerFullAccess = "danger-full-access"
        case prompt
        case allow

        private var order: Int {
            switch self {
            case .readOnly: return 0
            case .workspaceWrite: return 1
            case .dangerFullAccess: return 2
            case .prompt: return 3
            case .allow: return 4
            }
        }

        public static func < (l: Self, r: Self) -> Bool { l.order < r.order }
    }

    public enum PermissionOverride: Sendable, Equatable {
        case allow
        case deny
        case ask
    }

    public struct PermissionContext: Sendable, Equatable {
        public var overrideDecision: PermissionOverride?
        public var overrideReason: String?

        public init(overrideDecision: PermissionOverride? = nil, overrideReason: String? = nil) {
            self.overrideDecision = overrideDecision
            self.overrideReason = overrideReason
        }
    }

    public struct PermissionRequest: Sendable, Equatable {
        public var toolName: String
        public var input: String
        public var currentMode: PermissionMode
        public var requiredMode: PermissionMode
        public var reason: String?
    }

    public enum PermissionPromptDecision: Sendable, Equatable {
        case allow
        case deny(reason: String)
    }

    public enum PermissionOutcome: Sendable, Equatable {
        case allow
        case deny(reason: String)
    }

    public protocol PermissionPrompter: AnyObject {
        func decide(_ request: PermissionRequest) -> PermissionPromptDecision
    }

    // MARK: - Rules

    public struct RuntimePermissionRuleConfig: Sendable, Equatable, Codable {
        public var allow: [String]
        public var deny: [String]
        public var ask: [String]

        public init(allow: [String] = [], deny: [String] = [], ask: [String] = []) {
            self.allow = allow
            self.deny = deny
            self.ask = ask
        }
    }

    enum PermissionRuleMatcher: Sendable, Equatable {
        case any
        case exact(String)
        case prefix(String)
    }

    struct PermissionRule: Sendable, Equatable {
        let raw: String
        let toolName: String
        let matcher: PermissionRuleMatcher

        static func parse(_ raw: String) -> PermissionRule? {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            // find first unescaped "("
            if let open = findFirstUnescapedParen(trimmed, open: true),
               let close = findLastUnescapedParen(trimmed, open: false),
               close > open {
                let toolName = String(trimmed[..<open])
                var pattern = String(trimmed[trimmed.index(after: open)..<close])
                // unescape
                pattern = pattern
                    .replacingOccurrences(of: "\\(", with: "(")
                    .replacingOccurrences(of: "\\)", with: ")")
                    .replacingOccurrences(of: "\\\\", with: "\\")
                if pattern.isEmpty || pattern == "*" {
                    return PermissionRule(raw: raw, toolName: toolName, matcher: .any)
                }
                if pattern.hasSuffix(":*") {
                    let prefix = String(pattern.dropLast(2))
                    return PermissionRule(raw: raw, toolName: toolName, matcher: .prefix(prefix))
                }
                return PermissionRule(raw: raw, toolName: toolName, matcher: .exact(pattern))
            }
            return PermissionRule(raw: raw, toolName: trimmed, matcher: .any)
        }

        func matches(toolName: String, subject: String) -> Bool {
            guard toolName == self.toolName else { return false }
            switch matcher {
            case .any: return true
            case .exact(let s): return subject == s
            case .prefix(let p): return subject.hasPrefix(p)
            }
        }

        private static func findFirstUnescapedParen(_ s: String, open: Bool) -> String.Index? {
            let target: Character = open ? "(" : ")"
            var escapeCount = 0
            var idx = s.startIndex
            while idx < s.endIndex {
                let c = s[idx]
                if c == "\\" { escapeCount += 1 } else {
                    if c == target && escapeCount % 2 == 0 { return idx }
                    escapeCount = 0
                }
                idx = s.index(after: idx)
            }
            return nil
        }

        private static func findLastUnescapedParen(_ s: String, open: Bool) -> String.Index? {
            let target: Character = open ? "(" : ")"
            var result: String.Index?
            var escapeCount = 0
            var idx = s.startIndex
            while idx < s.endIndex {
                let c = s[idx]
                if c == "\\" { escapeCount += 1 } else {
                    if c == target && escapeCount % 2 == 0 { result = idx }
                    escapeCount = 0
                }
                idx = s.index(after: idx)
            }
            return result
        }
    }

    // MARK: - Policy

    public final class PermissionPolicy: @unchecked Sendable {
        public private(set) var activeMode: PermissionMode
        private var toolRequirements: [String: PermissionMode] = [:]
        private var allowRules: [PermissionRule] = []
        private var denyRules: [PermissionRule] = []
        private var askRules: [PermissionRule] = []

        public init(activeMode: PermissionMode) {
            self.activeMode = activeMode
        }

        @discardableResult
        public func withToolRequirement(_ tool: String, _ mode: PermissionMode) -> PermissionPolicy {
            toolRequirements[tool] = mode
            return self
        }

        @discardableResult
        public func withPermissionRules(_ config: RuntimePermissionRuleConfig) -> PermissionPolicy {
            allowRules = config.allow.compactMap(PermissionRule.parse(_:))
            denyRules = config.deny.compactMap(PermissionRule.parse(_:))
            askRules = config.ask.compactMap(PermissionRule.parse(_:))
            return self
        }

        public func requiredMode(for tool: String) -> PermissionMode {
            toolRequirements[tool] ?? .dangerFullAccess
        }

        public func authorize(
            tool: String, input: String, context: PermissionContext = PermissionContext(),
            prompter: PermissionPrompter? = nil
        ) -> PermissionOutcome {
            let subject = ClawRuntime.extractPermissionSubject(input)
            // 1. deny always wins
            for rule in denyRules where rule.matches(toolName: tool, subject: subject) {
                return .deny(reason: "rule '\(rule.raw)' denied '\(tool)'")
            }
            let current = activeMode
            let required = requiredMode(for: tool)
            let askRule = askRules.first(where: { $0.matches(toolName: tool, subject: subject) })
            let allowRule = allowRules.first(where: { $0.matches(toolName: tool, subject: subject) })

            if let override = context.overrideDecision {
                switch override {
                case .deny:
                    return .deny(reason: context.overrideReason ?? "hook denied '\(tool)'")
                case .ask:
                    return promptOrDeny(
                        prompter: prompter,
                        request: PermissionRequest(
                            toolName: tool, input: input,
                            currentMode: current, requiredMode: required,
                            reason: context.overrideReason
                        )
                    )
                case .allow:
                    if askRule != nil {
                        return promptOrDeny(
                            prompter: prompter,
                            request: PermissionRequest(
                                toolName: tool, input: input,
                                currentMode: current, requiredMode: required,
                                reason: askRule?.raw
                            )
                        )
                    }
                    if allowRule != nil || current >= required { return .allow }
                }
            }
            if askRule != nil {
                return promptOrDeny(
                    prompter: prompter,
                    request: PermissionRequest(
                        toolName: tool, input: input,
                        currentMode: current, requiredMode: required,
                        reason: askRule?.raw
                    )
                )
            }
            if allowRule != nil || current == .allow || current >= required {
                return .allow
            }
            if current == .prompt
                || (current == .workspaceWrite && required == .dangerFullAccess) {
                return promptOrDeny(
                    prompter: prompter,
                    request: PermissionRequest(
                        toolName: tool, input: input,
                        currentMode: current, requiredMode: required,
                        reason: nil
                    )
                )
            }
            return .deny(reason: "tool '\(tool)' requires \(required.rawValue) permission; current mode is \(current.rawValue)")
        }

        private func promptOrDeny(
            prompter: PermissionPrompter?, request: PermissionRequest
        ) -> PermissionOutcome {
            guard let prompter else {
                return .deny(reason: request.reason ?? "tool '\(request.toolName)' requires user confirmation")
            }
            switch prompter.decide(request) {
            case .allow: return .allow
            case .deny(let reason): return .deny(reason: reason)
            }
        }
    }

    /// Extract a permission-check subject from a tool input JSON string.
    public static func extractPermissionSubject(_ input: String) -> String {
        let keys = ["command", "path", "file_path", "filePath",
                    "notebook_path", "notebookPath", "url",
                    "pattern", "code", "message"]
        if let data = input.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in keys {
                if let v = obj[key] as? String, !v.isEmpty { return v }
            }
        }
        return input.trimmingCharacters(in: .whitespaces)
    }
}
