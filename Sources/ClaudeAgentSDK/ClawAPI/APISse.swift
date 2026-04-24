import Foundation

extension ClawAPI {

    /// Byte-level SSE parser for Anthropic-flavored streams.
    ///
    /// Mirrors `api::sse::SseParser`:
    /// - Splits on `\n\n` or `\r\n\r\n` frame separators
    /// - Understands `event:`, `data:`, and `:` comment lines
    /// - Joins multiple `data:` lines with `\n`
    /// - Skips `event: ping` and `data: [DONE]`
    public final class SseParser: @unchecked Sendable {
        private let lock = NSLock()
        private var buffer: Data = Data()
        private let provider: String?
        private let model: String?

        public init(provider: String? = nil, model: String? = nil) {
            self.provider = provider
            self.model = model
        }

        /// Append a chunk of bytes and drain any complete frames.
        public func push(_ chunk: Data) throws -> [StreamEvent] {
            lock.lock()
            defer { lock.unlock() }
            buffer.append(chunk)
            var events: [StreamEvent] = []
            while let frame = drainFrame() {
                if let event = try Self.parseFrame(
                    frame, provider: provider, model: model
                ) {
                    events.append(event)
                }
            }
            return events
        }

        /// Drain any residual bytes as a final frame.
        public func finish() throws -> [StreamEvent] {
            lock.lock()
            defer { lock.unlock() }
            guard !buffer.isEmpty else { return [] }
            let text = String(decoding: buffer, as: UTF8.self)
            buffer.removeAll()
            if let event = try Self.parseFrame(text, provider: provider, model: model) {
                return [event]
            }
            return []
        }

        /// Convenience: push a UTF-8 string.
        public func push(_ chunk: String) throws -> [StreamEvent] {
            try push(Data(chunk.utf8))
        }

        private func drainFrame() -> String? {
            let doubleNewline = Data([0x0A, 0x0A])      // "\n\n"
            let crlfDouble = Data([0x0D, 0x0A, 0x0D, 0x0A]) // "\r\n\r\n"

            if let range = buffer.firstRange(of: doubleNewline) {
                let frame = buffer.subdata(in: 0..<range.lowerBound)
                buffer.removeSubrange(0..<range.upperBound)
                return String(decoding: frame, as: UTF8.self)
            }
            if let range = buffer.firstRange(of: crlfDouble) {
                let frame = buffer.subdata(in: 0..<range.lowerBound)
                buffer.removeSubrange(0..<range.upperBound)
                return String(decoding: frame, as: UTF8.self)
            }
            return nil
        }

        // MARK: - Frame parser

        /// Parse a single SSE frame without provider context.
        public static func parseFrame(_ frame: String) throws -> StreamEvent? {
            try parseFrame(frame, provider: nil, model: nil)
        }

        /// Parse a single SSE frame. Returns `nil` when the frame is a
        /// comment, ping, empty, or `[DONE]`.
        public static func parseFrame(
            _ frame: String, provider: String?, model: String?
        ) throws -> StreamEvent? {
            let trimmed = frame.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return nil }

            var eventName: String?
            var dataLines: [String] = []
            for rawLine in trimmed.split(
                omittingEmptySubsequences: false,
                whereSeparator: { $0 == "\n" || $0 == "\r" }
            ) {
                let line = String(rawLine)
                if line.isEmpty { continue }
                if line.hasPrefix(":") { continue }
                if let (field, value) = parseFieldLine(line) {
                    switch field {
                    case "event":
                        eventName = value.trimmingCharacters(in: .whitespaces)
                    case "data":
                        // trim_start only — leading single space is significant to SSE semantics
                        var s = value
                        while s.first == " " { s.removeFirst() }
                        dataLines.append(s)
                    default:
                        break
                    }
                }
            }

            if eventName == "ping" { return nil }
            guard !dataLines.isEmpty else { return nil }
            let payload = dataLines.joined(separator: "\n")
            if payload == "[DONE]" { return nil }

            guard let data = payload.data(using: .utf8) else { return nil }
            do {
                return try JSONDecoder().decode(StreamEvent.self, from: data)
            } catch {
                throw ApiError.jsonDeserialize(
                    provider: provider ?? "unknown",
                    model: model ?? "unknown",
                    body: payload,
                    detail: String(describing: error)
                )
            }
        }

        private static func parseFieldLine(_ line: String) -> (String, String)? {
            guard let colon = line.firstIndex(of: ":") else {
                // field without value
                return (line, "")
            }
            let field = String(line[..<colon])
            let valueStart = line.index(after: colon)
            return (field, String(line[valueStart...]))
        }
    }
}
