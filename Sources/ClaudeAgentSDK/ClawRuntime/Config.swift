import Foundation

extension ClawRuntime {

    // MARK: - Config source + entries

    public enum ConfigSource: String, Sendable, Codable, Equatable, Comparable {
        case user, project, local

        private var rank: Int {
            switch self { case .user: return 0; case .project: return 1; case .local: return 2 }
        }
        public static func < (a: Self, b: Self) -> Bool { a.rank < b.rank }
    }

    public enum ResolvedPermissionMode: String, Sendable, Codable, Equatable {
        case readOnly = "read-only"
        case workspaceWrite = "workspace-write"
        case dangerFullAccess = "danger-full-access"

        public static func fromLabel(_ s: String) -> ResolvedPermissionMode? {
            switch s {
            case "default", "plan", "read-only": return .readOnly
            case "acceptEdits", "auto", "workspace-write": return .workspaceWrite
            case "dontAsk", "danger-full-access": return .dangerFullAccess
            default: return nil
            }
        }
    }

    public struct ConfigEntry: Sendable, Equatable, Codable {
        public let source: ConfigSource
        public let path: String
    }

    public enum ConfigError: Error, LocalizedError, Sendable {
        case io(String)
        case parse(String)

        public var errorDescription: String? {
            switch self {
            case .io(let m): return "IO error: \(m)"
            case .parse(let m): return "parse error: \(m)"
            }
        }
    }

    // MARK: - MCP transport + scoped types (mirrors config.rs)

    public enum McpTransport: String, Sendable, Codable, Equatable {
        case stdio, sse, http, ws, sdk
        case managedProxy = "managed-proxy"
    }

    public struct McpStdioServerConfig: Sendable, Equatable, Codable {
        public var command: String
        public var args: [String]
        public var env: [String: String]
        public var toolCallTimeoutMs: UInt64?
    }

    public struct McpOAuthConfig: Sendable, Equatable, Codable {
        public var clientId: String?
        public var callbackPort: UInt16?
        public var authServerMetadataUrl: String?
        public var xaa: Bool?
    }

    public struct McpRemoteServerConfig: Sendable, Equatable, Codable {
        public var url: String
        public var headers: [String: String]
        public var headersHelper: String?
        public var oauth: McpOAuthConfig?
    }

    public struct McpWebSocketServerConfig: Sendable, Equatable, Codable {
        public var url: String
        public var headers: [String: String]
        public var headersHelper: String?
    }

    public struct McpSdkServerConfig: Sendable, Equatable, Codable {
        public var name: String
    }

    public struct McpManagedProxyServerConfig: Sendable, Equatable, Codable {
        public var url: String
        public var id: String
    }

    public enum McpServerConfig: Sendable, Equatable {
        case stdio(McpStdioServerConfig)
        case sse(McpRemoteServerConfig)
        case http(McpRemoteServerConfig)
        case ws(McpWebSocketServerConfig)
        case sdk(McpSdkServerConfig)
        case managedProxy(McpManagedProxyServerConfig)

        public var transport: McpTransport {
            switch self {
            case .stdio: return .stdio
            case .sse: return .sse
            case .http: return .http
            case .ws: return .ws
            case .sdk: return .sdk
            case .managedProxy: return .managedProxy
            }
        }
    }

    public struct ScopedMcpServerConfig: Sendable, Equatable {
        public var scope: ConfigSource
        public var config: McpServerConfig
        public var transport: McpTransport { config.transport }
    }

    public struct McpConfigCollection: Sendable, Equatable {
        public var servers: [String: ScopedMcpServerConfig] = [:]
    }

    // MARK: - Feature configs

    public struct RuntimeHookConfig: Sendable, Equatable, Codable {
        public var preToolUse: [String]
        public var postToolUse: [String]
        public var postToolUseFailure: [String]

        public init(preToolUse: [String] = [], postToolUse: [String] = [], postToolUseFailure: [String] = []) {
            self.preToolUse = preToolUse
            self.postToolUse = postToolUse
            self.postToolUseFailure = postToolUseFailure
        }

        public func merged(with other: RuntimeHookConfig) -> RuntimeHookConfig {
            RuntimeHookConfig(
                preToolUse: extendUnique(preToolUse, other.preToolUse),
                postToolUse: extendUnique(postToolUse, other.postToolUse),
                postToolUseFailure: extendUnique(postToolUseFailure, other.postToolUseFailure)
            )
        }
    }

