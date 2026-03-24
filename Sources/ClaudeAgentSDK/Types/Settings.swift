import Foundation

/// Permission settings for tool usage.
public struct PermissionSettings: Codable, Sendable {
    public var allow: [String]?
    public var deny: [String]?
    public var ask: [String]?
    public var defaultMode: PermissionMode?
    public var disableBypassPermissionsMode: String?
    public var additionalDirectories: [String]?

    public init(
        allow: [String]? = nil,
        deny: [String]? = nil,
        ask: [String]? = nil,
        defaultMode: PermissionMode? = nil,
        disableBypassPermissionsMode: String? = nil,
        additionalDirectories: [String]? = nil
    ) {
        self.allow = allow
        self.deny = deny
        self.ask = ask
        self.defaultMode = defaultMode
        self.disableBypassPermissionsMode = disableBypassPermissionsMode
        self.additionalDirectories = additionalDirectories
    }
}

/// Attribution text for commits and PRs.
public struct AttributionSettings: Codable, Sendable {
    public var commit: String?
    public var pr: String?

    public init(commit: String? = nil, pr: String? = nil) {
        self.commit = commit
        self.pr = pr
    }
}

/// Worktree configuration.
public struct WorktreeSettings: Codable, Sendable {
    public var symlinkDirectories: [String]?
    public var sparsePaths: [String]?

    public init(symlinkDirectories: [String]? = nil, sparsePaths: [String]? = nil) {
        self.symlinkDirectories = symlinkDirectories
        self.sparsePaths = sparsePaths
    }
}

/// Status line configuration.
public struct StatusLineSettings: Codable, Sendable {
    public var type: String?
    public var command: String?
    public var padding: Int?

    public init(type: String? = nil, command: String? = nil, padding: Int? = nil) {
        self.type = type
        self.command = command
        self.padding = padding
    }
}

/// File suggestion configuration.
public struct FileSuggestionSettings: Codable, Sendable {
    public var type: String?
    public var command: String?

    public init(type: String? = nil, command: String? = nil) {
        self.type = type
        self.command = command
    }
}

/// Complete settings type for the Claude Code CLI.
///
/// Covers the most important sections of the TypeScript SDK's `Settings` interface
/// with strongly-typed fields. Less commonly used sections (plugins, marketplaces,
/// advanced enterprise controls) can be passed via ``additionalSettings``.
///
/// ```swift
/// let settings = Settings(
///     permissions: PermissionSettings(allow: ["Read", "Glob"]),
///     model: "claude-sonnet-4-6"
/// )
/// ```
public struct Settings: Sendable {
    // MARK: - Authentication

    public var apiKeyHelper: String?
    public var awsCredentialExport: String?
    public var awsAuthRefresh: String?
    public var gcpAuthRefresh: String?

    // MARK: - File Management

    public var fileSuggestion: FileSuggestionSettings?
    public var respectGitignore: Bool?
    public var cleanupPeriodDays: Int?

    // MARK: - Attribution & Git

    public var attribution: AttributionSettings?
    public var includeCoAuthoredBy: Bool?
    public var includeGitInstructions: Bool?

    // MARK: - Permissions

    public var permissions: PermissionSettings?

    // MARK: - Model Configuration

    public var model: String?
    public var availableModels: [String]?
    public var modelOverrides: [String: String]?

    // MARK: - Environment

    public var env: [String: String]?

    // MARK: - MCP Server Management

    public var enableAllProjectMcpServers: Bool?
    public var enabledMcpjsonServers: [String]?
    public var disabledMcpjsonServers: [String]?

    // MARK: - Worktrees

    public var worktree: WorktreeSettings?

    // MARK: - Advanced Controls

    public var disableAllHooks: Bool?
    public var defaultShell: String?
    public var allowManagedHooksOnly: Bool?
    public var allowManagedPermissionRulesOnly: Bool?
    public var allowManagedMcpServersOnly: Bool?
    public var statusLine: StatusLineSettings?

    // MARK: - Escape Hatch

    /// Additional settings not covered by the typed fields above.
    ///
    /// Use this for plugins, marketplaces, enterprise controls, or any
    /// other settings that don't have dedicated properties. Keys are merged
    /// at the top level during encoding.
    public var additionalSettings: [String: AnyCodable]?

