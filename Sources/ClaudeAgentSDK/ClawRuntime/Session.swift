import Foundation

extension ClawRuntime {

    public enum MessageRole: String, Sendable, Codable, Equatable {
        case system, user, assistant, tool
    }

    public enum ConversationContentBlock: Sendable, Equatable, Codable {
        case text(String)
        case toolUse(id: String, name: String, input: AnyCodable)
        case toolResult(toolUseId: String, toolName: String, output: String, isError: Bool)

        private enum CodingKeys: String, CodingKey {
            case type, text, id, name, input
            case toolUseId = "tool_use_id"
            case toolName = "tool_name"
            case output
            case isError = "is_error"
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            switch try c.decode(String.self, forKey: .type) {
            case "text":
                self = .text(try c.decode(String.self, forKey: .text))
            case "tool_use":
                self = .toolUse(
                    id: try c.decode(String.self, forKey: .id),
                    name: try c.decode(String.self, forKey: .name),
                    input: try c.decode(AnyCodable.self, forKey: .input)
                )
            case "tool_result":
                self = .toolResult(
                    toolUseId: try c.decode(String.self, forKey: .toolUseId),
                    toolName: try c.decode(String.self, forKey: .toolName),
                    output: try c.decode(String.self, forKey: .output),
                    isError: try c.decodeIfPresent(Bool.self, forKey: .isError) ?? false
                )
            default:
                throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "unknown content block")
            }
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .text(let t):
                try c.encode("text", forKey: .type)
                try c.encode(t, forKey: .text)
            case .toolUse(let id, let name, let input):
                try c.encode("tool_use", forKey: .type)
                try c.encode(id, forKey: .id)
                try c.encode(name, forKey: .name)
                try c.encode(input, forKey: .input)
            case .toolResult(let id, let tname, let out, let err):
                try c.encode("tool_result", forKey: .type)
                try c.encode(id, forKey: .toolUseId)
                try c.encode(tname, forKey: .toolName)
                try c.encode(out, forKey: .output)
                try c.encode(err, forKey: .isError)
            }
        }
    }

    public struct ConversationMessage: Sendable, Equatable, Codable {
        public var role: MessageRole
        public var blocks: [ConversationContentBlock]
        public var usage: TokenUsage?

        public init(
            role: MessageRole, blocks: [ConversationContentBlock], usage: TokenUsage? = nil
        ) {
            self.role = role
            self.blocks = blocks
            self.usage = usage
        }

        public static func userText(_ text: String) -> ConversationMessage {
            ConversationMessage(role: .user, blocks: [.text(text)])
        }

        public static func assistant(_ blocks: [ConversationContentBlock]) -> ConversationMessage {
            ConversationMessage(role: .assistant, blocks: blocks)
        }

        public static func assistantWithUsage(_ blocks: [ConversationContentBlock], usage: TokenUsage) -> ConversationMessage {
            ConversationMessage(role: .assistant, blocks: blocks, usage: usage)
        }

        public static func toolResult(id: String, toolName: String, output: String, isError: Bool = false) -> ConversationMessage {
            ConversationMessage(role: .tool, blocks: [
                .toolResult(toolUseId: id, toolName: toolName, output: output, isError: isError),
            ])
        }
    }

    public struct SessionCompaction: Sendable, Equatable, Codable {
        public var count: UInt32
        public var removedMessageCount: Int
        public var summary: String
    }

    public struct SessionFork: Sendable, Equatable, Codable {
        public var parentSessionId: String
        public var branchName: String?
    }

    public struct SessionPromptEntry: Sendable, Equatable, Codable {
        public var timestampMs: UInt64
        public var text: String
    }

    public static let sessionVersion: UInt32 = 1

    public struct Session: Sendable, Equatable, Codable {
        public var version: UInt32
        public var sessionId: String
        public var createdAtMs: UInt64
        public var updatedAtMs: UInt64
        public var messages: [ConversationMessage]
        public var compaction: SessionCompaction?
        public var fork: SessionFork?
        public var workspaceRoot: String?
        public var promptHistory: [SessionPromptEntry]
        public var lastHealthCheckMs: UInt64
        public var model: String?

        public init(
            sessionId: String = Self.generateId(),
            workspaceRoot: String? = nil,
            model: String? = nil
        ) {
            let now = Self.currentTimeMillis()
            self.version = sessionVersion
            self.sessionId = sessionId
            self.createdAtMs = now
            self.updatedAtMs = now
            self.messages = []
            self.compaction = nil
            self.fork = nil
            self.workspaceRoot = workspaceRoot
            self.promptHistory = []
            self.lastHealthCheckMs = 0
            self.model = model
        }

        public mutating func pushMessage(_ msg: ConversationMessage) {
            messages.append(msg)
            updatedAtMs = Self.currentTimeMillis()
        }

        public mutating func pushUserText(_ text: String) {
            pushMessage(.userText(text))
        }

        public mutating func recordCompaction(summary: String, removedCount: Int) {
            compaction = SessionCompaction(
                count: (compaction?.count ?? 0) + 1,
                removedMessageCount: removedCount,
                summary: summary
            )
            updatedAtMs = Self.currentTimeMillis()
        }

        public mutating func pushPromptEntry(_ text: String) {
            promptHistory.append(SessionPromptEntry(
                timestampMs: Self.currentTimeMillis(), text: text
            ))
        }

        public func fork(branchName: String? = nil) -> Session {
            var s = Session(sessionId: Self.generateId(), workspaceRoot: workspaceRoot, model: model)
            s.messages = messages
            s.compaction = compaction
            s.promptHistory = promptHistory
            s.fork = SessionFork(parentSessionId: sessionId, branchName: branchName)
            return s
        }

        // MARK: - Monotonic timestamp + id

        private final class MonotonicClock: @unchecked Sendable {
            private let lock = NSLock()
            private var lastTimestampMs: UInt64 = 0
            private var idCounter: UInt64 = 0

            func nextMillis() -> UInt64 {
                lock.lock(); defer { lock.unlock() }
                let now = UInt64(Date().timeIntervalSince1970 * 1000)
                if now > lastTimestampMs { lastTimestampMs = now }
                else { lastTimestampMs &+= 1 }
                return lastTimestampMs
            }

            func nextId() -> String {
                lock.lock()
                idCounter &+= 1
                let counter = idCounter
                let now = UInt64(Date().timeIntervalSince1970 * 1000)
                if now > lastTimestampMs { lastTimestampMs = now }
                else { lastTimestampMs &+= 1 }
                let ts = lastTimestampMs
                lock.unlock()
                return "session-\(ts)-\(counter)"
            }
        }

        private static let clock = MonotonicClock()

        public static func currentTimeMillis() -> UInt64 { clock.nextMillis() }
        public static func generateId() -> String { clock.nextId() }
    }

    // MARK: - Compaction

    public struct CompactionConfig: Sendable, Equatable {
        public var preserveRecentMessages: Int
        public var maxEstimatedTokens: Int

        public init(preserveRecentMessages: Int = 4, maxEstimatedTokens: Int = 10_000) {
            self.preserveRecentMessages = preserveRecentMessages
            self.maxEstimatedTokens = maxEstimatedTokens
        }
    }

    public struct CompactionResult: Sendable, Equatable {
        public var summary: String
        public var formattedSummary: String
        public var compactedSession: Session
        public var removedMessageCount: Int
    }

    public static func estimateSessionTokens(_ s: Session) -> Int {
        s.messages.reduce(0) { acc, msg in
            var n = 0
            for block in msg.blocks {
                switch block {
                case .text(let t): n += t.count / 4 + 1
                case .toolUse(_, let name, let input):
                    n += name.count / 4 + 1
                    if let data = try? JSONEncoder().encode(input) {
                        n += data.count / 4 + 1
                    }
                case .toolResult(_, let name, let out, _):
                    n += (name.count + out.count) / 4 + 1
                }
            }
            return acc + n
        }
    }

    public static func shouldCompact(_ s: Session, config: CompactionConfig) -> Bool {
        let tokens = estimateSessionTokens(s)
        let messages = s.messages
        let summaryPrefix = (messages.first.map { isCompactSummaryMessage($0) } ?? false) ? 1 : 0
        let compactable = messages.count - summaryPrefix
        return compactable > config.preserveRecentMessages && tokens >= config.maxEstimatedTokens
    }

    public static func compactSession(_ s: Session, config: CompactionConfig) -> CompactionResult {
        guard shouldCompact(s, config: config) else {
            return CompactionResult(
                summary: "", formattedSummary: "",
                compactedSession: s, removedMessageCount: 0
            )
        }
        let summaryPrefix = (s.messages.first.map { isCompactSummaryMessage($0) } ?? false) ? 1 : 0
        var keepFrom = max(summaryPrefix, s.messages.count - config.preserveRecentMessages)
        // avoid splitting tool_use/tool_result pair
        if keepFrom > 0 {
            let first = s.messages[keepFrom]
            if case .toolResult(let id, _, _, _) = first.blocks.first,
               case .toolUse(let prevId, _, _) = s.messages[keepFrom - 1].blocks.last, prevId == id {
                keepFrom -= 1
            }
        }
        let removed = Array(s.messages[summaryPrefix..<keepFrom])
        let preserved = Array(s.messages[keepFrom...])
        let summary = summarizeMessages(removed)
        let formatted = formatCompactSummary(summary)
        var newSession = s
        newSession.messages = [.userText(getCompactContinuationMessage(
            summary: formatted, suppressQuestions: true, recentPreserved: preserved
        ))] + preserved
        newSession.recordCompaction(summary: summary, removedCount: removed.count)
        return CompactionResult(
            summary: summary, formattedSummary: formatted,
            compactedSession: newSession, removedMessageCount: removed.count
        )
    }

    static let compactContinuationPreamble = "Continuing from a compacted summary of an earlier conversation."

    public static func getCompactContinuationMessage(
        summary: String, suppressQuestions: Bool, recentPreserved: [ConversationMessage]
    ) -> String {
        var s = compactContinuationPreamble + "\n\n" + summary
        if suppressQuestions {
            s += "\n\nDo not restate the summary; pick up from the preserved messages."
        }
        if !recentPreserved.isEmpty {
            s += "\n\n(\(recentPreserved.count) recent message(s) preserved.)"
        }
        return s
    }

    public static func formatCompactSummary(_ s: String) -> String {
        var result = s
            .replacingOccurrences(of: "<analysis>", with: "")
            .replacingOccurrences(of: "</analysis>", with: "")
            .replacingOccurrences(of: "<summary>", with: "Summary:\n")
            .replacingOccurrences(of: "</summary>", with: "")
        // collapse blank lines
        while result.contains("\n\n\n") {
            result = result.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func summarizeMessages(_ messages: [ConversationMessage]) -> String {
        var out = "<summary>\n"
        out += "Scope: \(messages.count) messages compacted\n"
        var userTexts: [String] = []
        for m in messages where m.role == .user {
            for b in m.blocks {
                if case .text(let t) = b, !t.isEmpty { userTexts.append(t) }
            }
        }
        if !userTexts.isEmpty {
            out += "- Recent user requests:\n"
            for t in userTexts.suffix(3) {
                out += "  - \(t)\n"
            }
        }
        out += "</summary>"
        return out
    }

    static func isCompactSummaryMessage(_ m: ConversationMessage) -> Bool {
        guard m.role == .user else { return false }
        for b in m.blocks {
            if case .text(let t) = b, t.hasPrefix(compactContinuationPreamble) {
                return true
            }
        }
        return false
    }
}
