import Foundation

extension ClawRuntime {

    public static let systemPromptDynamicBoundary = "__SYSTEM_PROMPT_DYNAMIC_BOUNDARY__"
    public static let frontierModelName = "Claude Opus 4.6"
    public static let maxInstructionFileChars = 4_000
    public static let maxTotalInstructionChars = 12_000

    public struct ContextFile: Sendable, Equatable, Codable {
        public let path: String
        public let content: String
    }

    public struct ProjectContext: Sendable, Equatable {
        public var cwd: String
        public var currentDate: String
        public var gitStatus: String?
        public var gitDiff: String?
        public var gitContext: GitContext?
        public var instructionFiles: [ContextFile]

        public static func discover(cwd: String, currentDate: String) -> ProjectContext {
            ProjectContext(
                cwd: cwd, currentDate: currentDate,
                gitStatus: nil, gitDiff: nil, gitContext: nil,
                instructionFiles: ClawRuntime.discoverInstructionFiles(cwd: cwd)
            )
        }

        public static func discoverWithGit(cwd: String, currentDate: String) -> ProjectContext {
            var pc = discover(cwd: cwd, currentDate: currentDate)
            pc.gitContext = GitContext.detect(cwd: cwd)
            pc.gitStatus = ClawRuntime.runGit(
                ["--no-optional-locks", "status", "--short", "--branch"], cwd: cwd
            )
            let staged = ClawRuntime.runGit(["--no-optional-locks", "diff", "--cached"], cwd: cwd) ?? ""
            let unstaged = ClawRuntime.runGit(["--no-optional-locks", "diff"], cwd: cwd) ?? ""
            var diff = ""
            if !staged.isEmpty { diff += "## Staged\n" + staged }
            if !unstaged.isEmpty {
                if !diff.isEmpty { diff += "\n\n" }
                diff += "## Unstaged\n" + unstaged
            }
            if !diff.isEmpty { pc.gitDiff = diff }
            return pc
        }
    }

    public struct SystemPromptBuilder: Sendable, Equatable {
        public var outputStyleName: String?
        public var outputStylePrompt: String?
        public var osName: String?
        public var osVersion: String?
        public var appendSections: [String]
        public var projectContext: ProjectContext?

        public init(
            outputStyleName: String? = nil, outputStylePrompt: String? = nil,
            osName: String? = nil, osVersion: String? = nil,
            appendSections: [String] = [], projectContext: ProjectContext? = nil
        ) {
            self.outputStyleName = outputStyleName
            self.outputStylePrompt = outputStylePrompt
            self.osName = osName
            self.osVersion = osVersion
            self.appendSections = appendSections
            self.projectContext = projectContext
        }

        public func withOutputStyle(name: String, prompt: String) -> SystemPromptBuilder {
            var c = self; c.outputStyleName = name; c.outputStylePrompt = prompt; return c
        }

        public func withOS(_ name: String, _ version: String?) -> SystemPromptBuilder {
            var c = self; c.osName = name; c.osVersion = version; return c
        }

        public func withProjectContext(_ pc: ProjectContext) -> SystemPromptBuilder {
            var c = self; c.projectContext = pc; return c
        }

        public func appendSection(_ s: String) -> SystemPromptBuilder {
            var c = self; c.appendSections.append(s); return c
        }

        public func build() -> [String] {
            var sections: [String] = []
            sections.append(Self.introSection(hasOutputStyle: outputStyleName != nil))
            if let name = outputStyleName, let prompt = outputStylePrompt {
                sections.append("# Output Style: \(name)\n\(prompt)")
            }
            sections.append(Self.systemBulletsSection())
            sections.append(Self.doingTasksSection())
            sections.append(Self.executingActionsSection())
            sections.append(ClawRuntime.systemPromptDynamicBoundary)
            sections.append(renderEnvironmentContext())
            if let pc = projectContext { sections.append(renderProjectContext(pc)) }
            if let pc = projectContext, !pc.instructionFiles.isEmpty {
                sections.append(renderInstructionFiles(pc.instructionFiles))
            }
            sections.append(contentsOf: appendSections)
            return sections
        }

        public func render() -> String { build().joined(separator: "\n\n") }

        // MARK: - Rendering

        private static func introSection(hasOutputStyle: Bool) -> String {
            hasOutputStyle
                ? "You are Claude Code, Anthropic's CLI-based coding agent, following the requested output style."
                : "You are Claude Code, Anthropic's CLI-based coding agent."
        }

