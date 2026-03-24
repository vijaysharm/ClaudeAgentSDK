import Testing
import Foundation
@testable import ClaudeAgentSDK

@Suite("Message Decoding")
struct MessageDecodingTests {
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    @Test("Decode system init message")
    func decodeSystemInit() throws {
        let message = try decoder.decode(SDKMessage.self, from: Data(Fixtures.systemInitMessage.utf8))
        guard case .system(.initialize(let init_msg)) = message else {
            Issue.record("Expected system init message")
            return
        }
        #expect(init_msg.model == "claude-sonnet-4-6")
        #expect(init_msg.claudeCodeVersion == "2.1.81")
        #expect(init_msg.cwd == "/Users/test")
        #expect(init_msg.tools.contains("Bash"))
        #expect(init_msg.permissionMode == .default)
        #expect(init_msg.sessionId == "session-123")
    }

    @Test("Decode assistant message")
    func decodeAssistant() throws {
        let message = try decoder.decode(SDKMessage.self, from: Data(Fixtures.assistantMessage.utf8))
        guard case .assistant(let msg) = message else {
            Issue.record("Expected assistant message")
            return
        }
        #expect(msg.uuid == "22222222-2222-2222-2222-222222222222")
        #expect(msg.sessionId == "session-123")
        #expect(msg.parentToolUseId == nil)
        #expect(msg.error == nil)
    }

    @Test("Decode result success")
    func decodeResultSuccess() throws {
        let message = try decoder.decode(SDKMessage.self, from: Data(Fixtures.resultSuccess.utf8))
        guard case .result(.success(let result)) = message else {
            Issue.record("Expected result success")
            return
        }
        #expect(result.result == "Hello! How can I help you today?")
        #expect(result.durationMs == 2712)
        #expect(result.numTurns == 1)
        #expect(result.totalCostUsd > 0)
        #expect(result.isError == false)
        #expect(result.sessionId == "session-123")
    }

    @Test("Decode result error")
    func decodeResultError() throws {
        let message = try decoder.decode(SDKMessage.self, from: Data(Fixtures.resultError.utf8))
        guard case .result(.error(let result)) = message else {
            Issue.record("Expected result error")
            return
        }
        #expect(result.subtype == "error_max_turns")
        #expect(result.isError == true)
        #expect(result.numTurns == 10)
        #expect(result.errors.contains("Max turns reached"))
    }

    @Test("Decode status message")
    func decodeStatus() throws {
        let message = try decoder.decode(SDKMessage.self, from: Data(Fixtures.statusMessage.utf8))
        guard case .system(.status(let status)) = message else {
            Issue.record("Expected status message")
            return
        }
        #expect(status.status == "compacting")
        #expect(status.permissionMode == .default)
    }

    @Test("Decode tool progress message")
    func decodeToolProgress() throws {
        let message = try decoder.decode(SDKMessage.self, from: Data(Fixtures.toolProgressMessage.utf8))
        guard case .toolProgress(let msg) = message else {
            Issue.record("Expected tool progress message")
            return
        }
        #expect(msg.toolName == "Bash")
        #expect(msg.toolUseId == "tu_123")
        #expect(msg.elapsedTimeSeconds == 2.5)
    }

    @Test("Decode task started message")
    func decodeTaskStarted() throws {
        let message = try decoder.decode(SDKMessage.self, from: Data(Fixtures.taskStartedMessage.utf8))
        guard case .system(.taskStarted(let msg)) = message else {
            Issue.record("Expected task started message")
            return
        }
        #expect(msg.taskId == "task-1")
        #expect(msg.description == "Running tests")
    }

    @Test("Decode rate limit event")
    func decodeRateLimitEvent() throws {
        let message = try decoder.decode(SDKMessage.self, from: Data(Fixtures.rateLimitEvent.utf8))
        guard case .rateLimitEvent(let msg) = message else {
            Issue.record("Expected rate limit event")
            return
        }
        #expect(msg.rateLimitInfo.status == "allowed")
        #expect(msg.rateLimitInfo.utilization == 0.5)
    }

    @Test("Decode prompt suggestion")
    func decodePromptSuggestion() throws {
        let message = try decoder.decode(SDKMessage.self, from: Data(Fixtures.promptSuggestion.utf8))
        guard case .promptSuggestion(let msg) = message else {
            Issue.record("Expected prompt suggestion")
            return
        }
        #expect(msg.suggestion == "Can you also add tests?")
    }
}
