import Testing
import Foundation
@testable import ClaudeAgentSDK

@Suite("Query")
struct QueryTests {

    @Test("Query iterates through messages")
    func queryIteration() async throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let initMsg = try decoder.decode(SDKMessage.self, from: Data(Fixtures.systemInitMessage.utf8))
        let assistantMsg = try decoder.decode(SDKMessage.self, from: Data(Fixtures.assistantMessage.utf8))
        let resultMsg = try decoder.decode(SDKMessage.self, from: Data(Fixtures.resultSuccess.utf8))

        let transport = MockTransport(messages: [
            .message(initMsg),
            .message(assistantMsg),
            .message(resultMsg),
        ])

        let query = Query(transport: transport, canUseTool: nil)

        var messages: [SDKMessage] = []
        for try await message in query {
            messages.append(message)
        }

        #expect(messages.count == 3)

        guard case .system(.initialize) = messages[0] else {
            Issue.record("Expected init message first")
            return
        }
        guard case .assistant = messages[1] else {
            Issue.record("Expected assistant message second")
            return
        }
        guard case .result(.success) = messages[2] else {
            Issue.record("Expected result success third")
            return
        }
    }

    @Test("Query filters keep_alive messages")
    func keepAliveFiltering() async throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let resultMsg = try decoder.decode(SDKMessage.self, from: Data(Fixtures.resultSuccess.utf8))

        let transport = MockTransport(messages: [
            .keepAlive,
            .keepAlive,
            .message(resultMsg),
            .keepAlive,
        ])

        let query = Query(transport: transport, canUseTool: nil)

        var messages: [SDKMessage] = []
        for try await message in query {
            messages.append(message)
        }

        #expect(messages.count == 1)
        guard case .result = messages.first else {
            Issue.record("Expected result message")
            return
        }
    }

    @Test("Query close terminates iteration")
    func queryClose() async throws {
        let transport = MockTransport(messages: [])
        let query = Query(transport: transport, canUseTool: nil)
        query.close()

        // Should complete immediately since transport is closed
        var count = 0
        for try await _ in query {
            count += 1
        }
        #expect(count == 0)
    }
}
