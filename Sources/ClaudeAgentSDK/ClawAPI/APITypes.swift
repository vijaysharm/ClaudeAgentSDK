import Foundation

extension ClawAPI {

    // MARK: - Request

    /// An Anthropic-shaped messages request. Serialized to the provider-specific
    /// wire format by each provider client.
    public struct MessageRequest: Codable, Sendable, Equatable {
        public var model: String
        public var maxTokens: UInt32
        public var messages: [InputMessage]
        public var system: String?
        public var tools: [ToolDefinition]?
        public var toolChoice: ToolChoice?
        public var stream: Bool
        public var temperature: Double?
        public var topP: Double?
        public var frequencyPenalty: Double?
        public var presencePenalty: Double?
        public var stop: [String]?
        public var reasoningEffort: String?

        public init(
            model: String,
            maxTokens: UInt32,
            messages: [InputMessage] = [],
            system: String? = nil,
            tools: [ToolDefinition]? = nil,
            toolChoice: ToolChoice? = nil,
            stream: Bool = false,
            temperature: Double? = nil,
            topP: Double? = nil,
            frequencyPenalty: Double? = nil,
            presencePenalty: Double? = nil,
            stop: [String]? = nil,
            reasoningEffort: String? = nil
        ) {
            self.model = model
            self.maxTokens = maxTokens
            self.messages = messages
            self.system = system
            self.tools = tools
            self.toolChoice = toolChoice
            self.stream = stream
            self.temperature = temperature
            self.topP = topP
            self.frequencyPenalty = frequencyPenalty
            self.presencePenalty = presencePenalty
            self.stop = stop
            self.reasoningEffort = reasoningEffort
        }

        public func withStreaming() -> MessageRequest {
            var copy = self
            copy.stream = true
            return copy
        }

        private enum CodingKeys: String, CodingKey {
            case model
            case maxTokens = "max_tokens"
            case messages
            case system
            case tools
            case toolChoice = "tool_choice"
            case stream
            case temperature
            case topP = "top_p"
            case frequencyPenalty = "frequency_penalty"
            case presencePenalty = "presence_penalty"
            case stop
            case reasoningEffort = "reasoning_effort"
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            model = try c.decode(String.self, forKey: .model)
            maxTokens = try c.decode(UInt32.self, forKey: .maxTokens)
            messages = try c.decodeIfPresent([InputMessage].self, forKey: .messages) ?? []
            system = try c.decodeIfPresent(String.self, forKey: .system)
            tools = try c.decodeIfPresent([ToolDefinition].self, forKey: .tools)
            toolChoice = try c.decodeIfPresent(ToolChoice.self, forKey: .toolChoice)
            stream = try c.decodeIfPresent(Bool.self, forKey: .stream) ?? false
            temperature = try c.decodeIfPresent(Double.self, forKey: .temperature)
            topP = try c.decodeIfPresent(Double.self, forKey: .topP)
            frequencyPenalty = try c.decodeIfPresent(Double.self, forKey: .frequencyPenalty)
            presencePenalty = try c.decodeIfPresent(Double.self, forKey: .presencePenalty)
            stop = try c.decodeIfPresent([String].self, forKey: .stop)
            reasoningEffort = try c.decodeIfPresent(String.self, forKey: .reasoningEffort)
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(model, forKey: .model)
            try c.encode(maxTokens, forKey: .maxTokens)
            try c.encode(messages, forKey: .messages)
            try c.encodeIfPresent(system, forKey: .system)
            try c.encodeIfPresent(tools, forKey: .tools)
            try c.encodeIfPresent(toolChoice, forKey: .toolChoice)
            if stream {
                try c.encode(true, forKey: .stream)
            }
            try c.encodeIfPresent(temperature, forKey: .temperature)
            try c.encodeIfPresent(topP, forKey: .topP)
            try c.encodeIfPresent(frequencyPenalty, forKey: .frequencyPenalty)
            try c.encodeIfPresent(presencePenalty, forKey: .presencePenalty)
            try c.encodeIfPresent(stop, forKey: .stop)
            try c.encodeIfPresent(reasoningEffort, forKey: .reasoningEffort)
        }
    }

    // MARK: - Input Message + blocks

    public struct InputMessage: Codable, Sendable, Equatable {
        public var role: String
        public var content: [InputContentBlock]

        public init(role: String, content: [InputContentBlock]) {
            self.role = role
            self.content = content
        }

        public static func userText(_ text: String) -> InputMessage {
            InputMessage(role: "user", content: [.text(text)])
        }

