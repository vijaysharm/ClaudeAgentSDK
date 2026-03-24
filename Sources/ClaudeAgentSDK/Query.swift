import Foundation

/// Errors from the Claude Agent SDK.
public enum ClaudeAgentSDKError: Error, Sendable {
    /// The current platform does not support process spawning.
    case unsupportedPlatform
    /// The prompt must not be empty.
    case emptyPrompt
    /// The query has already been closed.
    case queryClosed
    /// A control request timed out.
    case controlRequestTimeout
    /// A control request returned an error.
    case controlRequestError(String)
    /// Failed to encode data for stdin.
    case encodingError
}

/// A running query against the Claude Code CLI.
///
/// `Query` conforms to `AsyncSequence`, yielding ``SDKMessage`` values as the CLI
/// produces them. It also provides control methods to interact with the running session.
///
/// ```swift
/// let q = ClaudeAgentSDK.query(prompt: "Hello", options: Options())
/// for try await message in q {
///     switch message {
///     case .result(let result):
///         print("Done: \(result)")
///     case .assistant(let msg):
///         print("Assistant: \(msg.message)")
///     default:
///         break
///     }
/// }
/// ```
public final class Query: @unchecked Sendable {
    private let transport: any Transport
    private let canUseToolCallback: CanUseTool?
    private let lock = NSLock()
    private var _isClosed = false
    private var pendingControlResponses: [String: CheckedContinuation<SDKControlResponseRaw, any Error>] = [:]
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()

    init(transport: any Transport, canUseTool: CanUseTool?) {
        self.transport = transport
        self.canUseToolCallback = canUseTool
    }

    // MARK: - Control Methods

    /// Interrupt the current query execution.
    public func interrupt() async throws {
        try await sendControlRequest(subtype: "interrupt")
    }

    /// Change the permission mode for the current session.
    public func setPermissionMode(_ mode: PermissionMode) async throws {
        try await sendControlRequest(subtype: "set_permission_mode", fields: [
            "mode": .string(mode.rawValue)
        ])
    }

    /// Change the model used for subsequent responses.
    public func setModel(_ model: String?) async throws {
        var fields: [String: AnyCodable] = [:]
        if let model {
            fields["model"] = .string(model)
        }
        try await sendControlRequest(subtype: "set_model", fields: fields)
    }

    /// Close the query and terminate the underlying process.
    public func close() {
        let alreadyClosed = lock.withLock {
            let was = _isClosed
            _isClosed = true
            return was
        }
        guard !alreadyClosed else { return }

        // Cancel all pending control requests
        let pending = lock.withLock {
            let p = pendingControlResponses
            pendingControlResponses.removeAll()
            return p
        }
        for (_, continuation) in pending {
            continuation.resume(throwing: ClaudeAgentSDKError.queryClosed)
        }

        transport.close()
    }

    // MARK: - Internal

    @discardableResult
    private func sendControlRequest(
        subtype: String,
        fields: [String: AnyCodable] = [:]
    ) async throws -> SDKControlResponseRaw {
        let isClosed = lock.withLock { _isClosed }
        guard !isClosed else { throw ClaudeAgentSDKError.queryClosed }

        let requestId = UUID().uuidString

        let request = SDKControlOutboundRequest(
            requestId: requestId,
            subtype: subtype,
            fields: fields
        )

        let data = try encoder.encode(request)
        guard let json = String(data: data, encoding: .utf8) else {
            throw ClaudeAgentSDKError.encodingError
        }

        // Register continuation before writing to avoid race
        let response = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<SDKControlResponseRaw, any Error>) in
            lock.withLock {
                pendingControlResponses[requestId] = continuation
            }