    public struct RuntimePluginConfig: Sendable, Equatable, Codable {
        public var enabledPlugins: [String: Bool]
        public var externalDirectories: [String]
        public var installRoot: String?
        public var registryPath: String?
        public var bundledRoot: String?
        public var maxOutputTokens: UInt32?

        public init(
            enabledPlugins: [String: Bool] = [:],
            externalDirectories: [String] = [],
            installRoot: String? = nil,
            registryPath: String? = nil,
            bundledRoot: String? = nil,
            maxOutputTokens: UInt32? = nil
        ) {
            self.enabledPlugins = enabledPlugins
            self.externalDirectories = externalDirectories
            self.installRoot = installRoot
            self.registryPath = registryPath
            self.bundledRoot = bundledRoot
            self.maxOutputTokens = maxOutputTokens
        }

        public mutating func setMaxOutputTokens(_ n: UInt32?) {
            maxOutputTokens = n
        }

        public mutating func setPluginState(_ id: String, enabled: Bool) {
            enabledPlugins[id] = enabled
        }

        public func stateFor(_ id: String, defaultEnabled: Bool) -> Bool {
            enabledPlugins[id] ?? defaultEnabled
        }
    }

    public struct ProviderFallbackConfig: Sendable, Equatable, Codable {
        public var primary: String?
        public var fallbacks: [String]

        public var isEmpty: Bool { primary == nil && fallbacks.isEmpty }
    }

    public struct RuntimeFeatureConfig: Sendable, Equatable, Codable {
        public var hooks: RuntimeHookConfig
        public var plugins: RuntimePluginConfig
        public var oauth: OAuthConfig?
        public var model: String?
        public var aliases: [String: String]
        public var permissionMode: ResolvedPermissionMode?
        public var permissionRules: RuntimePermissionRuleConfig
        public var sandbox: SandboxConfig
        public var providerFallbacks: ProviderFallbackConfig
        public var trustedRoots: [String]

        public init(
            hooks: RuntimeHookConfig = RuntimeHookConfig(),
            plugins: RuntimePluginConfig = RuntimePluginConfig(),
            oauth: OAuthConfig? = nil,
            model: String? = nil,
            aliases: [String: String] = [:],
            permissionMode: ResolvedPermissionMode? = nil,
            permissionRules: RuntimePermissionRuleConfig = RuntimePermissionRuleConfig(),
            sandbox: SandboxConfig = SandboxConfig(),
            providerFallbacks: ProviderFallbackConfig = ProviderFallbackConfig(primary: nil, fallbacks: []),
            trustedRoots: [String] = []
        ) {
            self.hooks = hooks
            self.plugins = plugins
            self.oauth = oauth
            self.model = model
            self.aliases = aliases
            self.permissionMode = permissionMode
            self.permissionRules = permissionRules
            self.sandbox = sandbox
            self.providerFallbacks = providerFallbacks
            self.trustedRoots = trustedRoots
        }
    }

    public struct RuntimeConfig: Sendable, Equatable {
        public var merged: [String: AnyCodable]
        public var loadedEntries: [ConfigEntry]
        public var feature: RuntimeFeatureConfig
        public var mcp: McpConfigCollection

        public init(
            merged: [String: AnyCodable] = [:],
            loadedEntries: [ConfigEntry] = [],
            feature: RuntimeFeatureConfig = RuntimeFeatureConfig(),
            mcp: McpConfigCollection = McpConfigCollection()
        ) {
            self.merged = merged
            self.loadedEntries = loadedEntries
            self.feature = feature
            self.mcp = mcp
        }
    }

    // MARK: - ConfigLoader

    public struct ConfigLoader: Sendable, Equatable {
        public var cwd: String
        public var configHome: String

        public init(cwd: String, configHome: String) {
            self.cwd = cwd
            self.configHome = configHome
        }

        public static func defaultFor(cwd: String) -> ConfigLoader {
            ConfigLoader(cwd: cwd, configHome: defaultConfigHome())
        }

        /// The five possible entries, in lowest-to-highest precedence.
        public func discover() -> [ConfigEntry] {
            let parent = (configHome as NSString).deletingLastPathComponent
            return [
                ConfigEntry(source: .user, path: (parent as NSString).appendingPathComponent(".claw.json")),
                ConfigEntry(source: .user, path: (configHome as NSString).appendingPathComponent("settings.json")),
                ConfigEntry(source: .project, path: (cwd as NSString).appendingPathComponent(".claw.json")),
                ConfigEntry(source: .project, path: (cwd as NSString).appendingPathComponent(".claw/settings.json")),
                ConfigEntry(source: .local, path: (cwd as NSString).appendingPathComponent(".claw/settings.local.json")),
            ]
        }

