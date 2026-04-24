import Foundation

/// Slash-command registry ported from the Rust `commands` crate.
///
/// This exposes the canonical ``ClawCommands/SlashCommand`` enum, aliases, the
/// static ``ClawCommands/slashCommandSpecs()`` table, and a parser that maps
/// user input like `"/compact"` into strongly-typed commands. The actual
/// dispatch (which would call into `runtime`/`plugins`) is left to the caller.
public enum ClawCommands {

    // MARK: - Manifest

    public enum CommandSource: String, Sendable, Codable, Equatable {
        case builtin, internalOnly = "internal-only", featureGated = "feature-gated"
    }

    public struct CommandManifestEntry: Sendable, Equatable, Codable {
        public let name: String
        public let source: CommandSource
    }

    public struct CommandRegistry: Sendable, Equatable, Codable {
        public let entries: [CommandManifestEntry]

        public init(entries: [CommandManifestEntry] = []) { self.entries = entries }
    }

    // MARK: - Spec table

    public struct SlashCommandSpec: Sendable, Equatable, Codable {
        public let name: String
        public let aliases: [String]
        public let summary: String
        public let argumentHint: String?
        public let resumeSupported: Bool
    }

    public enum SkillSlashDispatch: Sendable, Equatable {
        case local
        case invoke(String)
    }

    public static let slashCommandSpecTable: [SlashCommandSpec] = [
        SlashCommandSpec(name: "help", aliases: [], summary: "Show help and available commands", argumentHint: nil, resumeSupported: true),
        SlashCommandSpec(name: "status", aliases: [], summary: "Show session status", argumentHint: nil, resumeSupported: true),
        SlashCommandSpec(name: "compact", aliases: [], summary: "Compact the conversation history", argumentHint: nil, resumeSupported: true),
        SlashCommandSpec(name: "model", aliases: [], summary: "Show or change the active model", argumentHint: "<model>", resumeSupported: true),
        SlashCommandSpec(name: "permissions", aliases: [], summary: "Show or change permission mode", argumentHint: "<mode>", resumeSupported: true),
        SlashCommandSpec(name: "clear", aliases: [], summary: "Clear the current conversation", argumentHint: "[confirm]", resumeSupported: false),
        SlashCommandSpec(name: "cost", aliases: ["tokens"], summary: "Show token usage and estimated cost", argumentHint: nil, resumeSupported: true),
        SlashCommandSpec(name: "resume", aliases: [], summary: "Resume a prior session", argumentHint: "<path>", resumeSupported: false),
        SlashCommandSpec(name: "config", aliases: [], summary: "Show or edit configuration", argumentHint: "[section]", resumeSupported: true),
        SlashCommandSpec(name: "mcp", aliases: [], summary: "Manage MCP servers", argumentHint: "[list|enable|disable] <name>", resumeSupported: true),
        SlashCommandSpec(name: "memory", aliases: [], summary: "Show or edit saved memory", argumentHint: nil, resumeSupported: true),
        SlashCommandSpec(name: "init", aliases: [], summary: "Initialize CLAUDE.md", argumentHint: nil, resumeSupported: false),
        SlashCommandSpec(name: "diff", aliases: [], summary: "Show pending diff", argumentHint: nil, resumeSupported: true),
        SlashCommandSpec(name: "version", aliases: [], summary: "Print Claude Code version", argumentHint: nil, resumeSupported: true),
        SlashCommandSpec(name: "export", aliases: [], summary: "Export the session transcript", argumentHint: "[path]", resumeSupported: false),
        SlashCommandSpec(name: "session", aliases: [], summary: "Manage sessions", argumentHint: "<action> <target>", resumeSupported: true),
        SlashCommandSpec(name: "plugins", aliases: ["plugin", "marketplace"], summary: "Manage plugins", argumentHint: "<action> <name>", resumeSupported: true),
        SlashCommandSpec(name: "agents", aliases: [], summary: "List or manage agents", argumentHint: nil, resumeSupported: true),
        SlashCommandSpec(name: "skills", aliases: ["skill"], summary: "List or invoke skills", argumentHint: "[name]", resumeSupported: true),
        SlashCommandSpec(name: "doctor", aliases: ["providers"], summary: "Run environment diagnostics", argumentHint: nil, resumeSupported: true),
        SlashCommandSpec(name: "stats", aliases: ["tokens", "cache"], summary: "Show usage statistics", argumentHint: nil, resumeSupported: true),
        SlashCommandSpec(name: "review", aliases: [], summary: "Run review workflow", argumentHint: "[scope]", resumeSupported: true),
        SlashCommandSpec(name: "plan", aliases: [], summary: "Enter/exit plan mode", argumentHint: "[mode]", resumeSupported: true),
        SlashCommandSpec(name: "hooks", aliases: [], summary: "Manage hooks", argumentHint: nil, resumeSupported: true),
        SlashCommandSpec(name: "context", aliases: [], summary: "Show context", argumentHint: "[action]", resumeSupported: true),
        SlashCommandSpec(name: "output-style", aliases: [], summary: "Show or change output style", argumentHint: "[style]", resumeSupported: true),
        SlashCommandSpec(name: "add-dir", aliases: [], summary: "Add a directory to workspace", argumentHint: "<path>", resumeSupported: false),
    ]