    public init(
        apiKeyHelper: String? = nil,
        awsCredentialExport: String? = nil,
        awsAuthRefresh: String? = nil,
        gcpAuthRefresh: String? = nil,
        fileSuggestion: FileSuggestionSettings? = nil,
        respectGitignore: Bool? = nil,
        cleanupPeriodDays: Int? = nil,
        attribution: AttributionSettings? = nil,
        includeCoAuthoredBy: Bool? = nil,
        includeGitInstructions: Bool? = nil,
        permissions: PermissionSettings? = nil,
        model: String? = nil,
        availableModels: [String]? = nil,
        modelOverrides: [String: String]? = nil,
        env: [String: String]? = nil,
        enableAllProjectMcpServers: Bool? = nil,
        enabledMcpjsonServers: [String]? = nil,
        disabledMcpjsonServers: [String]? = nil,
        worktree: WorktreeSettings? = nil,
        disableAllHooks: Bool? = nil,
        defaultShell: String? = nil,
        allowManagedHooksOnly: Bool? = nil,
        allowManagedPermissionRulesOnly: Bool? = nil,
        allowManagedMcpServersOnly: Bool? = nil,
        statusLine: StatusLineSettings? = nil,
        additionalSettings: [String: AnyCodable]? = nil
    ) {
        self.apiKeyHelper = apiKeyHelper
        self.awsCredentialExport = awsCredentialExport
        self.awsAuthRefresh = awsAuthRefresh
        self.gcpAuthRefresh = gcpAuthRefresh
        self.fileSuggestion = fileSuggestion
        self.respectGitignore = respectGitignore
        self.cleanupPeriodDays = cleanupPeriodDays
        self.attribution = attribution
        self.includeCoAuthoredBy = includeCoAuthoredBy
        self.includeGitInstructions = includeGitInstructions
        self.permissions = permissions
        self.model = model
        self.availableModels = availableModels
        self.modelOverrides = modelOverrides
        self.env = env
        self.enableAllProjectMcpServers = enableAllProjectMcpServers
        self.enabledMcpjsonServers = enabledMcpjsonServers
        self.disabledMcpjsonServers = disabledMcpjsonServers
        self.worktree = worktree
        self.disableAllHooks = disableAllHooks
        self.defaultShell = defaultShell
        self.allowManagedHooksOnly = allowManagedHooksOnly
        self.allowManagedPermissionRulesOnly = allowManagedPermissionRulesOnly
        self.allowManagedMcpServersOnly = allowManagedMcpServersOnly
        self.statusLine = statusLine
        self.additionalSettings = additionalSettings
    }
}

// MARK: - Codable (merges additionalSettings at top level)

