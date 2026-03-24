import Foundation

/// Internal handler for dispatching hook control requests to registered callbacks.
enum HookHandler {
    /// Handle a hook callback control request.
    ///
    /// - Parameters:
    ///   - callbackId: The callback ID from the control request.
    ///   - input: The raw hook input data.
    ///   - toolUseId: The tool use ID, if applicable.
    ///   - hooks: The registered hook callbacks by event.
    /// - Returns: Response fields to send back via control protocol.
    static func handle(
        callbackId: String,
        input: [String: AnyCodable],
        toolUseId: String?,
        hooks: [HookEvent: [HookCallbackMatcher]]
    ) async -> [String: AnyCodable] {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        // Parse base input to get the event name
        guard let inputData = try? JSONEncoder().encode(input),
              let baseInput = try? decoder.decode(BaseHookInput.self, from: inputData) else {
            return ["continue": .bool(true)]
        }

        // Find the matching hook event
        guard let event = HookEvent(rawValue: baseInput.hookEventName) else {
            return ["continue": .bool(true)]
        }

        guard let matchers = hooks[event] else {
            return ["continue": .bool(true)]
        }

        // Run matching callbacks
        for matcher in matchers {
            for callback in matcher.hooks {
                do {
                    let output = try await callback(baseInput, input, toolUseId)
                    switch output {
                    case let .sync(syncOutput):
                        return encodeSyncOutput(syncOutput)
                    case .async(let timeout):
                        return [
                            "async": .bool(true),
                            "asyncTimeout": timeout.map { .double($0) } ?? .null,
                        ]
                    }
                } catch {
                    return ["continue": .bool(true)]
                }
            }
        }

        return ["continue": .bool(true)]
    }

    private static func encodeSyncOutput(_ output: SyncHookOutput) -> [String: AnyCodable] {
        var result: [String: AnyCodable] = [:]
        if let v = output.continue { result["continue"] = .bool(v) }
        if let v = output.suppressOutput { result["suppressOutput"] = .bool(v) }
        if let v = output.stopReason { result["stopReason"] = .string(v) }
        if let v = output.decision { result["decision"] = .string(v) }
        if let v = output.systemMessage { result["systemMessage"] = .string(v) }
        if let v = output.reason { result["reason"] = .string(v) }
        if let v = output.hookSpecificOutput { result["hookSpecificOutput"] = .object(v) }
        return result
    }
}
