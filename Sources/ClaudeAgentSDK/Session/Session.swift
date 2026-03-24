import Foundation

/// A multi-turn conversation session with Claude.
///
/// Sessions maintain a persistent connection to the Claude Code CLI,
/// allowing multiple send/stream cycles within a single conversation.
///
/// ```swift
/// let session = try ClaudeAgentSDK.createSession(
///     options: SessionOptions(model: "claude-sonnet-4-6")
/// )
///
/// try await session.send("What is 2 + 2?")
/// for try await message in session.stream() {
///     if case .result(.success(let r)) = message {
///         print(r.result) // "4"
///     }
/// }
///
/// try await session.send("Multiply that by 10")
/// for try await message in session.stream() {
///     if case .result(.success(let r)) = message {
///         print(r.result) // "40"
///     }
/// }
///
/// session.close()
/// ```
///
/// - Note: Only available on macOS. On iOS, session creation throws
///   ``ClaudeAgentSDKError/unsupportedPlatform``.
public final class Session: @unchecked Sendable {
    /// The session ID.
    ///
    /// For new sessions, this is a pre-generated UUID passed via `--session-id`.
    /// For resumed sessions, this is the provided session ID.
    public let sessionId: String

    private let query: Query
    private let lock = NSLock()
    private var iterator: Query.AsyncIterator

    init(sessionId: String, query: Query) {
        self.sessionId = sessionId
        self.query = query
        self.iterator = query.makeAsyncIterator()
    }

    /// Send a text message to the session.
    public func send(_ text: String) async throws {
        try await query.sendMessage(text)
    }

    /// Send a structured user message to the session.
    public func send(_ message: SDKUserMessage) async throws {
        try await query.sendMessage(message)
    }

    /// Stream messages from the session.
    ///
    /// Returns an `AsyncThrowingStream` that yields ``SDKMessage`` values
    /// from the current point in the conversation. The stream completes
    /// when the underlying process finishes or the session is closed.
    ///
    /// Call `send()` followed by `stream()` for each conversation turn.
    ///
    /// - Important: Only one `stream()` should be active at a time.
    public func stream() -> AsyncThrowingStream<SDKMessage, any Error> {
        // Reset turn-complete flag for the new turn
        lock.withLock { _turnComplete = false }

        return AsyncThrowingStream { [self] in
            // If we already yielded a result, this turn is done
            let complete = self.lock.withLock { self._turnComplete }
            if complete { return nil }

            guard let message = try await self.iterator.next() else {
                return nil
            }

            // A result message marks the end of the current turn.
            if case .result = message {
                self.lock.withLock { self._turnComplete = true }
            }

            return message
        }
    }

    private var _turnComplete = false

    /// Close the session and terminate the underlying process.
    public func close() {
        query.close()
    }
}