        /// Load + merge all discovered config files. Missing files are skipped.
        /// Merge is deep (object+object recurses; otherwise later wins).
        public func load() throws -> RuntimeConfig {
            var merged: [String: AnyCodable] = [:]
            var loadedEntries: [ConfigEntry] = []
            var scopedServers: [String: ScopedMcpServerConfig] = [:]

            for entry in discover() {
                guard FileManager.default.fileExists(atPath: entry.path) else { continue }
                try checkUnsupportedFormat(path: entry.path)
                guard let data = try? Data(contentsOf: URL(fileURLWithPath: entry.path)) else { continue }
                let parsed: [String: AnyCodable]
                do {
                    parsed = try JSONDecoder().decode([String: AnyCodable].self, from: data)
                } catch {
                    if entry.path.hasSuffix(".claw.json") { continue } // legacy silently skip
                    throw ConfigError.parse("\(entry.path): \(error)")
                }

                if let mcp = parsed["mcpServers"]?.objectValue {
                    for (name, value) in mcp {
                        if let serverObj = value.objectValue,
                           let scoped = parseScopedMcpServer(name: name, value: serverObj, scope: entry.source) {
                            scopedServers[name] = scoped
                        }
                    }
                }
                merged = deepMerge(merged, parsed)
                loadedEntries.append(entry)
            }

            var feature = parseFeatureConfig(merged)
            var mcp = McpConfigCollection()
            mcp.servers = scopedServers
            feature.providerFallbacks = parseProviderFallbacks(merged["providerFallbacks"])
            feature.trustedRoots = merged["trustedRoots"]?.arrayValue?
                .compactMap { $0.stringValue } ?? []
            return RuntimeConfig(
                merged: merged,
                loadedEntries: loadedEntries,
                feature: feature,
                mcp: mcp
            )
        }
    }

    // MARK: - Parsing helpers

    public static func defaultConfigHome() -> String {
        let env = ProcessInfo.processInfo.environment
        if let home = env["CLAW_CONFIG_HOME"], !home.isEmpty { return home }
        if let home = env["HOME"], !home.isEmpty {
            return (home as NSString).appendingPathComponent(".claw")
        }
        return (FileManager.default.currentDirectoryPath as NSString).appendingPathComponent(".claw")
    }

    static func deepMerge(_ a: [String: AnyCodable], _ b: [String: AnyCodable]) -> [String: AnyCodable] {
        var result = a
        for (k, v) in b {
            if case .object(let left) = result[k] ?? .null, case .object(let right) = v {
                result[k] = .object(deepMerge(left, right))
            } else {
                result[k] = v
            }
        }
        return result
    }

    static func extendUnique(_ a: [String], _ b: [String]) -> [String] {
        var seen = Set(a)
        var out = a
        for s in b where !seen.contains(s) {
            out.append(s); seen.insert(s)
        }
        return out
    }

    static func parseFeatureConfig(_ merged: [String: AnyCodable]) -> RuntimeFeatureConfig {
        var feature = RuntimeFeatureConfig()
        feature.model = merged["model"]?.stringValue
        if let aliases = merged["aliases"]?.objectValue {
            var map: [String: String] = [:]
            for (k, v) in aliases { if let s = v.stringValue { map[k] = s } }
            feature.aliases = map
        }
        if let mode = merged["permissionMode"]?.stringValue {
            feature.permissionMode = ResolvedPermissionMode.fromLabel(mode)
        } else if let pm = merged["permissions"]?.objectValue,
                  let mode = pm["defaultMode"]?.stringValue {
            feature.permissionMode = ResolvedPermissionMode.fromLabel(mode)
        }
        if let hooks = merged["hooks"]?.objectValue {
            feature.hooks = RuntimeHookConfig(
                preToolUse: hooks["PreToolUse"]?.arrayValue?.compactMap { $0.stringValue } ?? [],
                postToolUse: hooks["PostToolUse"]?.arrayValue?.compactMap { $0.stringValue } ?? [],
                postToolUseFailure: hooks["PostToolUseFailure"]?.arrayValue?.compactMap { $0.stringValue } ?? []
            )
        }
        if let perm = merged["permissions"]?.objectValue {
            feature.permissionRules = RuntimePermissionRuleConfig(
                allow: perm["allow"]?.arrayValue?.compactMap { $0.stringValue } ?? [],
                deny: perm["deny"]?.arrayValue?.compactMap { $0.stringValue } ?? [],
                ask: perm["ask"]?.arrayValue?.compactMap { $0.stringValue } ?? []
            )
        }
        return feature
    }

