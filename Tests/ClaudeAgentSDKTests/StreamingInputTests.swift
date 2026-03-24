import Testing
import Foundation
@testable import ClaudeAgentSDK

@Suite("Streaming Input")
struct StreamingInputTests {

    @Test("sendMessage writes formatted JSON to transport")
    func sendMessageWritesJSON() async throws {
        let transport = StreamingMockTransport()
        let query = Query(transport: transport, canUseTool: nil)

        try await query.sendMessage("Hello world")

        let written = transport.writtenData
        #expect(written.count == 1)

        let line = written[0]
        #expect(line.hasSuffix("\n"))
        #expect(line.contains("\"type\":\"user\""))
        #expect(line.contains("Hello world"))
    }

    @Test("Multiple sendMessage calls produce multiple JSON lines")
    func multipleSendMessages() async throws {
        let transport = StreamingMockTransport()
        let query = Query(transport: transport, canUseTool: nil)

        try await query.sendMessage("First")
        try await query.sendMessage("Second")
        try await query.sendMessage("Third")

        #expect(transport.writtenData.count == 3)
    }

    @Test("endInput closes transport input")
    func endInputClosesTransport() async throws {
        let transport = StreamingMockTransport()
        let query = Query(transport: transport, canUseTool: nil)

        #expect(transport.inputEnded == false)
        query.endInput()
        #expect(transport.inputEnded == true)
    }

    @Test("sendMessage with SDKUserMessage writes to transport")
    func sendSDKUserMessage() async throws {
        let transport = StreamingMockTransport()
        let query = Query(transport: transport, canUseTool: nil)

        let message = SDKUserMessage.text("test message")
        try await query.sendMessage(message)

        let written = transport.writtenData
        #expect(written.count == 1)
        #expect(written[0].contains("test message"))
    }

    @Test("Query iterates messages from streaming transport")
    func queryIteratesStreamingMessages() async throws {
        let transport = StreamingMockTransport()
        let query = Query(transport: transport, canUseTool: nil)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let resultMsg = try decoder.decode(SDKMessage.self, from: Data(Fixtures.resultSuccess.utf8))

        // Emit messages from a background task
        Task {
            transport.emit(.message(resultMsg))
            transport.finish()
        }

        var messages: [SDKMessage] = []
        for try await message in query {
            messages.append(message)
        }

        #expect(messages.count == 1)
        guard case .result(.success) = messages.first else {
            Issue.record("Expected result success")
            return
        }
    }
}
