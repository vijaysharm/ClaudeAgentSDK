import Testing
import Foundation
@testable import ClaudeAgentSDK

@Suite("Bridge API")
struct BridgeTests {

    @Test("BridgeSessionState encodes correctly")
    func stateEncoding() throws {
        let encoder = JSONEncoder()

        let idle = try encoder.encode(BridgeSessionState.idle)
        #expect(String(data: idle, encoding: .utf8) == "\"idle\"")

        let running = try encoder.encode(BridgeSessionState.running)
        #expect(String(data: running, encoding: .utf8) == "\"running\"")

        let action = try encoder.encode(BridgeSessionState.requiresAction)
        #expect(String(data: action, encoding: .utf8) == "\"requires_action\"")
    }

    @Test("BridgeSessionState decodes correctly")
    func stateDecoding() throws {
        let decoder = JSONDecoder()

        let idle = try decoder.decode(BridgeSessionState.self, from: Data("\"idle\"".utf8))
        #expect(idle == .idle)

        let action = try decoder.decode(BridgeSessionState.self, from: Data("\"requires_action\"".utf8))
        #expect(action == .requiresAction)
    }

    @Test("BridgeSessionOptions initializes with required fields")
    func optionsInit() {
        let options = BridgeSessionOptions(
            sessionId: "cse_abc",
            ingressToken: "jwt-token",
            apiBaseUrl: "https://api.example.com"
        )
        #expect(options.sessionId == "cse_abc")
        #expect(options.ingressToken == "jwt-token")
        #expect(options.apiBaseUrl == "https://api.example.com")
        #expect(options.epoch == nil)
        #expect(options.heartbeatIntervalMs == nil)
    }

    @Test("BridgeSessionHandle tracks connection state")
    func handleConnectionState() {
        let options = BridgeSessionOptions(
            sessionId: "cse_test",
            ingressToken: "token",
            apiBaseUrl: "https://api.example.com"
        )
        let handle = BridgeSessionHandle(options: options)

        #expect(handle.sessionId == "cse_test")
        #expect(handle.isConnected() == false)
        #expect(handle.getSequenceNum() == 0)
    }

    @Test("BridgeSessionHandle with initial sequence num")
    func handleWithSequenceNum() {
        let options = BridgeSessionOptions(
            sessionId: "cse_test",
            ingressToken: "token",
            apiBaseUrl: "https://api.example.com",
            initialSequenceNum: 42
        )
        let handle = BridgeSessionHandle(options: options)
        #expect(handle.getSequenceNum() == 42)
    }

    @Test("BridgeDeliveryStatus encodes")
    func deliveryStatus() throws {
        let encoder = JSONEncoder()
        let processing = try encoder.encode(BridgeDeliveryStatus.processing)
        #expect(String(data: processing, encoding: .utf8) == "\"processing\"")
    }

    @Test("BridgePermissionModeResult variants")
    func permissionModeResult() {
        let ok = BridgePermissionModeResult.ok
        let err = BridgePermissionModeResult.error("not supported")

        if case .ok = ok {} else { Issue.record("Expected ok") }
        if case let .error(msg) = err { #expect(msg == "not supported") }
        else { Issue.record("Expected error") }
    }
}
