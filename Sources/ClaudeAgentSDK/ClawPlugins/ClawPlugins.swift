import Foundation

/// Plugin registry and runner ported from the Rust `plugins` crate.
public enum ClawPlugins {

    // MARK: - Core types

    public enum PluginKind: String, Sendable, Codable, Equatable {
        case builtin, bundled, external

        public var marketplace: String {
            switch self {
            case .builtin: return "builtin"
            case .bundled: return "bundled"
            case .external: return "external"
            }
        }
    }

    public struct PluginMetadata: Sendable, Equatable, Codable {
        public var id: String
        public var name: String
        public var version: String
        public var description: String
        public var kind: PluginKind
        public var source: String
        public var defaultEnabled: Bool
        public var root: String?
    }

    public struct PluginHooks: Sendable, Equatable, Codable {
        public var preToolUse: [String]
        public var postToolUse: [String]
        public var postToolUseFailure: [String]

        public init(preToolUse: [String] = [], postToolUse: [String] = [], postToolUseFailure: [String] = []) {
            self.preToolUse = preToolUse
            self.postToolUse = postToolUse
            self.postToolUseFailure = postToolUseFailure
        }

        public var isEmpty: Bool {
            preToolUse.isEmpty && postToolUse.isEmpty && postToolUseFailure.isEmpty
        }

        public func mergedWith(_ other: PluginHooks) -> PluginHooks {
            PluginHooks(
                preToolUse: preToolUse + other.preToolUse,
                postToolUse: postToolUse + other.postToolUse,
                postToolUseFailure: postToolUseFailure + other.postToolUseFailure
            )
        }

        private enum CodingKeys: String, CodingKey {
            case preToolUse = "PreToolUse"
            case postToolUse = "PostToolUse"
            case postToolUseFailure = "PostToolUseFailure"
        }
    }

    public struct PluginLifecycle: Sendable, Equatable, Codable {
        public var initSteps: [String]
        public var shutdownSteps: [String]

        public init(initSteps: [String] = [], shutdownSteps: [String] = []) {
            self.initSteps = initSteps
            self.shutdownSteps = shutdownSteps
        }

        public var isEmpty: Bool { initSteps.isEmpty && shutdownSteps.isEmpty }

        private enum CodingKeys: String, CodingKey {
            case initSteps = "Init"
            case shutdownSteps = "Shutdown"
        }
    }

    public enum PluginPermission: String, Sendable, Codable, Equatable {
        case read, write, execute

        public static func parse(_ s: String) -> PluginPermission? { PluginPermission(rawValue: s.lowercased()) }
    }

    public enum PluginToolPermission: String, Sendable, Codable, Equatable {
        case readOnly = "read-only"
        case workspaceWrite = "workspace-write"
        case dangerFullAccess = "danger-full-access"

        public static func parse(_ s: String) -> PluginToolPermission? { PluginToolPermission(rawValue: s) }
    }

    public struct PluginToolManifest: Sendable, Equatable, Codable {
        public var name: String
        public var description: String
        public var inputSchema: AnyCodable
        public var command: String
        public var args: [String]
        public var requiredPermission: PluginToolPermission

        private enum CodingKeys: String, CodingKey {
            case name, description
            case inputSchema = "inputSchema"
            case command, args
            case requiredPermission = "required_permission"
        }
    }

    public struct PluginToolDefinition: Sendable, Equatable, Codable {
        public var name: String
        public var description: String?
        public var inputSchema: AnyCodable
    }

    public struct PluginCommandManifest: Sendable, Equatable, Codable {
        public var name: String
        public var description: String
        public var command: String
    }

    public struct PluginManifest: Sendable, Equatable, Codable {
        public var name: String
        public var version: String
        public var description: String
        public var permissions: [PluginPermission]
        public var defaultEnabled: Bool
        public var hooks: PluginHooks
        public var lifecycle: PluginLifecycle
        public var tools: [PluginToolManifest]
        public var commands: [PluginCommandManifest]
    }

    public struct PluginTool: Sendable, Equatable, Codable {
        public let pluginId: String
        public let pluginName: String
        public let definition: PluginToolDefinition
        public let command: String
        public let args: [String]
        public let requiredPermission: PluginToolPermission
        public let root: String?
    }

    public enum PluginInstallSource: Sendable, Equatable, Codable {
        case localPath(path: String)
        case gitUrl(url: String)

