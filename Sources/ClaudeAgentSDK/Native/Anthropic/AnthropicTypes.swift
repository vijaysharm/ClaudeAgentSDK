import Foundation

// MARK: - Request Types

struct MessageRequest: Encodable {
    let model: String
    let maxTokens: Int
    let messages: [ApiMessage]
    let system: String?
    let tools: [ToolDefinition]?
    let stream: Bool
    let thinking: ThinkingRequestConfig?

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case messages
        case system
        case tools
        case stream
        case thinking
    }
}

struct ThinkingRequestConfig: Encodable {
    let type: String = "enabled"
    let budgetTokens: Int

    enum CodingKeys: String, CodingKey {
        case type
        case budgetTokens = "budget_tokens"
    }
}

struct ToolDefinition: Encodable {
    let name: String
    let description: String
    let inputSchema: AnyCodable

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case inputSchema = "input_schema"
    }
}

// MARK: - Message Types

struct ApiMessage: Codable, Sendable {
    let role: String
    let content: MessageContent
}

enum MessageContent: Codable, Sendable {
    case text(String)
    case blocks([ContentBlock])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            self = .text(text)
        } else {
            self = .blocks(try container.decode([ContentBlock].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let t): try container.encode(t)
        case .blocks(let b): try container.encode(b)
        }
    }
}

enum ContentBlock: Codable, Sendable {
    case text(TextBlock)
    case toolUse(ToolUseBlock)
    case toolResult(ToolResultBlock)
    case thinking(ThinkingBlock)

    private enum TypeKey: String, CodingKey { case type }

    init(from decoder: Decoder) throws {
        let typeContainer = try decoder.container(keyedBy: TypeKey.self)
        let type_ = try typeContainer.decode(String.self, forKey: .type)
        switch type_ {
        case "text":        self = .text(try TextBlock(from: decoder))
        case "tool_use":    self = .toolUse(try ToolUseBlock(from: decoder))
        case "tool_result": self = .toolResult(try ToolResultBlock(from: decoder))
        case "thinking":    self = .thinking(try ThinkingBlock(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: typeContainer,
                debugDescription: "Unknown content block type: \(type_)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .text(let b):       try b.encode(to: encoder)
        case .toolUse(let b):    try b.encode(to: encoder)
        case .toolResult(let b): try b.encode(to: encoder)
        case .thinking(let b):   try b.encode(to: encoder)
        }
    }
}

struct TextBlock: Codable, Sendable {
    let type: String = "text"
    let text: String

    enum CodingKeys: String, CodingKey { case type, text }
}

struct ToolUseBlock: Codable, Sendable {
    let type: String = "tool_use"
    let id: String
    let name: String
    let input: AnyCodable

    enum CodingKeys: String, CodingKey { case type, id, name, input }
}

struct ToolResultBlock: Codable, Sendable {
    let type: String = "tool_result"
    let toolUseId: String
    let content: String
    let isError: Bool?

    enum CodingKeys: String, CodingKey {
        case type
        case toolUseId = "tool_use_id"
        case content
        case isError = "is_error"
    }
}

struct ThinkingBlock: Codable, Sendable {
    let type: String = "thinking"
    let thinking: String

    enum CodingKeys: String, CodingKey { case type, thinking }
}

// MARK: - Streaming Event Types

enum StreamEvent: Sendable {
    case messageStart(MessageStartEvent)
    case contentBlockStart(ContentBlockStartEvent)
    case contentBlockDelta(ContentBlockDeltaEvent)
    case contentBlockStop(index: Int)
    case messageDelta(MessageDeltaEvent)
    case messageStop
    case ping
    case error(AnthropicAPIError)
}

struct MessageStartEvent: Sendable {
    let id: String
    let model: String
    let inputTokens: Int
}

struct ContentBlockStartEvent: Sendable {
    let index: Int
    let block: StartBlock

    struct StartBlock: Sendable {
        let type: String
        let id: String?
        let name: String?
    }
}

struct ContentBlockDeltaEvent: Sendable {
    let index: Int
    let delta: Delta

    struct Delta: Sendable {
        let type: String
        let text: String?
        let partialJson: String?
        let thinking: String?
    }
}

struct MessageDeltaEvent: Sendable {
    let stopReason: String?
    let outputTokens: Int?
}

// MARK: - API Error

struct AnthropicAPIError: Decodable, Error, Sendable {
    let type: String?
    let error: ErrorDetail?

    struct ErrorDetail: Decodable, Sendable {
        let type: String?
        let message: String?
    }

    var localizedDescription: String {
        error?.message ?? type ?? "Unknown Anthropic API error"
    }
}

// MARK: - Usage

struct UsageStats: Decodable, Sendable {
    let inputTokens: Int?
    let outputTokens: Int?
    let cacheCreationInputTokens: Int?
    let cacheReadInputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cacheCreationInputTokens = "cache_creation_input_tokens"
        case cacheReadInputTokens = "cache_read_input_tokens"
    }
}
