import Foundation
@testable import ClaudeAgentSDK

/// A mock transport for testing that emits pre-configured messages
/// and records data written to stdin.
final class MockTransport: Transport, @unchecked Sendable {
    private let lock = NSLock()
    private var _writtenData: [String] = []
    private let messagesToEmit: [StdoutMessage]
    private var _isClosed = false

    var writtenData: [String] {
        lock.withLock { _writtenData }
    }

    init(messages: [StdoutMessage] = []) {
        self.messagesToEmit = messages
    }

    func write(_ data: String) async throws {
        lock.withLock {
            _writtenData.append(data)
        }
    }

    func close() {
        lock.withLock { _isClosed = true }
    }

    func isReady() -> Bool {
        lock.withLock { !_isClosed }
    }

    func readMessages() -> AsyncThrowingStream<StdoutMessage, any Error> {
        let messages = messagesToEmit
        return AsyncThrowingStream { continuation in
            for message in messages {
                continuation.yield(message)
            }
            continuation.finish()
        }
    }

    func endInput() {}
}