        private enum CodingKeys: String, CodingKey { case type, path, url }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            switch try c.decode(String.self, forKey: .type) {
            case "local_path":
                self = .localPath(path: try c.decode(String.self, forKey: .path))
            case "git_url":
                self = .gitUrl(url: try c.decode(String.self, forKey: .url))
            default:
                throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "unknown install source")
            }
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .localPath(let p):
                try c.encode("local_path", forKey: .type)
                try c.encode(p, forKey: .path)
            case .gitUrl(let u):
                try c.encode("git_url", forKey: .type)
                try c.encode(u, forKey: .url)
            }
        }
    }

    public struct InstalledPluginRecord: Sendable, Equatable, Codable {
        public var kind: PluginKind
        public var id: String
        public var name: String
        public var version: String
        public var description: String
        public var installPath: String
        public var source: PluginInstallSource
        public var installedAtUnixMs: UInt64
        public var updatedAtUnixMs: UInt64
    }

    public struct InstalledPluginRegistry: Sendable, Equatable, Codable {
        public var plugins: [String: InstalledPluginRecord] = [:]
    }

    // MARK: - Errors

    public struct PluginManifestValidationError: Error, Sendable, Equatable, Codable {
        public let message: String
    }

    public enum PluginError: Error, LocalizedError, Sendable {
        case io(String)
        case json(String)
        case manifestValidation([PluginManifestValidationError])
        case invalidManifest(String)
        case notFound(String)
        case commandFailed(String)

        public var errorDescription: String? {
            switch self {
            case .io(let m): return "plugin IO error: \(m)"
            case .json(let m): return "plugin JSON error: \(m)"
            case .manifestValidation(let errs):
                return "plugin manifest validation failed: " + errs.map(\.message).joined(separator: "; ")
            case .invalidManifest(let m): return "invalid plugin manifest: \(m)"
            case .notFound(let id): return "plugin not found: \(id)"
            case .commandFailed(let m): return "plugin command failed: \(m)"
            }
        }
    }

    // MARK: - Registry + summaries

    public struct PluginSummary: Sendable, Equatable, Codable {
        public var metadata: PluginMetadata
        public var enabled: Bool
    }

    public enum PluginDefinition: Sendable, Equatable {
        case builtin(BuiltinPlugin)
        case bundled(BundledPlugin)
        case external(ExternalPlugin)

        public var metadata: PluginMetadata {
            switch self {
            case .builtin(let p): return p.metadata
            case .bundled(let p): return p.metadata
            case .external(let p): return p.metadata
            }
        }

        public var hooks: PluginHooks {
            switch self {
            case .builtin(let p): return p.hooks
            case .bundled(let p): return p.hooks
            case .external(let p): return p.hooks
            }
        }

        public var tools: [PluginTool] {
            switch self {
            case .builtin(let p): return p.tools
            case .bundled(let p): return p.tools
            case .external(let p): return p.tools
            }
        }
    }

    public struct BuiltinPlugin: Sendable, Equatable {
        public var metadata: PluginMetadata
        public var hooks: PluginHooks
        public var lifecycle: PluginLifecycle
        public var tools: [PluginTool]
    }

    public struct BundledPlugin: Sendable, Equatable {
        public var metadata: PluginMetadata
        public var hooks: PluginHooks
        public var lifecycle: PluginLifecycle
        public var tools: [PluginTool]
    }

    public struct ExternalPlugin: Sendable, Equatable {
        public var metadata: PluginMetadata
        public var hooks: PluginHooks
        public var lifecycle: PluginLifecycle
        public var tools: [PluginTool]
    }

    public struct RegisteredPlugin: Sendable, Equatable {
        public var definition: PluginDefinition
        public var enabled: Bool

        public var metadata: PluginMetadata { definition.metadata }
        public var hooks: PluginHooks { definition.hooks }
        public var tools: [PluginTool] { definition.tools }
        public var summary: PluginSummary { PluginSummary(metadata: metadata, enabled: enabled) }
    }

    public struct PluginRegistry: Sendable, Equatable {
        public var plugins: [RegisteredPlugin]

        public init(plugins: [RegisteredPlugin]) {
            self.plugins = plugins.sorted(by: { $0.metadata.id < $1.metadata.id })
        }

        public func get(_ id: String) -> RegisteredPlugin? {
            plugins.first { $0.metadata.id == id }
        }

        public func contains(_ id: String) -> Bool { get(id) != nil }

        public func summaries() -> [PluginSummary] { plugins.map { $0.summary } }

        /// Merge hooks from all enabled plugins.
        public func aggregatedHooks() -> PluginHooks {
            var result = PluginHooks()
            for p in plugins where p.enabled {
                result = result.mergedWith(p.hooks)
            }
            return result
        }

        /// Flat list of tools from all enabled plugins. Throws on duplicate tool names.
        public func aggregatedTools() throws -> [PluginTool] {
            var result: [PluginTool] = []
            var seen: Set<String> = []
            for p in plugins where p.enabled {
                for t in p.tools {
                    if seen.contains(t.definition.name) {
                        throw PluginError.invalidManifest("duplicate plugin tool name: \(t.definition.name)")
                    }
                    seen.insert(t.definition.name)
                    result.append(t)
                }
            }
            return result
        }
    }

    // MARK: - Loader

    /// Load and validate a plugin manifest from a directory.
    public static func loadManifest(fromDirectory root: String) throws -> PluginManifest {
        let candidates = [
            (root as NSString).appendingPathComponent("plugin.json"),
            (root as NSString).appendingPathComponent(".claude-plugin/plugin.json"),
        ]
        guard let path = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            throw PluginError.notFound("plugin.json under \(root)")
        }
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            return try JSONDecoder().decode(PluginManifest.self, from: data)
        } catch let e as DecodingError {
            throw PluginError.json(String(describing: e))
        } catch {
            throw PluginError.io(error.localizedDescription)
        }
    }

    /// Example built-in plugin (placeholder, matches the Rust scaffold).
    public static func builtinPlugins() -> [PluginDefinition] {
        [.builtin(BuiltinPlugin(
            metadata: PluginMetadata(
                id: "example-builtin@builtin",
                name: "example-builtin",
                version: "0.1.0",
                description: "Example built-in plugin (scaffold)",
                kind: .builtin,
                source: "builtin",
                defaultEnabled: false,
                root: nil
            ),
            hooks: PluginHooks(),
            lifecycle: PluginLifecycle(),
            tools: []
        ))]
    }

    public static func pluginId(name: String, marketplace: String) -> String {
        "\(name)@\(marketplace)"
    }

    public static func sanitizePluginId(_ id: String) -> String {
        var s = ""
        for c in id {
            if c == "/" || c == "\\" || c == "@" || c == ":" { s.append("-") }
            else { s.append(c) }
        }
        return s
    }
}
