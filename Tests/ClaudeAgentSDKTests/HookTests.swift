import Testing
import Foundation
@testable import ClaudeAgentSDK

@Suite("Hooks")
struct HookTests {

    @Test("HookEvent encodes all 23 cases")
    func hookEventEncoding() throws {
        let encoder = JSONEncoder()
        for event in HookEvent.allCases {
            let data = try encoder.encode(event)
            let str = String(data: data, encoding: .utf8)!
            #expect(str.contains(event.rawValue))
        }
        #expect(HookEvent.allCases.count == 23)
    }

    @Test("HookEvent decodes from raw values")
    func hookEventDecoding() throws {
        let json = "\"PreToolUse\""
        let decoded = try JSONDecoder().decode(HookEvent.self, from: Data(json.utf8))
        #expect(decoded == .preToolUse)
    }

    @Test("SyncHookOutput encodes correctly")
    func syncOutputEncoding() throws {
        let output = SyncHookOutput(
            continue: true,
            decision: "approve",
            reason: "Tool is safe"
        )

        let data = try JSONEncoder().encode(output)
        let json = String(data: data, encoding: .utf8)!

        #expect(json.contains("\"approve\""))
        #expect(json.contains("Tool is safe"))
    }

    @Test("BaseHookInput decodes from JSON")
    func baseHookInputDecoding() throws {
        let json = """
        {"session_id":"abc","transcript_path":"/tmp/t.jsonl","cwd":"/home","permission_mode":"default","hook_event_name":"PreToolUse"}
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let input = try decoder.decode(BaseHookInput.self, from: Data(json.utf8))

        #expect(input.sessionId == "abc")
        #expect(input.hookEventName == "PreToolUse")
        #expect(input.cwd == "/home")
    }

    @Test("HookHandler dispatches to matching callback")
    func hookHandlerDispatch() async {
        let hooks: [HookEvent: [HookCallbackMatcher]] = [
            .preToolUse: [
                HookCallbackMatcher(hooks: [{ input, data, toolUseId in
                    return .sync(SyncHookOutput(decision: "approve", reason: "callback-fired"))
                }])
            ]
        ]

        let input: [String: AnyCodable] = [
            "sessionId": "test",
            "transcriptPath": "/tmp",
            "cwd": "/home",
            "hookEventName": "PreToolUse",
        ]

        let result = await HookHandler.handle(
            callbackId: "req-1",
            input: input,
            toolUseId: nil,
            hooks: hooks
        )

        #expect(result["decision"]?.stringValue == "approve")
        #expect(result["reason"]?.stringValue == "callback-fired")
    }

    @Test("HookHandler returns continue for unknown events")
    func hookHandlerUnknownEvent() async {
        let result = await HookHandler.handle(
            callbackId: "req-1",
            input: ["hookEventName": "UnknownEvent"],
            toolUseId: nil,
            hooks: [:]
        )
        #expect(result["continue"]?.boolValue == true)
    }

    @Test("Options accepts hooks")
    func optionsWithHooks() {
        let options = Options(
            hooks: [
                .preToolUse: [
                    HookCallbackMatcher(matcher: "Bash", hooks: [{ _, _, _ in
                        .sync(SyncHookOutput(decision: "block"))
                    }])
                ]
            ]
        )
        #expect(options.hooks?[.preToolUse]?.count == 1)
        #expect(options.hooks?[.preToolUse]?.first?.matcher == "Bash")
    }
}
