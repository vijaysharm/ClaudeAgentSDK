import Foundation
@testable import ClaudeAgentSDK

/// A push-based mock transport for testing streaming/session scenarios.
///
/// Unlike `MockTransport` which emits all messages at construction,
/// this transport allows tests to push messages over time via `emit()`.
final class StreamingMockTransport: Transport, @unchecked Sendable {
    private let lock = NSLock()
    private var _writtenData: [String] = []
    private var _isClosed = false
    private var _inputEnded = false

    private let continuation: AsyncThrowingStream<StdoutMessage, any Error>.Continuation
    private let _stream: AsyncThrowingStream<StdoutMessage, any Error>

    var writtenData: [String] {
        lock.withLock { _writtenData }
    }

    var isClosed: Bool {
        lock.withLock { _isClosed }
    }

    var inputEnded: Bool {
        lock.withLock { _inputEnded }
    }

    init() {
        var captured: AsyncThrowingStream<StdoutMessage, any Error>.Continuation!
        self._stream = AsyncThrowingStream { continuation in
            captured = continuation
        }
        self.continuation = captured
    }

    /// Push a message to the transport's output stream.
    func emit(_ message: StdoutMessage) {
        continuation.yield(message)
    }

    /// Finish the output stream (simulates process exit / EOF).
    func finish() {
        continuation.finish()
    }

    // MARK: - Transport

    func write(_ data: String) async throws {
        lock.withLock {
            _writtenData.append(data)
        }
    }

    func close() {
        lock.withLock { _isClosed = true }
        continuation.finish()
    }

    func isReady() -> Bool {
        lock.withLock { !_isClosed }
    }

    func readMessages() -> AsyncThrowingStream<StdoutMessage, any Error> {
        _stream
    }

    func endInput() {
        lock.withLock { _inputEnded = true }
    }
}
