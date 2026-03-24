import Testing
import Foundation
@testable import ClaudeAgentSDK

@Suite("Session")
struct SessionTests {
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    private func makeInitMessage() throws -> SDKMessage {
        try decoder.decode(SDKMessage.self, from: Data(Fixtures.systemInitMessage.utf8))
    }

    private func makeResultMessage() throws -> SDKMessage {
        try decoder.decode(SDKMessage.self, from: Data(Fixtures.resultSuccess.utf8))
    }

    private func makeAssistantMessage() throws -> SDKMessage {
        try decoder.decode(SDKMessage.self, from: Data(Fixtures.assistantMessage.utf8))
    }

    @Test("Session send writes user message JSON to transport")
    func sessionSend() async throws {
        let transport = StreamingMockTransport()
        let query = Query(transport: transport, canUseTool: nil)
        let session = Session(sessionId: "test-session", query: query)

        try await session.send("Hello!")

        let written = transport.writtenData
        #expect(written.count == 1)
        #expect(written[0].contains("Hello!"))
        #expect(written[0].contains("\"type\":\"user\""))
    }

    @Test("Session stream yields messages")
    func sessionStream() async throws {
        let transport = StreamingMockTransport()
        let query = Query(transport: transport, canUseTool: nil)
        let session = Session(sessionId: "test-session", query: query)

        let initMsg = try makeInitMessage()
        let assistantMsg = try makeAssistantMessage()
        let resultMsg = try makeResultMessage()

        Task {
            transport.emit(.message(initMsg))
            transport.emit(.message(assistantMsg))
            transport.emit(.message(resultMsg))
            transport.finish()
        }

        var messages: [SDKMessage] = []
        for try await msg in session.stream() {
            messages.append(msg)
        }

        #expect(messages.count == 3)
    }

    @Test("Session close terminates transport")
    func sessionClose() async throws {
        let transport = StreamingMockTransport()
        let query = Query(transport: transport, canUseTool: nil)
        let session = Session(sessionId: "test-session", query: query)

        session.close()
        #expect(transport.isClosed == true)
    }

    @Test("SessionOptions converts to Options correctly")
    func sessionOptionsConverts() {
        let opts = SessionOptions(
            model: "claude-opus-4-6",
            cwd: "/tmp",
            allowedTools: ["Read"],
            permissionMode: .acceptEdits,
            effort: .high
        )

        let fullOpts = opts.toOptions()
        #expect(fullOpts.model == "claude-opus-4-6")
        #expect(fullOpts.cwd == "/tmp")
        #expect(fullOpts.allowedTools == ["Read"])
        #expect(fullOpts.permissionMode == .acceptEdits)
        #expect(fullOpts.effort == .high)
    }

    @Test("SessionOptions with resume sets resume field")
    func sessionOptionsResume() {
        let opts = SessionOptions(model: "claude-sonnet-4-6")
        let fullOpts = opts.toOptions(resumeSessionId: "abc-123")
        #expect(fullOpts.resume == "abc-123")
    }
}
