import Foundation

/// Controls Claude's thinking/reasoning behavior.
public enum ThinkingConfig: Codable, Sendable {
    /// Claude decides when and how much to think (Opus 4.6+).
    case adaptive
    /// Fixed thinking token budget.
    case enabled(budgetTokens: Int? = nil)
    /// No extended thinking.
    case disabled

    private enum CodingKeys: String, CodingKey {
        case type, budgetTokens
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "adaptive":
            self = .adaptive
        case "enabled":
            let budget = try container.decodeIfPresent(Int.self, forKey: .budgetTokens)
            self = .enabled(budgetTokens: budget)
        case "disabled":
            self = .disabled
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: container,
                debugDescription: "Unknown ThinkingConfig type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .adaptive:
            try container.encode("adaptive", forKey: .type)
        case .enabled(let budgetTokens):
            try container.encode("enabled", forKey: .type)
            try container.encodeIfPresent(budgetTokens, forKey: .budgetTokens)
        case .disabled:
            try container.encode("disabled", forKey: .type)
        }
    }
}
