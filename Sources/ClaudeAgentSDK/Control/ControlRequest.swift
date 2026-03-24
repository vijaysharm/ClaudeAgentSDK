import Foundation

/// A control request from the CLI process.
struct SDKControlRequest: Codable, Sendable {
    let type: String
    let requestId: String
    let request: SDKControlRequestInner
}

/// Inner control request payload — only the subtypes we handle.
struct SDKControlRequestInner: Codable, Sendable {
    let subtype: String
    let toolName: String?
    let input: [String: AnyCodable]?
    let permissionSuggestions: [PermissionUpdate]?
    let blockedPath: String?
    let decisionReason: String?
    let title: String?
    let displayName: String?
    let toolUseId: String?
    let agentId: String?
    let description: String?
}
