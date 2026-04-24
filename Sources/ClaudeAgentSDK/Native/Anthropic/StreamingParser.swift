import Foundation

/// Parses raw SSE (Server-Sent Events) lines into ``StreamEvent`` values.
struct SSEParser {

    /// Parse a single SSE event given its `event:` type line and `data:` line.
    static func parse(eventType: String, data: String) -> StreamEvent? {
        switch eventType {
        case "ping":
            return .ping

        case "message_start":
            guard let event = parseMessageStart(data) else { return nil }
            return .messageStart(event)

        case "content_block_start":
            guard let event = parseContentBlockStart(data) else { return nil }
            return .contentBlockStart(event)

        case "content_block_delta":
            guard let event = parseContentBlockDelta(data) else { return nil }
            return .contentBlockDelta(event)

        case "content_block_stop":
            guard let index = parseIndex(data) else { return nil }
            return .contentBlockStop(index: index)

        case "message_delta":
            guard let event = parseMessageDelta(data) else { return nil }
            return .messageDelta(event)

        case "message_stop":
            return .messageStop

        case "error":
            if let jsonData = data.data(using: .utf8),
               let err = try? JSONDecoder().decode(AnthropicAPIError.self, from: jsonData) {
                return .error(err)
            }
            return .error(AnthropicAPIError(type: "parse_error", error: nil))

        default:
            return nil
        }
    }

    // MARK: - Private parsers

    private static func parseMessageStart(_ data: String) -> MessageStartEvent? {
        guard let jsonData = data.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let message = root["message"] as? [String: Any] else { return nil }

        let id = message["id"] as? String ?? ""
        let model = message["model"] as? String ?? ""
        let usage = message["usage"] as? [String: Any]
        let inputTokens = usage?["input_tokens"] as? Int ?? 0
        return MessageStartEvent(id: id, model: model, inputTokens: inputTokens)
    }

    private static func parseContentBlockStart(_ data: String) -> ContentBlockStartEvent? {
        guard let jsonData = data.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let index = root["index"] as? Int,
              let block = root["content_block"] as? [String: Any],
              let type_ = block["type"] as? String else { return nil }

        let id = block["id"] as? String
        let name = block["name"] as? String
        return ContentBlockStartEvent(
            index: index,
            block: ContentBlockStartEvent.StartBlock(type: type_, id: id, name: name)
        )
    }

    private static func parseContentBlockDelta(_ data: String) -> ContentBlockDeltaEvent? {
        guard let jsonData = data.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let index = root["index"] as? Int,
              let delta = root["delta"] as? [String: Any],
              let type_ = delta["type"] as? String else { return nil }

        let text = delta["text"] as? String
        let partialJson = delta["partial_json"] as? String
        let thinking = delta["thinking"] as? String
        return ContentBlockDeltaEvent(
            index: index,
            delta: ContentBlockDeltaEvent.Delta(
                type: type_,
                text: text,
                partialJson: partialJson,
                thinking: thinking
            )
        )
    }

    private static func parseMessageDelta(_ data: String) -> MessageDeltaEvent? {
        guard let jsonData = data.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return nil
        }
        let delta = root["delta"] as? [String: Any]
        let stopReason = delta?["stop_reason"] as? String
        let usage = root["usage"] as? [String: Any]
        let outputTokens = usage?["output_tokens"] as? Int
        return MessageDeltaEvent(stopReason: stopReason, outputTokens: outputTokens)
    }

    private static func parseIndex(_ data: String) -> Int? {
        guard let jsonData = data.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return nil
        }
        return root["index"] as? Int
    }
}

// MARK: - Line Accumulator

/// Accumulates raw SSE text lines and emits complete events.
struct SSELineAccumulator {
    private var eventType: String = ""
    private var dataLines: [String] = []

    /// Feed a single raw line. Returns a ``StreamEvent`` when a complete event is ready.
    mutating func feed(_ line: String) -> StreamEvent? {
        if line.hasPrefix("event:") {
            eventType = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            return nil
        }
        if line.hasPrefix("data:") {
            let data = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            dataLines.append(data)
            return nil
        }
        if line.isEmpty, !eventType.isEmpty, !dataLines.isEmpty {
            let data = dataLines.joined(separator: "\n")
            let event = SSEParser.parse(eventType: eventType, data: data)
            eventType = ""
            dataLines = []
            return event
        }
        return nil
    }
}
