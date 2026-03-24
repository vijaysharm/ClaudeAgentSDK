import Foundation

/// Permission mode for controlling how tool executions are handled.
public enum PermissionMode: String, Codable, Sendable {
    /// Standard behavior, prompts for dangerous operations.
    case `default` = "default"
    /// Auto-accept file edit operations.
    case acceptEdits = "acceptEdits"
    /// Bypass all permission checks (requires `allowDangerouslySkipPermissions`).
    case bypassPermissions = "bypassPermissions"
    /// Planning mode, no actual tool execution.
    case plan = "plan"
    /// Don't prompt for permissions, deny if not pre-approved.
    case dontAsk = "dontAsk"
    /// Auto mode.
    case auto = "auto"
}

/// Permission behavior for rules.
public enum PermissionBehavior: String, Codable, Sendable {
    case allow
    case deny
    case ask
}

/// Result of a permission check.
public enum PermissionResult: Sendable {
    case allow(
        updatedInput: [String: AnyCodable]? = nil,
        updatedPermissions: [PermissionUpdate]? = nil
    )
    case deny(message: String, interrupt: Bool = false)
}

/// A permission rule value.
public struct PermissionRuleValue: Codable, Sendable {
    public let toolName: String
    public let ruleContent: String?

    public init(toolName: String, ruleContent: String? = nil) {
        self.toolName = toolName
        self.ruleContent = ruleContent
    }
}

/// Destination for permission updates.
public enum PermissionUpdateDestination: String, Codable, Sendable {
    case userSettings
    case projectSettings
    case localSettings
    case session
    case cliArg
}

/// A permission update operation.
public enum PermissionUpdate: Codable, Sendable {
    case addRules(rules: [PermissionRuleValue], behavior: PermissionBehavior, destination: PermissionUpdateDestination)
    case replaceRules(rules: [PermissionRuleValue], behavior: PermissionBehavior, destination: PermissionUpdateDestination)
    case removeRules(rules: [PermissionRuleValue], behavior: PermissionBehavior, destination: PermissionUpdateDestination)
    case setMode(mode: PermissionMode, destination: PermissionUpdateDestination)
    case addDirectories(directories: [String], destination: PermissionUpdateDestination)
    case removeDirectories(directories: [String], destination: PermissionUpdateDestination)

    private enum CodingKeys: String, CodingKey {
        case type, rules, behavior, destination, mode, directories
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "addRules":
            self = .addRules(
                rules: try container.decode([PermissionRuleValue].self, forKey: .rules),
                behavior: try container.decode(PermissionBehavior.self, forKey: .behavior),
                destination: try container.decode(PermissionUpdateDestination.self, forKey: .destination)
            )
        case "replaceRules":
            self = .replaceRules(
                rules: try container.decode([PermissionRuleValue].self, forKey: .rules),
                behavior: try container.decode(PermissionBehavior.self, forKey: .behavior),
                destination: try container.decode(PermissionUpdateDestination.self, forKey: .destination)
            )
        case "removeRules":
            self = .removeRules(
                rules: try container.decode([PermissionRuleValue].self, forKey: .rules),
                behavior: try container.decode(PermissionBehavior.self, forKey: .behavior),
                destination: try container.decode(PermissionUpdateDestination.self, forKey: .destination)
            )
        case "setMode":
            self = .setMode(
                mode: try container.decode(PermissionMode.self, forKey: .mode),
                destination: try container.decode(PermissionUpdateDestination.self, forKey: .destination)
            )
        case "addDirectories":
            self = .addDirectories(
                directories: try container.decode([String].self, forKey: .directories),
                destination: try container.decode(PermissionUpdateDestination.self, forKey: .destination)
            )
        case "removeDirectories":
            self = .removeDirectories(
                directories: try container.decode([String].self, forKey: .directories),
                destination: try container.decode(PermissionUpdateDestination.self, forKey: .destination)
            )
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: container,
                debugDescription: "Unknown PermissionUpdate type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .addRules(let rules, let behavior, let destination):
            try container.encode("addRules", forKey: .type)
            try container.encode(rules, forKey: .rules)
            try container.encode(behavior, forKey: .behavior)
            try container.encode(destination, forKey: .destination)
        case .replaceRules(let rules, let behavior, let destination):
            try container.encode("replaceRules", forKey: .type)
            try container.encode(rules, forKey: .rules)
            try container.encode(behavior, forKey: .behavior)
            try container.encode(destination, forKey: .destination)
        case .removeRules(let rules, let behavior, let destination):
            try container.encode("removeRules", forKey: .type)
            try container.encode(rules, forKey: .rules)
            try container.encode(behavior, forKey: .behavior)
            try container.encode(destination, forKey: .destination)
        case .setMode(let mode, let destination):
            try container.encode("setMode", forKey: .type)
            try container.encode(mode, forKey: .mode)
            try container.encode(destination, forKey: .destination)
        case .addDirectories(let directories, let destination):
            try container.encode("addDirectories", forKey: .type)
            try container.encode(directories, forKey: .directories)
            try container.encode(destination, forKey: .destination)
        case .removeDirectories(let directories, let destination):
            try container.encode("removeDirectories", forKey: .type)
            try container.encode(directories, forKey: .directories)
            try container.encode(destination, forKey: .destination)
        }
    }
}

/// Information about a tool use that was denied permission.
public struct SDKPermissionDenial: Codable, Sendable {
    public let toolName: String
    public let toolUseId: String
    public let toolInput: [String: AnyCodable]
}

/// Options passed to the `canUseTool` callback.
public struct CanUseToolOptions: Sendable {
    public let signal: CanUseToolSignal
    public let suggestions: [PermissionUpdate]?
    public let blockedPath: String?
    public let decisionReason: String?
    public let title: String?
    public let displayName: String?
    public let description: String?
    public let toolUseID: String
    public let agentID: String?
}

/// A simple signal type for cancellation in `CanUseTool` callbacks.
public final class CanUseToolSignal: Sendable {
    private let _isCancelled: ManagedAtomic<Bool>

    public var isCancelled: Bool { _isCancelled.value }

    init() {
        _isCancelled = ManagedAtomic(false)
    }

    func cancel() {
        _isCancelled.setValue(true)
    }
}

/// Thread-safe atomic wrapper for use in Sendable contexts.
internal final class ManagedAtomic<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Value

    var value: Value {
        lock.withLock { _value }
    }

    init(_ value: Value) {
        _value = value
    }

    func setValue(_ newValue: Value) {
        lock.withLock { _value = newValue }
    }
}

/// Permission callback function for controlling tool usage.
public typealias CanUseTool = @Sendable (
    _ toolName: String,
    _ input: [String: AnyCodable],
    _ options: CanUseToolOptions
) async throws -> PermissionResult