        private static func systemBulletsSection() -> String {
            """
            # System
             - Be concise and respectful of the user's time.
             - Prefer editing existing files to creating new ones.
             - Use tools conservatively and transparently.
             - Respect permission and sandbox constraints.
             - Surface errors with enough context to debug them.
             - Keep changes scoped and reversible.
            """
        }

        private static func doingTasksSection() -> String {
            """
            # Doing tasks
             - Read the user's goal fully before acting.
             - Gather information with read-only tools before writing.
             - Keep feedback loops short: plan, act, observe, repeat.
             - Commit deliberate units of work when asked.
             - Verify with tests/builds where possible.
             - Leave the workspace in a clean state.
            """
        }

        private static func executingActionsSection() -> String {
            """
            # Executing actions with care
            Prefer local, reversible actions. Confirm before destructive or
            shared-state changes. Communicate risks clearly.
            """
        }

        private func renderEnvironmentContext() -> String {
            var s = "# Environment context"
            s += "\n- Model family: \(ClawRuntime.frontierModelName)"
            if let pc = projectContext { s += "\n- cwd: \(pc.cwd)" }
            if let pc = projectContext { s += "\n- date: \(pc.currentDate)" }
            if let os = osName {
                if let v = osVersion {
                    s += "\n- platform: \(os) (\(v))"
                } else {
                    s += "\n- platform: \(os)"
                }
            }
            return s
        }

        private func renderProjectContext(_ pc: ProjectContext) -> String {
            var s = "# Project context"
            s += "\n- cwd: \(pc.cwd)"
            s += "\n- date: \(pc.currentDate)"
            if let status = pc.gitStatus { s += "\n\n## Git status\n\(status)" }
            if let ctx = pc.gitContext { s += "\n\n\(ctx.render())" }
            if let diff = pc.gitDiff {
                s += "\n\n## Git diff\n\(diff)"
            }
            return s
        }

        private func renderInstructionFiles(_ files: [ContextFile]) -> String {
            var s = "# Claude instructions"
            for f in files {
                let scope = ((f.path as NSString).deletingLastPathComponent as NSString).lastPathComponent
                s += "\n\n## \((f.path as NSString).lastPathComponent) (scope: \(scope))\n\(f.content)"
            }
            return s
        }
    }

    public static func prependBullets(_ items: [String]) -> [String] {
        items.map { " - \($0)" }
    }

    // MARK: - Instruction discovery

    public static func discoverInstructionFiles(cwd: String) -> [ContextFile] {
        var result: [ContextFile] = []
        var seen: Set<String> = []
        var running = 0

        let candidates = ["CLAUDE.md", "CLAUDE.local.md", ".claw/CLAUDE.md", ".claw/instructions.md"]
        var components = cwd.split(separator: "/").map(String.init)
        if cwd.hasPrefix("/") { components.insert("", at: 0) }
        // walk directories from root to cwd
        var dirs: [String] = []
        var acc = ""
        for c in components {
            acc = acc.isEmpty ? c : "\(acc)/\(c)"
            dirs.append(acc.isEmpty ? "/" : acc)
        }
        for dir in dirs {
            for candidate in candidates {
                let path = (dir as NSString).appendingPathComponent(candidate)
                guard FileManager.default.fileExists(atPath: path),
                      let raw = try? String(contentsOfFile: path, encoding: .utf8) else {
                    continue
                }
                let normalized = collapseBlankLines(raw).trimmingCharacters(in: .whitespacesAndNewlines)
                let key = normalized.lowercased()
                if seen.contains(key) { continue }
                seen.insert(key)

                var content = raw
                if content.count > maxInstructionFileChars {
                    content = String(content.prefix(maxInstructionFileChars)) + "\n\n[truncated]"
                }
                if running + content.count > maxTotalInstructionChars {
                    result.append(ContextFile(
                        path: path,
                        content: "_Additional instruction content omitted after reaching the prompt budget._"
                    ))
                    return result
                }
                running += content.count
                result.append(ContextFile(path: path, content: content))
            }
        }
        return result
    }

    static func collapseBlankLines(_ s: String) -> String {
        var out = ""
        var lastBlank = false
        for line in s.split(separator: "\n", omittingEmptySubsequences: false) {
            let isBlank = line.trimmingCharacters(in: .whitespaces).isEmpty
            if isBlank && lastBlank { continue }
            if !out.isEmpty { out += "\n" }
            out += String(line)
            lastBlank = isBlank
        }
        return out
    }
}
