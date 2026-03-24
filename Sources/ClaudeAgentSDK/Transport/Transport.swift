import Foundation

/// Internal message type from stdout — either an SDKMessage or a control message.
enum StdoutMessage: Sendable {
    case message(SDKMessage)
    case controlRequest(SDKControlRequest)
    case controlResponse(SDKControlResponseRaw)
    case keepAlive
}

/// Raw control response from the CLI stdout.
struct SDKControlResponseRaw: Codable, Sendable {
    let type: String
    let response: ControlResponseInner

    struct ControlResponseInner: Codable, Sendable {
        let subtype: String
        let requestId: String
        let response: [String: AnyCodable]?
        let error: String?
    }
}

/// Transport protocol for communication with the Claude Code CLI.
protocol Transport: Sendable {
    /// Write data to the transport's stdin.
    func write(_ data: String) async throws

    /// Close the transport and terminate the process.
    func close()

    /// Whether the transport is ready for communication.
    func isReady() -> Bool

    /// Read and parse messages from the transport's stdout.
    func readMessages() -> AsyncThrowingStream<StdoutMessage, any Error>

    /// Close the input (stdin) side of the transport.
    func endInput()
}
