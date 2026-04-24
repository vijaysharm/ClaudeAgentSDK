import Foundation

/// Tool registry + DTOs ported from the Rust `tools` crate.
///
/// This is the thin Swift facade over the Rust tool specs. It exposes the tool
/// manifest table, the `ToolSpec`/`ToolRegistry` shapes, and the lane-completion
/// detector from `tools::lane_completion`.
public enum ClawTools {

    // MARK: - Manifest

    public enum ToolSource: String, Sendable, Codable, Equatable {
        case base
        case conditional
    }

    public struct ToolManifestEntry: Sendable, Equatable, Codable {
        public let name: String
        public let source: ToolSource
    }

    public struct ToolRegistry: Sendable, Equatable, Codable {
        public let entries: [ToolManifestEntry]
    }

    // MARK: - Tool spec

    public struct ToolSpec: Sendable, Equatable, Codable {
        public let name: String
        public let description: String
        public let inputSchema: AnyCodable
        public let requiredPermission: ClawRuntime.PermissionMode
    }

    /// Minimum-viable tool set exposed by Claw Code. Matches the Rust
    /// `tools::mvp_tool_specs()` table at a high level.
    public static func mvpToolSpecs() -> [ToolSpec] {
        [
            ToolSpec(
                name: "bash",
                description: "Run a shell command and capture output.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "command": .object(["type": .string("string")]),
                        "timeout": .object(["type": .string("number")]),
                        "description": .object(["type": .string("string")]),
                    ]),
                    "required": .array([.string("command")]),
                ]),
                requiredPermission: .workspaceWrite
            ),
            ToolSpec(
                name: "read_file",
                description: "Read a file from disk.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "path": .object(["type": .string("string")]),
                        "offset": .object(["type": .string("number")]),
                        "limit": .object(["type": .string("number")]),
                    ]),
                    "required": .array([.string("path")]),
                ]),
                requiredPermission: .readOnly
            ),
            ToolSpec(
                name: "write_file",
                description: "Create or overwrite a file on disk.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "path": .object(["type": .string("string")]),
                        "content": .object(["type": .string("string")]),
                    ]),
                    "required": .array([.string("path"), .string("content")]),
                ]),
                requiredPermission: .workspaceWrite
            ),
            ToolSpec(
                name: "edit_file",
                description: "Edit a file by replacing a string literally.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "path": .object(["type": .string("string")]),
                        "old_string": .object(["type": .string("string")]),
                        "new_string": .object(["type": .string("string")]),
                        "replace_all": .object(["type": .string("boolean")]),
                    ]),
                    "required": .array([.string("path"), .string("old_string"), .string("new_string")]),
                ]),
                requiredPermission: .workspaceWrite
            ),
            ToolSpec(
                name: "glob_search",
                description: "Find files by glob pattern.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "pattern": .object(["type": .string("string")]),
                        "path": .object(["type": .string("string")]),
                    ]),
                    "required": .array([.string("pattern")]),
                ]),
                requiredPermission: .readOnly
            ),
            ToolSpec(
                name: "grep_search",
                description: "Regex search across files.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "pattern": .object(["type": .string("string")]),
                        "path": .object(["type": .string("string")]),
                    ]),
                    "required": .array([.string("pattern")]),
                ]),
                requiredPermission: .readOnly
            ),
        ]
    }

    // MARK: - Global tool registry

    public struct ToolSearchOutput: Sendable, Equatable, Codable {
        public var matches: [String]
        public var query: String
        public var normalizedQuery: String
        public var totalDeferredTools: Int
        public var pendingMcpServers: [String]?
        public var mcpDegraded: ClawRuntime.McpDegradedReport?
    }

    public final class GlobalToolRegistry: @unchecked Sendable {
        public private(set) var pluginTools: [ClawPlugins.PluginTool]
        public private(set) var runtimeTools: [RuntimeToolDefinition]
        public private(set) var enforcer: ClawRuntime.PermissionEnforcer?

        public init(
            pluginTools: [ClawPlugins.PluginTool] = [],
            runtimeTools: [RuntimeToolDefinition] = [],
            enforcer: ClawRuntime.PermissionEnforcer? = nil
        ) {
            self.pluginTools = pluginTools
            self.runtimeTools = runtimeTools
            self.enforcer = enforcer
        }

        public static func builtin() -> GlobalToolRegistry { GlobalToolRegistry() }

        public func withPluginTools(_ tools: [ClawPlugins.PluginTool]) throws -> GlobalToolRegistry {
            var seen = Set(mvpToolSpecs().map(\.name))
            for t in tools {
                if seen.contains(t.definition.name) {
                    throw ClawPlugins.PluginError.invalidManifest("plugin tool name conflicts with builtin: \(t.definition.name)")
                }
                seen.insert(t.definition.name)
            }
            return GlobalToolRegistry(pluginTools: tools, runtimeTools: runtimeTools, enforcer: enforcer)
        }

        public func withRuntimeTools(_ tools: [RuntimeToolDefinition]) -> GlobalToolRegistry {
            GlobalToolRegistry(pluginTools: pluginTools, runtimeTools: tools, enforcer: enforcer)
        }

        public func withEnforcer(_ enf: ClawRuntime.PermissionEnforcer?) -> GlobalToolRegistry {
            GlobalToolRegistry(pluginTools: pluginTools, runtimeTools: runtimeTools, enforcer: enf)
        }

        public func hasRuntimeTool(_ name: String) -> Bool {
            runtimeTools.contains { $0.name == name }
        }

        /// Tokenized search over builtin + runtime + plugin tool names.
        public func search(
            query: String,
            maxResults: Int = 5,
            pendingMcpServers: [String]? = nil,
            mcpDegraded: ClawRuntime.McpDegradedReport? = nil
        ) -> ToolSearchOutput {
            let normalized = query.lowercased()
            var names: [String] = mvpToolSpecs().map(\.name)
            names.append(contentsOf: runtimeTools.map(\.name))
            names.append(contentsOf: pluginTools.map { $0.definition.name })
            let scored = names
                .map { name -> (String, Int) in
                    let lower = name.lowercased()
                    if lower.hasPrefix(normalized) { return (name, 0) }
                    if lower.contains(normalized) { return (name, 1) }
                    return (name, ClawCommands.levenshtein(lower, normalized))
                }
                .sorted { $0.1 < $1.1 }
                .prefix(maxResults)
                .map(\.0)
            return ToolSearchOutput(
                matches: Array(scored),
                query: query,
                normalizedQuery: normalized,
                totalDeferredTools: pluginTools.count,
                pendingMcpServers: pendingMcpServers,
                mcpDegraded: mcpDegraded
            )
        }

        /// Normalize an `allowed_tools` input. Splits on commas/whitespace,
        /// expands aliases (`read` → `read_file`, etc.).
        public static func normalizeAllowedTools(_ raw: [String]) -> Set<String> {
            var out: Set<String> = []
            for part in raw {
                for token in part.split(whereSeparator: { ",\t\n ".contains($0) }) {
                    let lower = token.lowercased()
                    switch lower {
                    case "read": out.insert("read_file")
                    case "write": out.insert("write_file")
                    case "edit": out.insert("edit_file")
                    case "glob": out.insert("glob_search")
                    case "grep": out.insert("grep_search")
                    default: out.insert(String(lower))
                    }
                }
            }
            return out
        }
    }

    public struct RuntimeToolDefinition: Sendable, Equatable, Codable {
        public var name: String
        public var description: String?
        public var inputSchema: AnyCodable
        public var requiredPermission: ClawRuntime.PermissionMode
    }

    // MARK: - Lane completion detection

    public struct AgentOutput: Sendable, Equatable, Codable {
        public var agentId: String
        public var name: String
        public var description: String
        public var status: String
        public var laneEvents: [ClawRuntime.LaneEvent]
        public var currentBlocker: ClawRuntime.LaneEventBlocker?
        public var derivedState: String
        public var error: String?
    }

    public static func detectLaneCompletion(
        output: AgentOutput, testGreen: Bool, hasPushed: Bool
    ) -> ClawRuntime.LaneContext? {
        guard output.error == nil,
              ["completed", "finished"].contains(output.status.lowercased()),
              output.currentBlocker == nil,
              testGreen, hasPushed else { return nil }
        return ClawRuntime.LaneContext(
            laneId: output.agentId, greenLevel: 3, branchFreshness: 0,
            blocker: .none, reviewStatus: .approved, diffScope: .scoped,
            completed: true, reconciled: false
        )
    }

    public static func evaluateCompletedLane(_ context: ClawRuntime.LaneContext) -> [ClawRuntime.PolicyAction] {
        let engine = ClawRuntime.PolicyEngine(rules: [
            ClawRuntime.PolicyRule(
                name: "closeout-completed-lane",
                condition: .laneCompleted,
                action: .closeoutLane,
                priority: 0
            ),
            ClawRuntime.PolicyRule(
                name: "cleanup-completed-session",
                condition: .laneCompleted,
                action: .cleanupSession,
                priority: 1
            ),
        ])
        return ClawRuntime.evaluate(engine, context: context)
    }
}