    public static func slashCommandSpecs() -> [SlashCommandSpec] { slashCommandSpecTable }

    public static func resumeSupportedSlashCommands() -> [SlashCommandSpec] {
        slashCommandSpecTable.filter { $0.resumeSupported }
    }

    // MARK: - SlashCommand enum (parsed command)

    public enum SlashCommand: Sendable, Equatable {
        case help
        case status
        case compact
        case model(String?)
        case permissions(String?)
        case clear(confirm: Bool)
        case cost
        case resume(path: String?)
        case config(section: String?)
        case mcp(action: String?, target: String?)
        case memory
        case initialize
        case diff
        case version
        case export(path: String?)
        case session(action: String?, target: String?)
        case plugins(action: String?, target: String?)
        case agents(args: String?)
        case skills(args: String?)
        case doctor
        case stats
        case plan(mode: String?)
        case review(scope: String?)
        case hooks(args: String?)
        case context(action: String?)
        case outputStyle(style: String?)
        case addDir(path: String?)
        case unknown(String)

        public var slashName: String {
            switch self {
            case .help: return "/help"
            case .status: return "/status"
            case .compact: return "/compact"
            case .model: return "/model"
            case .permissions: return "/permissions"
            case .clear: return "/clear"
            case .cost: return "/cost"
            case .resume: return "/resume"
            case .config: return "/config"
            case .mcp: return "/mcp"
            case .memory: return "/memory"
            case .initialize: return "/init"
            case .diff: return "/diff"
            case .version: return "/version"
            case .export: return "/export"
            case .session: return "/session"
            case .plugins: return "/plugins"
            case .agents: return "/agents"
            case .skills: return "/skills"
            case .doctor: return "/doctor"
            case .stats: return "/stats"
            case .plan: return "/plan"
            case .review: return "/review"
            case .hooks: return "/hooks"
            case .context: return "/context"
            case .outputStyle: return "/output-style"
            case .addDir: return "/add-dir"
            case .unknown(let n): return "/\(n)"
            }
        }
    }

    public struct SlashCommandParseError: Error, Sendable, Equatable {
        public let message: String
    }