    static func parseProviderFallbacks(_ v: AnyCodable?) -> ProviderFallbackConfig {
        guard let obj = v?.objectValue else {
            return ProviderFallbackConfig(primary: nil, fallbacks: [])
        }
        return ProviderFallbackConfig(
            primary: obj["primary"]?.stringValue,
            fallbacks: obj["fallbacks"]?.arrayValue?.compactMap { $0.stringValue } ?? []
        )
    }

    static func parseScopedMcpServer(
        name: String, value: [String: AnyCodable], scope: ConfigSource
    ) -> ScopedMcpServerConfig? {
        var kind = value["type"]?.stringValue
        if kind == nil {
            kind = value["url"] != nil ? "http" : "stdio"
        }
        if name == "claudeai-proxy" { kind = "managed-proxy" }
        switch kind {
        case "stdio":
            return ScopedMcpServerConfig(
                scope: scope,
                config: .stdio(McpStdioServerConfig(
                    command: value["command"]?.stringValue ?? "",
                    args: value["args"]?.arrayValue?.compactMap { $0.stringValue } ?? [],
                    env: value["env"]?.objectValue?
                        .reduce(into: [String: String]()) { dict, kv in
                            if let s = kv.value.stringValue { dict[kv.key] = s }
                        } ?? [:],
                    toolCallTimeoutMs: value["toolCallTimeoutMs"]?.intValue.map(UInt64.init)
                ))
            )
        case "sse", "http":
            let remote = McpRemoteServerConfig(
                url: value["url"]?.stringValue ?? "",
                headers: value["headers"]?.objectValue?
                    .reduce(into: [String: String]()) { dict, kv in
                        if let s = kv.value.stringValue { dict[kv.key] = s }
                    } ?? [:],
                headersHelper: value["headersHelper"]?.stringValue,
                oauth: nil
            )
            return ScopedMcpServerConfig(
                scope: scope,
                config: kind == "sse" ? .sse(remote) : .http(remote)
            )
        case "ws":
            return ScopedMcpServerConfig(scope: scope, config: .ws(McpWebSocketServerConfig(
                url: value["url"]?.stringValue ?? "",
                headers: value["headers"]?.objectValue?
                    .reduce(into: [String: String]()) { dict, kv in
                        if let s = kv.value.stringValue { dict[kv.key] = s }
                    } ?? [:],
                headersHelper: value["headersHelper"]?.stringValue
            )))
        case "sdk":
            return ScopedMcpServerConfig(scope: scope, config: .sdk(McpSdkServerConfig(
                name: value["name"]?.stringValue ?? name
            )))
        case "managed-proxy":
            return ScopedMcpServerConfig(scope: scope, config: .managedProxy(McpManagedProxyServerConfig(
                url: value["url"]?.stringValue ?? "",
                id: value["id"]?.stringValue ?? ""
            )))
        default:
            return nil
        }
    }

    static func checkUnsupportedFormat(path: String) throws {
        if path.hasSuffix(".toml") {
            throw ConfigError.parse("TOML config is not supported (found \(path))")
        }
    }

    // MARK: - Validation diagnostics

    public struct ConfigDiagnostic: Sendable, Equatable {
        public var path: String
        public var field: String
        public var line: Int?
        public var kind: DiagnosticKind

        public enum DiagnosticKind: Sendable, Equatable {
            case unknownKey(suggestion: String?)
            case wrongType(expected: String, got: String)
            case deprecated(replacement: String)
        }
    }

    public struct ConfigValidationResult: Sendable, Equatable {
        public var errors: [ConfigDiagnostic] = []
        public var warnings: [ConfigDiagnostic] = []
        public var isOk: Bool { errors.isEmpty }
    }

    public static func simpleEditDistance(_ a: String, _ b: String) -> Int {
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

    public static func suggestField(_ field: String, candidates: [String]) -> String? {
        var best: (String, Int)?
        for c in candidates {
            let d = simpleEditDistance(field.lowercased(), c.lowercased())
            if best == nil || d < best!.1 { best = (c, d) }
        }
        return best.flatMap { $0.1 <= 3 ? $0.0 : nil }
    }
}
