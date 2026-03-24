import Foundation

/// Union of all system event subtypes.
public enum SDKSystemEvent: Sendable {
    case initialize(SDKSystemInitMessage)
    case status(SDKStatusMessage)
    case apiRetry(SDKAPIRetryMessage)
    case compactBoundary(SDKCompactBoundaryMessage)
    case hookStarted(SDKHookStartedMessage)
    case hookProgress(SDKHookProgressMessage)
    case hookResponse(SDKHookResponseMessage)
    case taskNotification(SDKTaskNotificationMessage)
    case taskStarted(SDKTaskStartedMessage)
    case taskProgress(SDKTaskProgressMessage)
    case filesPersisted(SDKFilesPersistedEvent)
    case localCommandOutput(SDKLocalCommandOutputMessage)
    case elicitationComplete(SDKElicitationCompleteMessage)
}

/// All possible messages emitted by the Claude Code CLI.
///
/// Each variant corresponds to a different `type` (and optionally `subtype`) in the
/// JSON stream from the CLI's `--output-format stream-json` mode.
public enum SDKMessage: Sendable {
    case assistant(SDKAssistantMessage)
    case user(SDKUserMessage)
    case userReplay(SDKUserMessageReplay)
    case result(SDKResultMessage)
    case system(SDKSystemEvent)
    case streamEvent(SDKPartialAssistantMessage)
    case toolProgress(SDKToolProgressMessage)
    case toolUseSummary(SDKToolUseSummaryMessage)
    case rateLimitEvent(SDKRateLimitEvent)
    case authStatus(SDKAuthStatusMessage)
    case promptSuggestion(SDKPromptSuggestionMessage)
}

// MARK: - Decodable

extension SDKMessage: Decodable {
    private enum TypeKey: String, CodingKey {
        case type
        case subtype
        case isReplay
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: TypeKey.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "assistant":
            self = .assistant(try SDKAssistantMessage(from: decoder))

        case "user":
            let isReplay = try container.decodeIfPresent(Bool.self, forKey: .isReplay) ?? false
            if isReplay {
                self = .userReplay(try SDKUserMessageReplay(from: decoder))
            } else {
                self = .user(try SDKUserMessage(from: decoder))
            }

        case "result":
            self = .result(try SDKResultMessage(from: decoder))

        case "system":
            let subtype = try container.decode(String.self, forKey: .subtype)
            self = .system(try Self.decodeSystemEvent(subtype: subtype, from: decoder))

        case "stream_event":
            self = .streamEvent(try SDKPartialAssistantMessage(from: decoder))

        case "tool_progress":
            self = .toolProgress(try SDKToolProgressMessage(from: decoder))

        case "tool_use_summary":
            self = .toolUseSummary(try SDKToolUseSummaryMessage(from: decoder))

        case "rate_limit_event":
            self = .rateLimitEvent(try SDKRateLimitEvent(from: decoder))

        case "auth_status":
            self = .authStatus(try SDKAuthStatusMessage(from: decoder))

        case "prompt_suggestion":
            self = .promptSuggestion(try SDKPromptSuggestionMessage(from: decoder))

        default:
            throw DecodingError.dataCorruptedError(
                forKey: TypeKey.type,
                in: container,
                debugDescription: "Unknown SDKMessage type: \(type)"
            )
        }
    }

    private static func decodeSystemEvent(subtype: String, from decoder: Decoder) throws -> SDKSystemEvent {
        switch subtype {
        case "init":
            return .initialize(try SDKSystemInitMessage(from: decoder))
        case "status":
            return .status(try SDKStatusMessage(from: decoder))
        case "api_retry":
            return .apiRetry(try SDKAPIRetryMessage(from: decoder))
        case "compact_boundary":
            return .compactBoundary(try SDKCompactBoundaryMessage(from: decoder))
        case "hook_started":
            return .hookStarted(try SDKHookStartedMessage(from: decoder))
        case "hook_progress":
            return .hookProgress(try SDKHookProgressMessage(from: decoder))
        case "hook_response":
            return .hookResponse(try SDKHookResponseMessage(from: decoder))
        case "task_notification":
            return .taskNotification(try SDKTaskNotificationMessage(from: decoder))
        case "task_started":
            return .taskStarted(try SDKTaskStartedMessage(from: decoder))
        case "task_progress":
            return .taskProgress(try SDKTaskProgressMessage(from: decoder))
        case "files_persisted":
            return .filesPersisted(try SDKFilesPersistedEvent(from: decoder))
        case "local_command_output":
            return .localCommandOutput(try SDKLocalCommandOutputMessage(from: decoder))
        case "elicitation_complete":
            return .elicitationComplete(try SDKElicitationCompleteMessage(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: TypeKey.subtype,
                in: try decoder.container(keyedBy: TypeKey.self),
                debugDescription: "Unknown system subtype: \(subtype)"
            )
        }
    }
}

// MARK: - Encodable

extension SDKMessage: Encodable {
    public func encode(to encoder: Encoder) throws {
        switch self {
        case .assistant(let msg): try msg.encode(to: encoder)
        case .user(let msg): try msg.encode(to: encoder)
        case .userReplay(let msg): try msg.encode(to: encoder)
        case .result(let msg): try msg.encode(to: encoder)
        case .system(let event):
            switch event {
            case .initialize(let msg): try msg.encode(to: encoder)
            case .status(let msg): try msg.encode(to: encoder)
            case .apiRetry(let msg): try msg.encode(to: encoder)
            case .compactBoundary(let msg): try msg.encode(to: encoder)
            case .hookStarted(let msg): try msg.encode(to: encoder)
            case .hookProgress(let msg): try msg.encode(to: encoder)
            case .hookResponse(let msg): try msg.encode(to: encoder)
            case .taskNotification(let msg): try msg.encode(to: encoder)
            case .taskStarted(let msg): try msg.encode(to: encoder)
            case .taskProgress(let msg): try msg.encode(to: encoder)
            case .filesPersisted(let msg): try msg.encode(to: encoder)
            case .localCommandOutput(let msg): try msg.encode(to: encoder)
            case .elicitationComplete(let msg): try msg.encode(to: encoder)
            }
        case .streamEvent(let msg): try msg.encode(to: encoder)
        case .toolProgress(let msg): try msg.encode(to: encoder)
        case .toolUseSummary(let msg): try msg.encode(to: encoder)
        case .rateLimitEvent(let msg): try msg.encode(to: encoder)
        case .authStatus(let msg): try msg.encode(to: encoder)
        case .promptSuggestion(let msg): try msg.encode(to: encoder)
        }
    }
}
