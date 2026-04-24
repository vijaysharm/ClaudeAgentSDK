import Foundation

/// Upstream-TS manifest extractor ported from the Rust `compat-harness` crate.
///
/// Parses a snapshot of the upstream Claude Code TypeScript source to recover
/// its command and tool registries plus the canonical bootstrap-phase order.
public enum ClawCompatHarness {

    public struct UpstreamPaths: Sendable, Equatable {
        public let repoRoot: String

        public var commandsPath: String { (repoRoot as NSString).appendingPathComponent("src/commands.ts") }
        public var toolsPath: String { (repoRoot as NSString).appendingPathComponent("src/tools.ts") }
        public var cliPath: String { (repoRoot as NSString).appendingPathComponent("src/entrypoints/cli.tsx") }

        public static func fromRepoRoot(_ path: String) -> UpstreamPaths {
            UpstreamPaths(repoRoot: path)
        }

        public static func fromWorkspaceDir(_ dir: String) -> UpstreamPaths? {
            let parent = (dir as NSString).deletingLastPathComponent
            let env = ProcessInfo.processInfo.environment
            var candidates: [String] = [parent]
            if let up = env["CLAUDE_CODE_UPSTREAM"] { candidates.append(up) }
            var current = dir
            for _ in 0..<4 {
                current = (current as NSString).deletingLastPathComponent
                candidates.append((current as NSString).appendingPathComponent("claw-code"))
                candidates.append((current as NSString).appendingPathComponent("clawd-code"))
            }
            candidates.append((parent as NSString).appendingPathComponent("reference-source/claw-code"))
            candidates.append((parent as NSString).appendingPathComponent("vendor/claw-code"))

            for c in candidates {
                let path = (c as NSString).appendingPathComponent("src/commands.ts")
                if FileManager.default.fileExists(atPath: path) {
                    return UpstreamPaths(repoRoot: c)
                }
            }
            return nil
        }
    }

    public struct ExtractedManifest: Sendable, Equatable {
        public let commands: ClawCommands.CommandRegistry
        public let tools: ClawTools.ToolRegistry
        public let bootstrap: ClawRuntime.BootstrapPlan
    }

    public static func extractManifest(_ paths: UpstreamPaths) throws -> ExtractedManifest {
        let cmdSource = try String(contentsOfFile: paths.commandsPath, encoding: .utf8)
        let toolSource = try String(contentsOfFile: paths.toolsPath, encoding: .utf8)
        let cliSource = try String(contentsOfFile: paths.cliPath, encoding: .utf8)
        return ExtractedManifest(
            commands: extractCommands(cmdSource),
            tools: extractTools(toolSource),
            bootstrap: extractBootstrapPlan(cliSource)
        )
    }

    // MARK: - Commands extraction

    public static func extractCommands(_ source: String) -> ClawCommands.CommandRegistry {
        var entries: [ClawCommands.CommandManifestEntry] = []
        var inInternalBlock = false

        for rawLine in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if inInternalBlock {
                if line.contains("]") { inInternalBlock = false; continue }
                if let name = firstIdentifier(line) {
                    entries.append(.init(name: name, source: .internalOnly))
                }
                continue
            }
            if line.contains("export const INTERNAL_ONLY_COMMANDS = [") {
                inInternalBlock = true
                continue
            }
            if line.hasPrefix("import ") {
                for symbol in importedSymbols(line) {
                    entries.append(.init(name: symbol, source: .builtin))
                }
            } else if line.contains("feature('") && line.contains("./commands/") {
                if let name = firstAssignmentIdentifier(line) {
                    entries.append(.init(name: name, source: .featureGated))
                }
            }
        }
        return ClawCommands.CommandRegistry(entries: dedupe(entries) { "\($0.name)|\($0.source.rawValue)" })
    }

    public static func extractTools(_ source: String) -> ClawTools.ToolRegistry {
        var entries: [ClawTools.ToolManifestEntry] = []
        for rawLine in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if line.hasPrefix("import ") && line.contains("./tools/") {
                for symbol in importedSymbols(line) where symbol.hasSuffix("Tool") {
                    entries.append(.init(name: symbol, source: .base))
                }
            } else if line.contains("feature('") {
                if let match = extractFeatureArg(line),
                   match.hasSuffix("Tool") || match.hasSuffix("Tools") {
                    entries.append(.init(name: match, source: .conditional))
                }
            }
        }
        return ClawTools.ToolRegistry(entries: dedupe(entries) { "\($0.name)|\($0.source.rawValue)" })
    }

    public static func extractBootstrapPlan(_ source: String) -> ClawRuntime.BootstrapPlan {
        var phases: [ClawRuntime.BootstrapPhase] = [.cliEntry]
        if source.contains("--version") { phases.append(.fastPathVersion) }
        if source.contains("startupProfiler") { phases.append(.startupProfiler) }
        if source.contains("--dump-system-prompt") { phases.append(.systemPromptFastPath) }
        if source.contains("--claude-in-chrome-mcp") { phases.append(.chromeMcpFastPath) }
        if source.contains("--daemon-worker") { phases.append(.daemonWorkerFastPath) }
        if source.contains("remote-control") { phases.append(.bridgeFastPath) }
        if source.contains("args[0] === 'daemon'") { phases.append(.daemonFastPath) }
        if source.contains("args[0] === 'ps'") || source.contains("args.includes('--bg')") {
            phases.append(.backgroundSessionFastPath)
        }
        if source.contains("args[0] === 'new'") || source.contains("args[0] === 'list'")
            || source.contains("args[0] === 'reply'") {
            phases.append(.templateFastPath)
        }
        if source.contains("environment-runner") { phases.append(.environmentRunnerFastPath) }
        phases.append(.mainRuntime)
        return ClawRuntime.BootstrapPlan.fromPhases(phases)
    }

    // MARK: - Helpers

    static func importedSymbols(_ line: String) -> [String] {
        guard let fromIdx = line.range(of: " from ") else { return [] }
        var remaining = String(line[..<fromIdx.lowerBound]).trimmingCharacters(in: .whitespaces)
        if remaining.hasPrefix("import ") { remaining = String(remaining.dropFirst("import ".count)) }
        if let openBrace = remaining.firstIndex(of: "{"),
           let closeBrace = remaining.firstIndex(of: "}") {
            let inner = remaining[remaining.index(after: openBrace)..<closeBrace]
            return inner.split(separator: ",").compactMap { clause -> String? in
                firstIdentifier(String(clause))
            }
        }
        // default import
        if let first = remaining.split(separator: ",").first.map(String.init) {
            return firstIdentifier(first).map { [$0] } ?? []
        }
        return []
    }

    static func firstAssignmentIdentifier(_ line: String) -> String? {
        let left = line.split(separator: "=").first.map(String.init) ?? line
        return firstIdentifier(left)
    }

    static func firstIdentifier(_ line: String) -> String? {
        var buf = ""
        for c in line {
            if c.isLetter || c.isNumber || c == "_" || c == "-" {
                buf.append(c)
            } else if !buf.isEmpty {
                break
            }
        }
        return buf.isEmpty ? nil : buf
    }

    static func extractFeatureArg(_ line: String) -> String? {
        guard let open = line.range(of: "feature('") else { return nil }
        let rest = line[open.upperBound...]
        guard let close = rest.firstIndex(of: "'") else { return nil }
        return String(rest[..<close])
    }

    static func dedupe<T: Hashable>(_ items: [T], key: (T) -> String) -> [T] {
        var seen: Set<String> = []
        return items.filter {
            let k = key($0)
            if seen.contains(k) { return false }
            seen.insert(k)
            return true
        }
    }
}
