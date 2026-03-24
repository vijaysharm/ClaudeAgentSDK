import Foundation

#if os(macOS)

/// Errors from the process transport.
public enum ProcessTransportError: Error, Sendable {
    case processNotRunning
    case executableNotFound(String)
    case processExitedWithError(code: Int32)
    case writeError(any Error)
}

/// Transport implementation using `Foundation.Process` to spawn and communicate
/// with the Claude Code CLI.
///
/// Available on macOS only. On iOS, use types directly — process spawning is not supported.
final class ProcessTransport: Transport, @unchecked Sendable {
    private let process: Process
    private let stdinPipe: Pipe
    private let stdoutPipe: Pipe
    private let stderrPipe: Pipe
    private let lock = NSLock()
    private var _isClosed = false
    private let stderrHandler: (@Sendable (String) -> Void)?

    // Eagerly created stream — readabilityHandler is set at init time
    // so no stdout data is lost before the consumer starts iterating.
    private let _messageStream: AsyncThrowingStream<StdoutMessage, any Error>

    init(
        executablePath: String,
        arguments: [String],
        cwd: String?,
        environment: [String: String]?,
        stderrHandler: (@Sendable (String) -> Void)? = nil
    ) throws {
        guard FileManager.default.fileExists(atPath: executablePath) else {
            throw ProcessTransportError.executableNotFound(executablePath)
        }

        self.stderrHandler = stderrHandler
        self.stdinPipe = Pipe()
        self.stdoutPipe = Pipe()
        self.stderrPipe = Pipe()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        if let cwd {
            process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }

        if let environment {
            process.environment = environment
        }

        self.process = process

        // Set up stderr reading
        if let handler = stderrHandler {
            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                if let str = String(data: data, encoding: .utf8) {
                    handler(str)
                }
            }
        }

        // Set up stdout reading EAGERLY — before process.run() — so no data is lost
        let stdoutHandle = stdoutPipe.fileHandleForReading
        self._messageStream = AsyncThrowingStream { continuation in
            let lineBuffer = LineBuffer()

            stdoutHandle.readabilityHandler = { fileHandle in
                let data = fileHandle.availableData

                if data.isEmpty {
                    // EOF
                    stdoutHandle.readabilityHandler = nil
                    if let lastLine = lineBuffer.flush() {
                        if let message = try? JSONLineParser.parse(lastLine) {
                            continuation.yield(message)
                        }
                    }
                    continuation.finish()
                    return
                }

                guard let chunk = String(data: data, encoding: .utf8) else { return }

                let lines = lineBuffer.append(chunk)
                for line in lines {
                    do {
                        if let message = try JSONLineParser.parse(line) {
                            continuation.yield(message)
                        }
                    } catch {
                        continuation.finish(throwing: error)
                        stdoutHandle.readabilityHandler = nil
                        return
                    }
                }
            }

            continuation.onTermination = { _ in
                stdoutHandle.readabilityHandler = nil
            }
        }

        try process.run()
    }

    func write(_ data: String) async throws {
        let isClosed = lock.withLock { _isClosed }
        guard !isClosed else {
            throw ProcessTransportError.processNotRunning
        }

        guard let data = data.data(using: .utf8) else { return }
        stdinPipe.fileHandleForWriting.write(data)
    }

    func close() {
        let alreadyClosed = lock.withLock {
            let was = _isClosed
            _isClosed = true
            return was
        }
        guard !alreadyClosed else { return }

        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        if process.isRunning {
            process.terminate()
        }
    }

    func isReady() -> Bool {
        let isClosed = lock.withLock { _isClosed }
        return !isClosed && process.isRunning
    }

    func readMessages() -> AsyncThrowingStream<StdoutMessage, any Error> {
        _messageStream
    }

    func endInput() {
        stdinPipe.fileHandleForWriting.closeFile()
    }
}

/// Thread-safe line buffer that accumulates partial lines across chunks.
private final class LineBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var leftover = ""

    func append(_ chunk: String) -> [String] {
        lock.lock()
        defer { lock.unlock() }

        let combined = leftover + chunk
        let parts = combined.split(separator: "\n", omittingEmptySubsequences: false)

        if combined.hasSuffix("\n") {
            leftover = ""
            return parts.map(String.init)
        } else {
            leftover = String(parts.last ?? "")
            return parts.dropLast().map(String.init)
        }
    }

    func flush() -> String? {
        lock.lock()
        defer { lock.unlock() }
        let remaining = leftover
        leftover = ""
        return remaining.isEmpty ? nil : remaining
    }
}

#endif