        public static func userToolResult(
            toolUseId: String,
            content: [ToolResultContentBlock],
            isError: Bool = false
        ) -> InputMessage {
            InputMessage(
                role: "user",
                content: [.toolResult(toolUseId: toolUseId, content: content, isError: isError)]
            )
        }
    }

    public enum InputContentBlock: Codable, Sendable, Equatable {
        case text(String)
        case toolUse(id: String, name: String, input: AnyCodable)
        case toolResult(toolUseId: String, content: [ToolResultContentBlock], isError: Bool)

        private enum CodingKeys: String, CodingKey {
            case type, text, id, name, input
            case toolUseId = "tool_use_id"
            case content
            case isError = "is_error"
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let type = try c.decode(String.self, forKey: .type)
            switch type {
            case "text":
                self = .text(try c.decode(String.self, forKey: .text))
            case "tool_use":
                self = .toolUse(
                    id: try c.decode(String.self, forKey: .id),
                    name: try c.decode(String.self, forKey: .name),
                    input: try c.decode(AnyCodable.self, forKey: .input)
                )
            case "tool_result":
                self = .toolResult(
                    toolUseId: try c.decode(String.self, forKey: .toolUseId),
                    content: try c.decode([ToolResultContentBlock].self, forKey: .content),
                    isError: try c.decodeIfPresent(Bool.self, forKey: .isError) ?? false
                )
            default:
                throw DecodingError.dataCorruptedError(
                    forKey: .type, in: c,
                    debugDescription: "Unknown input content block type: \(type)"
                )
            }
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .text(let text):
                try c.encode("text", forKey: .type)
                try c.encode(text, forKey: .text)
            case .toolUse(let id, let name, let input):
                try c.encode("tool_use", forKey: .type)
                try c.encode(id, forKey: .id)
                try c.encode(name, forKey: .name)
                try c.encode(input, forKey: .input)
            case .toolResult(let id, let content, let isError):
                try c.encode("tool_result", forKey: .type)
                try c.encode(id, forKey: .toolUseId)
                try c.encode(content, forKey: .content)
                if isError { try c.encode(true, forKey: .isError) }
            }
        }
    }

    public enum ToolResultContentBlock: Codable, Sendable, Equatable {
        case text(String)
        case json(AnyCodable)

        private enum CodingKeys: String, CodingKey {
            case type, text, value
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let type = try c.decode(String.self, forKey: .type)
            switch type {
            case "text":
                self = .text(try c.decode(String.self, forKey: .text))
            case "json":
                self = .json(try c.decode(AnyCodable.self, forKey: .value))
            default:
                throw DecodingError.dataCorruptedError(
                    forKey: .type, in: c,
                    debugDescription: "Unknown tool result content block type: \(type)"
                )
            }
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .text(let text):
                try c.encode("text", forKey: .type)
                try c.encode(text, forKey: .text)
            case .json(let value):
                try c.encode("json", forKey: .type)
                try c.encode(value, forKey: .value)
            }
        }
    }

    // MARK: - Tool definition + choice

    public struct ToolDefinition: Codable, Sendable, Equatable {
        public var name: String
        public var description: String?
        public var inputSchema: AnyCodable

        public init(name: String, description: String? = nil, inputSchema: AnyCodable) {
            self.name = name
            self.description = description
            self.inputSchema = inputSchema
        }

        private enum CodingKeys: String, CodingKey {
            case name, description
            case inputSchema = "input_schema"
        }
    }

    public enum ToolChoice: Codable, Sendable, Equatable {
        case auto
        case any
        case tool(name: String)

        private enum CodingKeys: String, CodingKey { case type, name }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            switch try c.decode(String.self, forKey: .type) {
            case "auto": self = .auto
            case "any": self = .any
            case "tool": self = .tool(name: try c.decode(String.self, forKey: .name))
            default: throw DecodingError.dataCorruptedError(
                forKey: .type, in: c,
                debugDescription: "Unknown tool_choice type"
            )
            }
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .auto: try c.encode("auto", forKey: .type)
            case .any: try c.encode("any", forKey: .type)
            case .tool(let name):
                try c.encode("tool", forKey: .type)
                try c.encode(name, forKey: .name)
            }
        }
    }

    // MARK: - Response

    public struct MessageResponse: Codable, Sendable, Equatable {
        public var id: String
        public var kind: String
        public var role: String
        public var content: [OutputContentBlock]
        public var model: String
        public var stopReason: String?
        public var stopSequence: String?
        public var usage: Usage
        public var requestId: String?

        public init(
            id: String,
            kind: String = "message",
            role: String = "assistant",
            content: [OutputContentBlock] = [],
            model: String,
            stopReason: String? = nil,
            stopSequence: String? = nil,
            usage: Usage = Usage(),
            requestId: String? = nil
        ) {
            self.id = id
            self.kind = kind
            self.role = role
            self.content = content
            self.model = model
            self.stopReason = stopReason
            self.stopSequence = stopSequence
            self.usage = usage
            self.requestId = requestId
        }

        public func totalTokens() -> UInt32 {
            usage.totalTokens()
        }

        private enum CodingKeys: String, CodingKey {
            case id
            case kind = "type"
            case role, content, model
            case stopReason = "stop_reason"
            case stopSequence = "stop_sequence"
            case usage
            case requestId = "request_id"
        }
    }

    public enum OutputContentBlock: Codable, Sendable, Equatable {
        case text(String)
        case toolUse(id: String, name: String, input: AnyCodable)
        case thinking(text: String, signature: String?)
        case redactedThinking(data: AnyCodable)

        private enum CodingKeys: String, CodingKey {
            case type, text, id, name, input, thinking, signature, data
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let type = try c.decode(String.self, forKey: .type)
            switch type {
            case "text":
                self = .text(try c.decode(String.self, forKey: .text))
            case "tool_use":
                self = .toolUse(
                    id: try c.decode(String.self, forKey: .id),
                    name: try c.decode(String.self, forKey: .name),
                    input: try c.decode(AnyCodable.self, forKey: .input)
                )
            case "thinking":
                self = .thinking(
                    text: try c.decode(String.self, forKey: .thinking),
                    signature: try c.decodeIfPresent(String.self, forKey: .signature)
                )
            case "redacted_thinking":
                self = .redactedThinking(data: try c.decode(AnyCodable.self, forKey: .data))
            default:
                throw DecodingError.dataCorruptedError(
                    forKey: .type, in: c,
                    debugDescription: "Unknown output content block type: \(type)"
                )
            }
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .text(let text):
                try c.encode("text", forKey: .type)
                try c.encode(text, forKey: .text)
            case .toolUse(let id, let name, let input):
                try c.encode("tool_use", forKey: .type)
                try c.encode(id, forKey: .id)
                try c.encode(name, forKey: .name)
                try c.encode(input, forKey: .input)
            case .thinking(let text, let signature):
                try c.encode("thinking", forKey: .type)
                try c.encode(text, forKey: .thinking)
                try c.encodeIfPresent(signature, forKey: .signature)
            case .redactedThinking(let data):
                try c.encode("redacted_thinking", forKey: .type)
                try c.encode(data, forKey: .data)
            }
        }
    }

    // MARK: - Usage

    public struct Usage: Codable, Sendable, Equatable {
        public var inputTokens: UInt32
        public var cacheCreationInputTokens: UInt32
        public var cacheReadInputTokens: UInt32
        public var outputTokens: UInt32

        public init(
            inputTokens: UInt32 = 0,
            cacheCreationInputTokens: UInt32 = 0,
            cacheReadInputTokens: UInt32 = 0,
            outputTokens: UInt32 = 0
        ) {
            self.inputTokens = inputTokens
            self.cacheCreationInputTokens = cacheCreationInputTokens
            self.cacheReadInputTokens = cacheReadInputTokens
            self.outputTokens = outputTokens
        }

        public func totalTokens() -> UInt32 {
            inputTokens &+ cacheCreationInputTokens &+ cacheReadInputTokens &+ outputTokens
        }

        private enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case cacheCreationInputTokens = "cache_creation_input_tokens"
            case cacheReadInputTokens = "cache_read_input_tokens"
            case outputTokens = "output_tokens"
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            inputTokens = try c.decodeIfPresent(UInt32.self, forKey: .inputTokens) ?? 0
            cacheCreationInputTokens = try c.decodeIfPresent(UInt32.self, forKey: .cacheCreationInputTokens) ?? 0
            cacheReadInputTokens = try c.decodeIfPresent(UInt32.self, forKey: .cacheReadInputTokens) ?? 0
            outputTokens = try c.decodeIfPresent(UInt32.self, forKey: .outputTokens) ?? 0
        }
    }

    // MARK: - Stream events

    public struct MessageStartEvent: Codable, Sendable, Equatable {
        public var message: MessageResponse
    }

    public struct MessageDelta: Codable, Sendable, Equatable {
        public var stopReason: String?
        public var stopSequence: String?

        private enum CodingKeys: String, CodingKey {
            case stopReason = "stop_reason"
            case stopSequence = "stop_sequence"
        }
    }

    public struct MessageDeltaEvent: Codable, Sendable, Equatable {
        public var delta: MessageDelta
        public var usage: Usage

        public init(delta: MessageDelta, usage: Usage = Usage()) {
            self.delta = delta
            self.usage = usage
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            delta = try c.decode(MessageDelta.self, forKey: .delta)
            usage = try c.decodeIfPresent(Usage.self, forKey: .usage) ?? Usage()
        }

        private enum CodingKeys: String, CodingKey { case delta, usage }
    }

    public struct ContentBlockStartEvent: Codable, Sendable, Equatable {
        public var index: UInt32
        public var contentBlock: OutputContentBlock

        private enum CodingKeys: String, CodingKey {
            case index
            case contentBlock = "content_block"
        }
    }

    public enum ContentBlockDelta: Codable, Sendable, Equatable {
        case textDelta(String)
        case inputJsonDelta(String)
        case thinkingDelta(String)
        case signatureDelta(String)

        private enum CodingKeys: String, CodingKey {
            case type, text, partialJson = "partial_json", thinking, signature
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let type = try c.decode(String.self, forKey: .type)
            switch type {
            case "text_delta":
                self = .textDelta(try c.decode(String.self, forKey: .text))
            case "input_json_delta":
                self = .inputJsonDelta(try c.decode(String.self, forKey: .partialJson))
            case "thinking_delta":
                self = .thinkingDelta(try c.decode(String.self, forKey: .thinking))
            case "signature_delta":
                self = .signatureDelta(try c.decode(String.self, forKey: .signature))
            default:
                throw DecodingError.dataCorruptedError(
                    forKey: .type, in: c,
                    debugDescription: "Unknown content block delta type: \(type)"
                )
            }
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .textDelta(let s):
                try c.encode("text_delta", forKey: .type)
                try c.encode(s, forKey: .text)
            case .inputJsonDelta(let s):
                try c.encode("input_json_delta", forKey: .type)
                try c.encode(s, forKey: .partialJson)
            case .thinkingDelta(let s):
                try c.encode("thinking_delta", forKey: .type)
                try c.encode(s, forKey: .thinking)
            case .signatureDelta(let s):
                try c.encode("signature_delta", forKey: .type)
                try c.encode(s, forKey: .signature)
            }
        }
    }

    public struct ContentBlockDeltaEvent: Codable, Sendable, Equatable {
        public var index: UInt32
        public var delta: ContentBlockDelta
    }

    public struct ContentBlockStopEvent: Codable, Sendable, Equatable {
        public var index: UInt32
    }

    public struct MessageStopEvent: Codable, Sendable, Equatable {
        public init() {}
    }

    /// Anthropic-shaped streaming events. Provider implementations (including OpenAI
    /// compatibility) translate their native stream into this enum.
    public enum StreamEvent: Codable, Sendable, Equatable {
        case messageStart(MessageStartEvent)
        case messageDelta(MessageDeltaEvent)
        case contentBlockStart(ContentBlockStartEvent)
        case contentBlockDelta(ContentBlockDeltaEvent)
        case contentBlockStop(ContentBlockStopEvent)
        case messageStop(MessageStopEvent)

        private enum CodingKeys: String, CodingKey { case type }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let type = try c.decode(String.self, forKey: .type)
            switch type {
            case "message_start":
                self = .messageStart(try MessageStartEvent(from: decoder))
            case "message_delta":
                self = .messageDelta(try MessageDeltaEvent(from: decoder))
            case "content_block_start":
                self = .contentBlockStart(try ContentBlockStartEvent(from: decoder))
            case "content_block_delta":
                self = .contentBlockDelta(try ContentBlockDeltaEvent(from: decoder))
            case "content_block_stop":
                self = .contentBlockStop(try ContentBlockStopEvent(from: decoder))
            case "message_stop":
                self = .messageStop(MessageStopEvent())
            default:
                throw DecodingError.dataCorruptedError(
                    forKey: .type, in: c,
                    debugDescription: "Unknown stream event type: \(type)"
                )
            }
        }

        public func encode(to encoder: Encoder) throws {
            var typeContainer = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .messageStart(let e):
                try typeContainer.encode("message_start", forKey: .type)
                try e.encode(to: encoder)
            case .messageDelta(let e):
                try typeContainer.encode("message_delta", forKey: .type)
                try e.encode(to: encoder)
            case .contentBlockStart(let e):
                try typeContainer.encode("content_block_start", forKey: .type)
                try e.encode(to: encoder)
            case .contentBlockDelta(let e):
                try typeContainer.encode("content_block_delta", forKey: .type)
                try e.encode(to: encoder)
            case .contentBlockStop(let e):
                try typeContainer.encode("content_block_stop", forKey: .type)
                try e.encode(to: encoder)
            case .messageStop:
                try typeContainer.encode("message_stop", forKey: .type)
            }
        }
    }
}
