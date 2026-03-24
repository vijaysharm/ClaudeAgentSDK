import Foundation

/// State of a bridge session as reported to the server.
public enum BridgeSessionState: String, Codable, Sendable {
    case idle
    case running
    case requiresAction = "requires_action"
}

/// Options for attaching to a bridge session.
///
/// The bridge API connects to a remote Claude Code instance via SSE transport
/// with JWT authentication, instead of spawning a local process.
public struct BridgeSessionOptions: Sendable {
    /// Session ID (typically in `cse_*` form).
    public let sessionId: String

    /// Worker JWT for authentication.
    public let ingressToken: String

    /// Base URL for the session ingress API.
    public let apiBaseUrl: String

    /// Worker epoch (omit to register automatically).
    public var epoch: Int?

    /// SSE sequence number high-water mark for resumable streams.
    public var initialSequenceNum: Int?

    /// Heartbeat interval in milliseconds (default: 20000).
    public var heartbeatIntervalMs: Int?

    /// Called when a user message arrives from the remote side.
    public var onInboundMessage: (@Sendable (SDKMessage) async -> Void)?

    /// Called when a permission response arrives.
    public var onPermissionResponse: (@Sendable (AnyCodable) -> Void)?

    /// Called when an interrupt is received.
    public var onInterrupt: (@Sendable () -> Void)?

    /// Called when the model is changed remotely.
    public var onSetModel: (@Sendable (String?) -> Void)?

    /// Called when the permission mode is changed remotely.
    public var onSetPermissionMode: (@Sendable (PermissionMode) -> BridgePermissionModeResult)?

    /// Called when the transport closes permanently.
    public var onClose: (@Sendable (Int?) -> Void)?

    public init(
        sessionId: String,
        ingressToken: String,
        apiBaseUrl: String,
        epoch: Int? = nil,
        initialSequenceNum: Int? = nil,
        heartbeatIntervalMs: Int? = nil,
        onInboundMessage: (@Sendable (SDKMessage) async -> Void)? = nil,
        onPermissionResponse: (@Sendable (AnyCodable) -> Void)? = nil,
        onInterrupt: (@Sendable () -> Void)? = nil,
        onSetModel: (@Sendable (String?) -> Void)? = nil,
        onSetPermissionMode: (@Sendable (PermissionMode) -> BridgePermissionModeResult)? = nil,
        onClose: (@Sendable (Int?) -> Void)? = nil
    ) {
        self.sessionId = sessionId
        self.ingressToken = ingressToken
        self.apiBaseUrl = apiBaseUrl
        self.epoch = epoch
        self.initialSequenceNum = initialSequenceNum
        self.heartbeatIntervalMs = heartbeatIntervalMs
        self.onInboundMessage = onInboundMessage
        self.onPermissionResponse = onPermissionResponse
        self.onInterrupt = onInterrupt
        self.onSetModel = onSetModel
        self.onSetPermissionMode = onSetPermissionMode
        self.onClose = onClose
    }
}

/// Result of a permission mode change request.
public enum BridgePermissionModeResult: Sendable {
    case ok
    case error(String)
}
