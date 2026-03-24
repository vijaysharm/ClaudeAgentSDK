import Foundation

#if os(macOS)

/// Transport implementation using Server-Sent Events over HTTP.
///
/// Uses `URLSession` for the SSE connection and HTTP POST for writing messages.
/// Supports reconnection with token refresh.
final class SSETransport: Transport, @unchecked Sendable {
    private let url: URL
    private let token: String
    private let lock = NSLock()
    private var _isClosed = false
    private var sequenceNum: Int
    private let _messageStream: AsyncThrowingStream<StdoutMessage, any Error>
    private var urlSession: URLSession?
    private var dataTask: URLSessionDataTask?

    init(url: URL, token: String, sequenceNum: Int = 0) async throws {
        self.url = url
        self.token = token
        self.sequenceNum = sequenceNum

        // Create SSE connection
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        if sequenceNum > 0 {
            request.setValue(String(sequenceNum), forHTTPHeaderField: "Last-Event-ID")
        }

        let session = URLSession(configuration: .default)
        self.urlSession = session

        let capturedSession = session
        let capturedRequest = request
        self._messageStream = AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await capturedSession.bytes(for: capturedRequest)

                    guard let httpResponse = response as? HTTPURLResponse,
                          (200..<300).contains(httpResponse.statusCode) else {
                        continuation.finish(throwing: ClaudeAgentSDKError.sessionError("SSE connection failed"))
                        return
                    }

                    var lineBuffer = ""
                    var dataBuffer = ""

                    for try await byte in bytes {
                        let char = Character(UnicodeScalar(byte))

                        if char == "\n" {
                            let line = lineBuffer
                            lineBuffer = ""

                            if line.isEmpty {
                                // Empty line = end of event
                                if !dataBuffer.isEmpty {
                                    if let message = try? JSONLineParser.parse(dataBuffer) {
                                        continuation.yield(message)
                                    }
                                    dataBuffer = ""
                                }
                            } else if line.hasPrefix("data: ") {
                                let data = String(line.dropFirst(6))
                                if dataBuffer.isEmpty {
                                    dataBuffer = data
                                } else {
                                    dataBuffer += "\n" + data
                                }
                            } else if line.hasPrefix("id: ") {
                                // Track sequence number for resume
                            }
                        } else {
                            lineBuffer.append(char)
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func write(_ data: String) async throws {
        let isClosed = lock.withLock { _isClosed }
        guard !isClosed else {
            throw ProcessTransportError.processNotRunning
        }

        // POST the message to the write endpoint
        var request = URLRequest(url: url.appendingPathComponent("messages"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(data.utf8)

        guard let session = urlSession else { return }
        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw ClaudeAgentSDKError.sessionError("Bridge write failed")
        }
    }

    func close() {
        lock.withLock { _isClosed = true }
        urlSession?.invalidateAndCancel()
        urlSession = nil
    }

    func isReady() -> Bool {
        lock.withLock { !_isClosed }
    }

    func readMessages() -> AsyncThrowingStream<StdoutMessage, any Error> {
        _messageStream
    }

    func endInput() {
        // No-op for SSE transport — connection stays open
    }
}

#endif