            Task {
                do {
                    try await transport.write(json + "\n")
                } catch {
                    let cont = lock.withLock {
                        pendingControlResponses.removeValue(forKey: requestId)
                    }
                    cont?.resume(throwing: error)
                }
            }
        }

        if response.response.subtype == "error", let error = response.response.error {
            throw ClaudeAgentSDKError.controlRequestError(error)
        }

        return response
    }

    /// Write a user message to the CLI's stdin.
    func writeUserMessage(_ message: SDKUserMessage) async throws {
        let data = try encoder.encode(message)
        guard var json = String(data: data, encoding: .utf8) else {
            throw ClaudeAgentSDKError.encodingError
        }
        json = "{\"type\":\"user\"," + json.dropFirst(1)
        try await transport.write(json + "\n")
    }

    /// Handle a permission request from the CLI.
    private func handlePermissionRequest(_ request: SDKControlRequest) async {
        guard request.request.subtype == "can_use_tool",
              let toolName = request.request.toolName,
              let input = request.request.input else {
            // Send error response for unhandled request types
            await sendControlResponse(requestId: request.requestId, error: "Unhandled control request")
            return
        }

        guard let callback = canUseToolCallback else {
            // No callback — deny by default
            await sendControlResponse(
                requestId: request.requestId,
                result: .deny(message: "No permission handler configured")
            )
            return
        }

        let signal = CanUseToolSignal()
        let options = CanUseToolOptions(
            signal: signal,
            suggestions: request.request.permissionSuggestions,
            blockedPath: request.request.blockedPath,
            decisionReason: request.request.decisionReason,
            title: request.request.title,
            displayName: request.request.displayName,
            description: request.request.description,
            toolUseID: request.request.toolUseId ?? "",
            agentID: request.request.agentId
        )

        do {
            let result = try await callback(toolName, input, options)
            await sendControlResponse(requestId: request.requestId, result: result)
        } catch {
            await sendControlResponse(
                requestId: request.requestId,
                result: .deny(message: "Permission handler error: \(error)")
            )
        }
    }

    private func sendControlResponse(requestId: String, result: PermissionResult) async {
        var responseFields: [String: AnyCodable] = [:]
        switch result {
        case .allow(let updatedInput, let updatedPermissions):
            responseFields["behavior"] = .string("allow")
            if let updatedInput {
                responseFields["updatedInput"] = .object(updatedInput)
            }
            if let updatedPermissions {
                let encoder = JSONEncoder()
                encoder.keyEncodingStrategy = .convertToSnakeCase
                if let data = try? encoder.encode(updatedPermissions),
                   let decoded = try? JSONDecoder().decode(AnyCodable.self, from: data) {
                    responseFields["updatedPermissions"] = decoded
                }
            }
        case .deny(let message, let interrupt):
            responseFields["behavior"] = .string("deny")
            responseFields["message"] = .string(message)
            if interrupt {
                responseFields["interrupt"] = .bool(true)
            }
        }

        let response = SDKControlResponse(
            requestId: requestId,
            response: responseFields
        )

        do {
            let data = try encoder.encode(response)
            if let json = String(data: data, encoding: .utf8) {
                try await transport.write(json + "\n")
            }
        } catch {
            // Best effort — if we can't write the response, the CLI will time out
        }
    }

    private func sendControlResponse(requestId: String, error: String) async {
        let response = SDKControlResponse(requestId: requestId, error: error)
        do {
            let data = try encoder.encode(response)
            if let json = String(data: data, encoding: .utf8) {
                try await transport.write(json + "\n")
            }
        } catch {
            // Best effort
        }
    }
}

// MARK: - AsyncSequence

extension Query: AsyncSequence {
    public typealias Element = SDKMessage

    public struct AsyncIterator: AsyncIteratorProtocol {
        private let query: Query
        private var innerIterator: AsyncThrowingStream<StdoutMessage, any Error>.AsyncIterator

        init(query: Query) {
            self.query = query
            self.innerIterator = query.transport.readMessages().makeAsyncIterator()
        }

        public mutating func next() async throws -> SDKMessage? {
            while true {
                guard let stdoutMessage = try await innerIterator.next() else {
                    return nil
                }

                switch stdoutMessage {
                case .message(let message):
                    return message

                case .controlRequest(let request):
                    // Handle permission requests asynchronously
                    await query.handlePermissionRequest(request)
                    continue

                case .controlResponse(let response):
                    // Route to pending control request
                    let continuation = query.lock.withLock {
                        query.pendingControlResponses.removeValue(forKey: response.response.requestId)
                    }
                    continuation?.resume(returning: response)
                    continue

                case .keepAlive:
                    continue
                }
            }
        }
    }

    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(query: self)
    }
}
