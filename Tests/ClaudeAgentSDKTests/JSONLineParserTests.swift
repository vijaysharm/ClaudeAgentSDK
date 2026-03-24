import Testing
import Foundation
@testable import ClaudeAgentSDK

@Suite("JSON Line Parser")
struct JSONLineParserTests {

    @Test("Parse empty line returns nil")
    func emptyLine() throws {
        let result = try JSONLineParser.parse("")
        #expect(result == nil)
    }

    @Test("Parse whitespace line returns nil")
    func whitespaceLine() throws {
        let result = try JSONLineParser.parse("   \n  ")
        #expect(result == nil)
    }

    @Test("Parse keep_alive message")
    func keepAlive() throws {
        let result = try JSONLineParser.parse(Fixtures.keepAlive)
        guard case .keepAlive = result else {
            Issue.record("Expected keep_alive")
            return
        }
    }

    @Test("Parse SDK message")
    func sdkMessage() throws {
        let result = try JSONLineParser.parse(Fixtures.assistantMessage)
        guard case .message(.assistant) = result else {
            Issue.record("Expected assistant message")
            return
        }
    }

    @Test("Parse control request")
    func controlRequest() throws {
        let result = try JSONLineParser.parse(Fixtures.controlRequestPermission)
        guard case .controlRequest(let req) = result else {
            Issue.record("Expected control request")
            return
        }
        #expect(req.requestId == "req-001")
        #expect(req.request.subtype == "can_use_tool")
        #expect(req.request.toolName == "Bash")
    }

    @Test("Parse invalid JSON throws error")
    func invalidJSON() {
        #expect(throws: (any Error).self) {
            _ = try JSONLineParser.parse("{invalid json}")
        }
    }
}