    /// Parse an input string into a ``SlashCommand``. Returns `nil` if the
    /// input doesn't start with `/`.
    public static func parse(_ input: String) throws -> SlashCommand? {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("/") else { return nil }
        let afterSlash = trimmed.dropFirst()
        let parts = afterSlash.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard let rawName = parts.first.map(String.init) else { return .help }
        let rest = parts.count > 1 ? String(parts[1]) : nil
        let name = canonicalName(rawName)

        switch name {
        case "help": return .help
        case "status": return .status
        case "compact": return .compact
        case "model": return .model(rest)
        case "permissions":
            if let r = rest, !validPermissionMode(r) {
                throw SlashCommandParseError(message: "invalid permission mode: \(r)")
            }
            return .permissions(rest)
        case "clear":
            return .clear(confirm: rest == "confirm")
        case "cost": return .cost
        case "resume": return .resume(path: rest)
        case "config": return .config(section: rest)
        case "mcp":
            let (action, target) = splitTwo(rest)
            return .mcp(action: action, target: target)
        case "memory": return .memory
        case "init": return .initialize
        case "diff": return .diff
        case "version": return .version
        case "export": return .export(path: rest)
        case "session":
            let (action, target) = splitTwo(rest)
            return .session(action: action, target: target)
        case "plugins":
            let (action, target) = splitTwo(rest)
            return .plugins(action: action, target: target)
        case "agents": return .agents(args: rest)
        case "skills": return .skills(args: rest)
        case "doctor": return .doctor
        case "stats": return .stats
        case "plan": return .plan(mode: rest)
        case "review": return .review(scope: rest)
        case "hooks": return .hooks(args: rest)
        case "context": return .context(action: rest)
        case "output-style": return .outputStyle(style: rest)
        case "add-dir": return .addDir(path: rest)
        case "login", "logout":
            throw SlashCommandParseError(message: "/\(name) was removed; authenticate via ANTHROPIC_API_KEY")
        default:
            return .unknown(name)
        }
    }

    public static func classifySkillsSlashCommand(_ args: String?) -> SkillSlashDispatch {
        guard let args = args?.trimmingCharacters(in: .whitespaces), !args.isEmpty else {
            return .local
        }
        let lower = args.lowercased()
        if lower == "list" || lower == "help" || lower == "-h" || lower == "--help" {
            return .local
        }
        if lower.hasPrefix("install") { return .local }
        return .invoke("$\(args)")
    }

    // MARK: - Suggestions

    public static func suggestSlashCommands(_ input: String, limit: Int = 5) -> [String] {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        let needle = trimmed.hasPrefix("/") ? String(trimmed.dropFirst()) : trimmed
        let lowerNeedle = needle.lowercased()
        var scored: [(String, Int, Int)] = []
        for spec in slashCommandSpecTable {
            let candidates = [spec.name] + spec.aliases
            for candidate in candidates {
                let lower = candidate.lowercased()
                let rank: Int
                if lower.hasPrefix(lowerNeedle) || lowerNeedle.hasPrefix(lower) { rank = 0 }
                else if lower.contains(lowerNeedle) { rank = 1 }
                else { rank = 2 }
                let distance = levenshtein(lowerNeedle, lower)
                if rank < 2 || distance <= 2 {
                    scored.append(("/\(candidate)", rank, distance))
                }
            }
        }
        scored.sort { a, b in
            if a.1 != b.1 { return a.1 < b.1 }
            return a.2 < b.2
        }
        var seen: Set<String> = []
        var out: [String] = []
        for (name, _, _) in scored {
            if seen.contains(name) { continue }
            seen.insert(name)
            out.append(name)
            if out.count >= limit { break }
        }
        return out
    }

    // MARK: - Helpers

    static func canonicalName(_ name: String) -> String {
        let lower = name.lowercased()
        for spec in slashCommandSpecTable {
            if spec.name == lower || spec.aliases.contains(lower) { return spec.name }
        }
        return lower
    }

    static func validPermissionMode(_ s: String) -> Bool {
        ["read-only", "workspace-write", "danger-full-access"].contains(s)
    }

    static func splitTwo(_ rest: String?) -> (String?, String?) {
        guard let rest else { return (nil, nil) }
        let parts = rest.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        let a = parts.first.map(String.init)
        let b = parts.count > 1 ? String(parts[1]) : nil
        return (a, b)
    }

    public static func levenshtein(_ a: String, _ b: String) -> Int {
        let ac = Array(a), bc = Array(b)
        if ac.isEmpty { return bc.count }
        if bc.isEmpty { return ac.count }
        var prev = Array(0...bc.count)
        var curr = Array(repeating: 0, count: bc.count + 1)
        for i in 1...ac.count {
            curr[0] = i
            for j in 1...bc.count {
                let cost = ac[i - 1] == bc[j - 1] ? 0 : 1
                curr[j] = min(prev[j] + 1, min(curr[j - 1] + 1, prev[j - 1] + cost))
            }
            swap(&prev, &curr)
        }
        return prev[bc.count]
    }
}
