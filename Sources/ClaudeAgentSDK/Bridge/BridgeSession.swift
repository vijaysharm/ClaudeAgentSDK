import Foundation

/// Handle to a bridge session connected via SSE transport.
///
/// The bridge API enables connecting to Claude Code running remotely
/// (e.g., claude.ai web) via Server-Sent Events instead of a local process.
///
/// ```swift
/// let handle = try await ClaudeAgentSDK.attachBridgeSession(
///     options: BridgeSessionOptions(
///         sessionId: "cse_abc123",
///         ingressToken: "jwt-token",
///         apiBaseUrl: "https://api.claude.ai"
///     )
/// )
///
/// handle.write(someMessage)
/// handle.reportState(.running)
/// // ...
/// handle.close()
/// ```
///
/// - Note: This API is marked as alpha stability. Breaking changes may occur
///   without a major version bump.
public final class BridgeSessionHandle: @unchecked Sendable {
    /// The session ID.
    public let sessionId: String

    let lock = NSLock()
    var _sequenceNum: Int
    var _isConnected: Bool = false
    private let options: BridgeSessionOptions

    #if os(macOS)
    var sseTransport: SSETransport?
    #endif

    init(options: BridgeSessionOptions) {
        self.sessionId = options.sessionId
        self._sequenceNum = options.initialSequenceNum ?? 0
        self.options = options
    }

    /// Current SSE sequence number high-water mark.
    public func getSequenceNum() -> Int {
        lock.withLock { _sequenceNum }
    }

    /// Whether the transport is currently connected.
    public func isConnected() -> Bool {
        lock.withLock { _isConnected }
    }

    /// Write a single SDKMessage to the session.
    public func write(_ msg: SDKMessage) throws {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(msg)
        guard let json = String(data: data, encoding: .utf8) else {
            throw ClaudeAgentSDKError.encodingError
        }
        #if os(macOS)
        Task {
            try? await sseTransport?.write(json)
        }
        #endif
    }

    /// Signal turn boundary — tells the remote side to stop the "working" spinner.
    public func sendResult() {
        // Implementation would send a result signal via the transport
    }

    /// Report session state to the server.
    public func reportState(_ state: BridgeSessionState) {
        // Implementation would PUT /worker state
    }

    /// Report external metadata (branch, directory).
    public func reportMetadata(_ metadata: [String: AnyCodable]) {
        // Implementation would PUT /worker external_metadata
    }

    /// Report delivery status for an event.
    public func reportDelivery(eventId: String, status: BridgeDeliveryStatus) {
        // Implementation would POST /worker/events/{id}/delivery
    }

    /// Drain the write queue.
    public func flush() async {
        // Wait for pending writes to complete
    }

    /// Reconnect the transport with a fresh JWT.
    ///
    /// Call when the poll loop re-dispatches work with a new token.
    public func reconnectTransport(
        ingressToken: String,
        apiBaseUrl: String,
        epoch: Int? = nil
    ) async throws {
        #if os(macOS)
        lock.withLock { _isConnected = false }
        // Reconnect with new credentials
        sseTransport = try await SSETransport(
            url: URL(string: apiBaseUrl)!,
            token: ingressToken,
            sequenceNum: getSequenceNum()
        )
        lock.withLock { _isConnected = true }
        #else
        throw ClaudeAgentSDKError.unsupportedPlatform
        #endif
    }

    /// Close the bridge session.
    public func close() {
        lock.withLock { _isConnected = false }
        #if os(macOS)
        sseTransport?.close()
        #endif
    }
}

/// Delivery status for bridge events.
public enum BridgeDeliveryStatus: String, Codable, Sendable {
    case processing
    case processed
}

// MARK: - Factory

extension ClaudeAgentSDK {
    /// Attach to a remote bridge session via SSE transport.
    ///
    /// Creates a connection to a remote Claude Code instance using
    /// Server-Sent Events with JWT authentication.
    ///
    /// - Parameter options: Bridge session configuration.
    /// - Returns: A handle to the bridge session.
    ///
    /// - Note: Alpha stability — breaking changes may occur without a major version bump.
    public static func attachBridgeSession(
        options: BridgeSessionOptions
    ) async throws -> BridgeSessionHandle {
        #if os(macOS)
        let handle = BridgeSessionHandle(options: options)

        // Create SSE transport
        let transport = try await SSETransport(
            url: URL(string: options.apiBaseUrl)!,
            token: options.ingressToken,
            sequenceNum: options.initialSequenceNum ?? 0
        )

        handle.lock.withLock {
            handle.sseTransport = transport
            handle._isConnected = true
        }

        // Start reading inbound messages in background
        if let onMessage = options.onInboundMessage {
            Task {
                for try await message in transport.readMessages() {
                    if case let .message(sdkMessage) = message {
                        await onMessage(sdkMessage)
                    }
                }
                options.onClose?(nil)
            }
        }

        return handle
        #else
        throw ClaudeAgentSDKError.unsupportedPlatform
        #endif
    }
}
