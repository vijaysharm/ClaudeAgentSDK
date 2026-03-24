import Testing
import Foundation
@testable import ClaudeAgentSDK

@Suite("Session Management")
struct SessionManagementTests {

    @Test("ListSessionsOptions has correct defaults")
    func listSessionsOptionsDefaults() {
        let opts = ListSessionsOptions()
        #expect(opts.dir == nil)
        #expect(opts.limit == nil)
        #expect(opts.offset == nil)
    }

    @Test("ForkSessionResult is decodable")
    func forkSessionResultDecodable() throws {
        let json = """
        {"sessionId":"abc-123-def"}
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let result = try decoder.decode(ForkSessionResult.self, from: Data(json.utf8))
        #expect(result.sessionId == "abc-123-def")
    }

    @Test("SessionJSONLEntry decodes user entry")
    func jsonlEntryDecodesUser() throws {
        let json = """
        {"type":"user","uuid":"aaa-111","parentUuid":"root","isSidechain":false,"timestamp":"2026-01-01T00:00:00Z","message":{"role":"user","content":"Hello"}}
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let entry = try decoder.decode(SessionJSONLEntry.self, from: Data(json.utf8))
        #expect(entry.type == "user")
        #expect(entry.uuid == "aaa-111")
        #expect(entry.isSidechain == false)
        #expect(entry.message?["content"]?.stringValue == "Hello")
    }

    @Test("SessionJSONLEntry decodes custom-title entry")
    func jsonlEntryDecodesTitle() throws {
        let json = """
        {"type":"custom-title","title":"My Session"}
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let entry = try decoder.decode(SessionJSONLEntry.self, from: Data(json.utf8))
        #expect(entry.type == "custom-title")
        #expect(entry.title == "My Session")
    }

    @Test("SessionJSONLEntry decodes assistant entry")
    func jsonlEntryDecodesAssistant() throws {
        let json = """
        {"type":"assistant","uuid":"bbb-222","isSidechain":false,"message":{"role":"assistant","content":[{"type":"text","text":"Hi there!"}]}}
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let entry = try decoder.decode(SessionJSONLEntry.self, from: Data(json.utf8))
        #expect(entry.type == "assistant")
        #expect(entry.uuid == "bbb-222")
    }

    #if os(macOS)
    @Test("listSessions reads from projects directory")
    func listSessionsReadsFiles() async throws {
        // This is an integration test that reads real session files
        // It will return results if there are any sessions on this machine
        let sessions = try await ClaudeAgentSDK.listSessions()
        // Just verify it doesn't crash — actual content depends on the machine
        #expect(sessions is [SDKSessionInfo])
    }

    @Test("getSessionInfo returns nil for non-existent session")
    func getSessionInfoNonExistent() async throws {
        let info = try await ClaudeAgentSDK.getSessionInfo("non-existent-session-id")
        #expect(info == nil)
    }

    @Test("getSessionMessages returns empty for non-existent session")
    func getSessionMessagesNonExistent() async throws {
        let messages = try await ClaudeAgentSDK.getSessionMessages("non-existent-session-id")
        #expect(messages.isEmpty)
    }
    #endif
}