extension Settings: Codable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case apiKeyHelper, awsCredentialExport, awsAuthRefresh, gcpAuthRefresh
        case fileSuggestion, respectGitignore, cleanupPeriodDays
        case attribution, includeCoAuthoredBy, includeGitInstructions
        case permissions
        case model, availableModels, modelOverrides
        case env
        case enableAllProjectMcpServers, enabledMcpjsonServers, disabledMcpjsonServers
        case worktree
        case disableAllHooks, defaultShell, allowManagedHooksOnly
        case allowManagedPermissionRulesOnly, allowManagedMcpServersOnly
        case statusLine
    }

    private struct DynamicKey: CodingKey {
        var stringValue: String
        var intValue: Int?
        init(stringValue: String) { self.stringValue = stringValue; self.intValue = nil }
        init?(intValue: Int) { return nil }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicKey.self)

        // Decode known fields using a standard keyed container
        let known = try decoder.container(keyedBy: CodingKeys.self)
        apiKeyHelper = try known.decodeIfPresent(String.self, forKey: .apiKeyHelper)
        awsCredentialExport = try known.decodeIfPresent(String.self, forKey: .awsCredentialExport)
        awsAuthRefresh = try known.decodeIfPresent(String.self, forKey: .awsAuthRefresh)
        gcpAuthRefresh = try known.decodeIfPresent(String.self, forKey: .gcpAuthRefresh)
        fileSuggestion = try known.decodeIfPresent(FileSuggestionSettings.self, forKey: .fileSuggestion)
        respectGitignore = try known.decodeIfPresent(Bool.self, forKey: .respectGitignore)
        cleanupPeriodDays = try known.decodeIfPresent(Int.self, forKey: .cleanupPeriodDays)
        attribution = try known.decodeIfPresent(AttributionSettings.self, forKey: .attribution)
        includeCoAuthoredBy = try known.decodeIfPresent(Bool.self, forKey: .includeCoAuthoredBy)
        includeGitInstructions = try known.decodeIfPresent(Bool.self, forKey: .includeGitInstructions)
        permissions = try known.decodeIfPresent(PermissionSettings.self, forKey: .permissions)
        model = try known.decodeIfPresent(String.self, forKey: .model)
        availableModels = try known.decodeIfPresent([String].self, forKey: .availableModels)
        modelOverrides = try known.decodeIfPresent([String: String].self, forKey: .modelOverrides)
        env = try known.decodeIfPresent([String: String].self, forKey: .env)
        enableAllProjectMcpServers = try known.decodeIfPresent(Bool.self, forKey: .enableAllProjectMcpServers)
        enabledMcpjsonServers = try known.decodeIfPresent([String].self, forKey: .enabledMcpjsonServers)
        disabledMcpjsonServers = try known.decodeIfPresent([String].self, forKey: .disabledMcpjsonServers)
        worktree = try known.decodeIfPresent(WorktreeSettings.self, forKey: .worktree)
        disableAllHooks = try known.decodeIfPresent(Bool.self, forKey: .disableAllHooks)
        defaultShell = try known.decodeIfPresent(String.self, forKey: .defaultShell)
        allowManagedHooksOnly = try known.decodeIfPresent(Bool.self, forKey: .allowManagedHooksOnly)
        allowManagedPermissionRulesOnly = try known.decodeIfPresent(Bool.self, forKey: .allowManagedPermissionRulesOnly)
        allowManagedMcpServersOnly = try known.decodeIfPresent(Bool.self, forKey: .allowManagedMcpServersOnly)
        statusLine = try known.decodeIfPresent(StatusLineSettings.self, forKey: .statusLine)

        // Collect unknown keys into additionalSettings
        let knownKeySet = Set(CodingKeys.allCases.map(\.rawValue))
        var additional: [String: AnyCodable] = [:]
        for key in container.allKeys {
            if !knownKeySet.contains(key.stringValue) {
                additional[key.stringValue] = try container.decode(AnyCodable.self, forKey: key)
            }
        }
        additionalSettings = additional.isEmpty ? nil : additional
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encodeIfPresent(apiKeyHelper, forKey: .apiKeyHelper)
        try container.encodeIfPresent(awsCredentialExport, forKey: .awsCredentialExport)
        try container.encodeIfPresent(awsAuthRefresh, forKey: .awsAuthRefresh)
        try container.encodeIfPresent(gcpAuthRefresh, forKey: .gcpAuthRefresh)
        try container.encodeIfPresent(fileSuggestion, forKey: .fileSuggestion)
        try container.encodeIfPresent(respectGitignore, forKey: .respectGitignore)
        try container.encodeIfPresent(cleanupPeriodDays, forKey: .cleanupPeriodDays)
        try container.encodeIfPresent(attribution, forKey: .attribution)
        try container.encodeIfPresent(includeCoAuthoredBy, forKey: .includeCoAuthoredBy)
        try container.encodeIfPresent(includeGitInstructions, forKey: .includeGitInstructions)
        try container.encodeIfPresent(permissions, forKey: .permissions)
        try container.encodeIfPresent(model, forKey: .model)
        try container.encodeIfPresent(availableModels, forKey: .availableModels)
        try container.encodeIfPresent(modelOverrides, forKey: .modelOverrides)
        try container.encodeIfPresent(env, forKey: .env)
        try container.encodeIfPresent(enableAllProjectMcpServers, forKey: .enableAllProjectMcpServers)
        try container.encodeIfPresent(enabledMcpjsonServers, forKey: .enabledMcpjsonServers)
        try container.encodeIfPresent(disabledMcpjsonServers, forKey: .disabledMcpjsonServers)
        try container.encodeIfPresent(worktree, forKey: .worktree)
        try container.encodeIfPresent(disableAllHooks, forKey: .disableAllHooks)
        try container.encodeIfPresent(defaultShell, forKey: .defaultShell)
        try container.encodeIfPresent(allowManagedHooksOnly, forKey: .allowManagedHooksOnly)
        try container.encodeIfPresent(allowManagedPermissionRulesOnly, forKey: .allowManagedPermissionRulesOnly)
        try container.encodeIfPresent(allowManagedMcpServersOnly, forKey: .allowManagedMcpServersOnly)
        try container.encodeIfPresent(statusLine, forKey: .statusLine)

        // Merge additional settings at the top level
        if let additional = additionalSettings {
            var dynamic = encoder.container(keyedBy: DynamicKey.self)
            for (key, value) in additional {
                try dynamic.encode(value, forKey: DynamicKey(stringValue: key))
            }
        }
    }
}
