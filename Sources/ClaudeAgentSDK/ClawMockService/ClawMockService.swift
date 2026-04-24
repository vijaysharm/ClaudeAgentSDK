import Foundation

/// In-memory deterministic scenario service ported from the Rust
/// `mock-anthropic-service` crate.
///
/// This Swift port is intentionally transport-less — it exposes the pure
/// scenario detection + response builders so tests can drive the logic
/// without spinning up a TCP listener. Wire it up to a server of your
/// choice (e.g. SwiftNIO or `Network.framework`) if you need over-the-wire
/// behavior.
public enum ClawMockService {

    public static let scenarioPrefix = "PARITY_SCENARIO:"
    public static let defaultModel = "claude-sonnet-4-6"

    public enum Scenario: String, Sendable, Codable, Equatable, CaseIterable {
        case streamingText = "streaming_text"
        case readFileRoundtrip = "read_file_roundtrip"
        case grepChunkAssembly = "grep_chunk_assembly"
        case writeFileAllowed = "write_file_allowed"
        case writeFileDenied = "write_file_denied"
        case multiToolTurnRoundtrip = "multi_tool_turn_roundtrip"
        case bashStdoutRoundtrip = "bash_stdout_roundtrip"
        case bashPermissionPromptApproved = "bash_permission_prompt_approved"
        case bashPermissionPromptDenied = "bash_permission_prompt_denied"
        case pluginToolRoundtrip = "plugin_tool_roundtrip"
        case autoCompactTriggered = "auto_compact_triggered"
        case tokenCostReporting = "token_cost_reporting"

        public static func parse(_ value: String) -> Scenario? {
            Scenario(rawValue: value)
        }

        public var name: String { rawValue }
    }

    public struct CapturedRequest: Sendable, Equatable, Codable {
        public var method: String
        public var path: String
        public var headers: [String: String]
        public var scenario: String
        public var stream: Bool
        public var rawBody: String
    }

    /// Walk the input messages in reverse looking for a
    /// `PARITY_SCENARIO:<name>` token in a user text block.
    public static func detectScenario(_ request: ClawAPI.MessageRequest) -> Scenario? {
        for msg in request.messages.reversed() {
            for block in msg.content.reversed() {
                if case .text(let t) = block {
                    for token in t.split(whereSeparator: { $0 == " " || $0 == "\n" }) {
                        let s = String(token)
                        if s.hasPrefix(scenarioPrefix) {
                            let name = String(s.dropFirst(scenarioPrefix.count))
                            return Scenario.parse(name)
                        }
                    }
                }
            }
        }
        return nil
    }

    /// Build a non-streaming response for the given scenario.
    public static func buildMessageResponse(
        for request: ClawAPI.MessageRequest, scenario: Scenario
    ) -> ClawAPI.MessageResponse {
        let model = request.model.isEmpty ? defaultModel : request.model
        let id = "msg_" + String(UInt64.random(in: 0..<UInt64.max), radix: 16)
        switch scenario {
        case .streamingText, .tokenCostReporting:
            return textMessageResponse(
                id: id, model: model,
                text: "mock: streaming-text response",
                requestId: requestId(for: scenario)
            )
        case .readFileRoundtrip:
            return textMessageResponse(
                id: id, model: model,
                text: "mock: read_file roundtrip",
                requestId: requestId(for: scenario)
            )
        case .grepChunkAssembly:
            return textMessageResponse(
                id: id, model: model,
                text: "mock: grep_chunk_assembly",
                requestId: requestId(for: scenario)
            )
        case .writeFileAllowed:
            return textMessageResponse(
                id: id, model: model,
                text: "mock: write allowed",
                requestId: requestId(for: scenario)
            )
        case .writeFileDenied:
            return textMessageResponse(
                id: id, model: model,
                text: "mock: write denied",
                requestId: requestId(for: scenario)
            )
        case .multiToolTurnRoundtrip, .bashStdoutRoundtrip,
             .bashPermissionPromptApproved, .bashPermissionPromptDenied,
             .pluginToolRoundtrip, .autoCompactTriggered:
            return textMessageResponse(
                id: id, model: model,
                text: "mock: \(scenario.rawValue)",
                requestId: requestId(for: scenario)
            )
        }
    }

    /// Build a stream of SSE frames for the given scenario.
    public static func buildStreamFrames(
        for request: ClawAPI.MessageRequest, scenario: Scenario
    ) -> String {
        let model = request.model.isEmpty ? defaultModel : request.model
        let id = "msg_" + String(UInt64.random(in: 0..<UInt64.max), radix: 16)
        var out = ""
        let msgStart: [String: Any] = [
            "type": "message_start",
            "message": [
                "id": id,
                "type": "message",
                "role": "assistant",
                "model": model,
                "content": [],
                "usage": ["input_tokens": 10, "output_tokens": 0],
            ]
        ]
        append(&out, event: "message_start", payload: msgStart)
        append(&out, event: "content_block_start", payload: [
            "type": "content_block_start",
            "index": 0,
            "content_block": ["type": "text", "text": ""],
        ])
        append(&out, event: "content_block_delta", payload: [
            "type": "content_block_delta",
            "index": 0,
            "delta": ["type": "text_delta", "text": "mock: "],
        ])
        append(&out, event: "content_block_delta", payload: [
            "type": "content_block_delta",
            "index": 0,
            "delta": ["type": "text_delta", "text": scenario.rawValue],
        ])
        append(&out, event: "content_block_stop", payload: [
            "type": "content_block_stop", "index": 0,
        ])
        append(&out, event: "message_delta", payload: [
            "type": "message_delta",
            "delta": ["stop_reason": "end_turn"],
            "usage": ["output_tokens": 5],
        ])
        append(&out, event: "message_stop", payload: ["type": "message_stop"])
        return out
    }

    public static func requestId(for scenario: Scenario) -> String { "req_\(scenario.rawValue)" }

    // MARK: - Helpers

    static func textMessageResponse(
        id: String, model: String, text: String, requestId: String
    ) -> ClawAPI.MessageResponse {
        ClawAPI.MessageResponse(
            id: id,
            kind: "message",
            role: "assistant",
            content: [.text(text)],
            model: model,
            stopReason: "end_turn",
            stopSequence: nil,
            usage: ClawAPI.Usage(inputTokens: 10, outputTokens: 5),
            requestId: requestId
        )
    }

    static func append(_ buffer: inout String, event: String, payload: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let s = String(data: data, encoding: .utf8) else { return }
        buffer += "event: \(event)\ndata: \(s)\n\n"
    }
}
