import Foundation

/// Parses newline-delimited JSON from the CLI stdout into ``StdoutMessage`` values.
enum JSONLineParser {
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    /// Parse a single JSON line into a ``StdoutMessage``.
    ///
    /// - Parameter line: A single line of JSON text from the CLI stdout.
    /// - Returns: The parsed message, or nil if the line is empty or whitespace.
    static func parse(_ line: String) throws -> StdoutMessage? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let data = Data(trimmed.utf8)

        // Peek at the "type" field to route decoding
        let typeInfo = try decoder.decode(TypePeek.self, from: data)

        switch typeInfo.type {
        case "control_request":
            let request = try decoder.decode(SDKControlRequest.self, from: data)
            return .controlRequest(request)

        case "control_response":
            let response = try decoder.decode(SDKControlResponseRaw.self, from: data)
            return .controlResponse(response)

        case "keep_alive":
            return .keepAlive

        default:
            let message = try decoder.decode(SDKMessage.self, from: data)
            return .message(message)
        }
    }

    private struct TypePeek: Decodable {
        let type: String
    }
}
