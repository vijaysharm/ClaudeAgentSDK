import Foundation

/// Result of a query — either success or error.
public enum SDKResultMessage: Sendable {
    case success(SDKResultSuccess)
    case error(SDKResultError)

    /// Whether this result represents an error.
    public var isError: Bool {
        switch self {
        case .success: return false
        case .error: return true
        }
    }

    /// The result text (success only).
    public var resultText: String? {
        switch self {
        case .success(let s): return s.result
        case .error: return nil
        }
    }

    /// Duration in milliseconds.
    public var durationMs: Int {
        switch self {
        case .success(let s): return s.durationMs
        case .error(let e): return e.durationMs
        }
    }

    /// Total cost in USD.
    public var totalCostUsd: Double {
        switch self {
        case .success(let s): return s.totalCostUsd
        case .error(let e): return e.totalCostUsd
        }
    }

    /// Session ID.
    public var sessionId: String {
        switch self {
        case .success(let s): return s.sessionId
        case .error(let e): return e.sessionId
        }
    }
}

extension SDKResultMessage: Codable {
    private enum CodingKeys: String, CodingKey {
        case subtype
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let subtype = try container.decode(String.self, forKey: .subtype)
        if subtype == "success" {
            self = .success(try SDKResultSuccess(from: decoder))
        } else {
            self = .error(try SDKResultError(from: decoder))
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .success(let value):
            try value.encode(to: encoder)
        case .error(let value):
            try value.encode(to: encoder)
        }
    }
}

/// Successful query result.
public struct SDKResultSuccess: Codable, Sendable {
    public let subtype: String
    public let durationMs: Int
    public let durationApiMs: Int
    public let isError: Bool
    public let numTurns: Int
    public let result: String
    public let stopReason: String?
    public let totalCostUsd: Double
    public let usage: NonNullableUsage
    public let modelUsage: [String: ModelUsage]
    public let permissionDenials: [SDKPermissionDenial]
    public let structuredOutput: AnyCodable?
    public let fastModeState: FastModeState?
    public let uuid: String
    public let sessionId: String
}

/// Error result subtypes.
public enum SDKResultErrorSubtype: String, Codable, Sendable {
    case errorDuringExecution = "error_during_execution"
    case errorMaxTurns = "error_max_turns"
    case errorMaxBudgetUsd = "error_max_budget_usd"
    case errorMaxStructuredOutputRetries = "error_max_structured_output_retries"
}

/// Error query result.
public struct SDKResultError: Codable, Sendable {
    public let subtype: String
    public let durationMs: Int
    public let durationApiMs: Int
    public let isError: Bool
    public let numTurns: Int
    public let stopReason: String?
    public let totalCostUsd: Double
    public let usage: NonNullableUsage
    public let modelUsage: [String: ModelUsage]
    public let permissionDenials: [SDKPermissionDenial]
    public let errors: [String]
    public let fastModeState: FastModeState?
    public let uuid: String
    public let sessionId: String
}
