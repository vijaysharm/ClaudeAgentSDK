import XCTest
@testable import ClaudeAgentSDK

/// Sanity tests for the Claw Code Rust→Swift ports. These are syntactic/logic
/// smoke tests — they don't hit any network.
final class ClawAPIPortTests: XCTestCase {

    func testModelAliasesResolve() {
        XCTAssertEqual(ClawAPI.resolveModelAlias("sonnet"), "claude-sonnet-4-6")
        XCTAssertEqual(ClawAPI.resolveModelAlias("opus"), "claude-opus-4-6")
        XCTAssertEqual(ClawAPI.resolveModelAlias("grok-mini"), "grok-3-mini")
        XCTAssertEqual(ClawAPI.resolveModelAlias("kimi"), "kimi-k2.5")
        XCTAssertEqual(ClawAPI.resolveModelAlias("custom/model"), "custom/model")
    }

    func testProviderDetection() {
        XCTAssertEqual(
            ClawAPI.detectProviderKind("claude-sonnet-4-6", environment: [:]),
            .anthropic
        )
        XCTAssertEqual(
            ClawAPI.detectProviderKind("grok-3", environment: [:]),
            .xai
        )
        XCTAssertEqual(
            ClawAPI.detectProviderKind("gpt-5", environment: [:]),
            .openai
        )
    }

    func testTokenLimits() {
        let limit = ClawAPI.modelTokenLimit("claude-opus-4-6")
        XCTAssertEqual(limit?.maxOutputTokens, 32_000)
        XCTAssertEqual(limit?.contextWindowTokens, 200_000)

        XCTAssertEqual(ClawAPI.maxTokensForModel("sonnet"), 64_000)
        XCTAssertEqual(ClawAPI.maxTokensForModel("opus"), 32_000)
    }

    func testPreflightRejectsOversizedRequest() {
        let huge = String(repeating: "a ", count: 500_000)
        let req = ClawAPI.MessageRequest(
            model: "claude-sonnet-4-6",
            maxTokens: 64_000,
            messages: [.userText(huge)]
        )
        do {
            try ClawAPI.preflightMessageRequest(req)
            XCTFail("expected preflight to throw")
        } catch ClawAPI.ApiError.contextWindowExceeded {
            // expected
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testFnv1aStability() {
        XCTAssertEqual(ClawAPI.FNV1a64.hashString(""), 0xcbf29ce484222325)
        XCTAssertNotEqual(
            ClawAPI.FNV1a64.hashString("hello"),
            ClawAPI.FNV1a64.hashString("world")
        )
    }

    func testParseDotenv() {
        let parsed = ClawAPI.parseDotenv("""
            # comment
            FOO=bar
            export BAZ="qux"
            EMPTY=
            """)
        XCTAssertEqual(parsed["FOO"], "bar")
        XCTAssertEqual(parsed["BAZ"], "qux")
    }

    func testSsePingIsSkipped() throws {
        let frame = "event: ping\ndata: {}"
        let event = try ClawAPI.SseParser.parseFrame(frame)
        XCTAssertNil(event)
    }

    func testSseDoneIsSkipped() throws {
        let frame = "data: [DONE]"
        let event = try ClawAPI.SseParser.parseFrame(frame)
        XCTAssertNil(event)
    }

    func testSseMessageStopDecodes() throws {
        let frame = #"data: {"type":"message_stop"}"#
        let event = try ClawAPI.SseParser.parseFrame(frame)
        guard case .messageStop = event else {
            XCTFail("expected message_stop, got \(String(describing: event))")
            return
        }
    }

    func testApiErrorRetryableClassification() {
        let err = ClawAPI.ApiError.api(
            status: .tooManyRequests, errorType: nil, message: nil,
            requestId: nil, body: "", retryable: true, suggestedAction: nil
        )
        XCTAssertTrue(err.isRetryable)
        XCTAssertEqual(err.safeFailureClass, "provider_rate_limit")
    }

    func testOpenAICompatTranslatesToolResultDropsIsErrorForKimi() {
        let msg = ClawAPI.InputMessage(role: "user", content: [
            .toolResult(
                toolUseId: "abc",
                content: [.text("hello")],
                isError: true
            ),
        ])
        let out = ClawAPI.OpenAiCompatClient.translateMessage(msg, model: "kimi-k2.5")
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0]["role"] as? String, "tool")
        XCTAssertNil(out[0]["is_error"])
    }
}

/// Tests for ClawRuntime ports.
final class ClawRuntimePortTests: XCTestCase {

    func testPermissionModeOrdering() {
        XCTAssertTrue(ClawRuntime.PermissionMode.readOnly < .workspaceWrite)
        XCTAssertTrue(ClawRuntime.PermissionMode.workspaceWrite < .dangerFullAccess)
    }

    func testPermissionEnforcerDeniesReadOnlyWrites() {
        let policy = ClawRuntime.PermissionPolicy(activeMode: .readOnly)
        let enforcer = ClawRuntime.PermissionEnforcer(policy)
        let result = enforcer.checkFileWrite(path: "/tmp/x", workspaceRoot: "/tmp")
        guard case .denied = result else {
            XCTFail("expected deny")
            return
        }
    }

    func testReadOnlyBashAllowsGitStatus() {
        let policy = ClawRuntime.PermissionPolicy(activeMode: .readOnly)
        let enforcer = ClawRuntime.PermissionEnforcer(policy)
        XCTAssertTrue(enforcer.checkBash(command: "git status").isAllowed)
    }

    func testBashValidationBlocksRmInReadOnly() {
        switch ClawRuntime.BashValidator.validateReadOnly("rm -rf foo", mode: .readOnly) {
        case .block: break
        default: XCTFail("expected block")
        }
    }

    func testPolicyEngineRunsInPriorityOrder() {
        let engine = ClawRuntime.PolicyEngine(rules: [
            ClawRuntime.PolicyRule(
                name: "a", condition: .laneCompleted,
                action: .closeoutLane, priority: 1
            ),
            ClawRuntime.PolicyRule(
                name: "b", condition: .laneCompleted,
                action: .cleanupSession, priority: 0
            ),
        ])
        let ctx = ClawRuntime.LaneContext.reconciled(laneId: "x")
        let actions = engine.evaluate(ctx)
        XCTAssertEqual(actions.first, .cleanupSession)
    }

    func testBranchLockDetectsCollisions() {
        let collisions = ClawRuntime.detectBranchLockCollisions([
            ClawRuntime.BranchLockIntent(laneId: "a", branch: "main", modules: ["pkg"]),
            ClawRuntime.BranchLockIntent(laneId: "b", branch: "main", modules: ["pkg/sub"]),
        ])
        XCTAssertEqual(collisions.count, 1)
        XCTAssertEqual(collisions.first?.module, "pkg")
    }

    func testSessionMonotonicIds() {
        let a = ClawRuntime.Session.generateId()
        let b = ClawRuntime.Session.generateId()
        XCTAssertNotEqual(a, b)
    }

    func testBootstrapPhasesDedup() {
        let plan = ClawRuntime.BootstrapPlan.fromPhases([
            .cliEntry, .cliEntry, .mainRuntime, .cliEntry,
        ])
        XCTAssertEqual(plan.phases, [.cliEntry, .mainRuntime])
    }

    func testRecoveryContextEscalatesAfterMax() {
        var ctx = ClawRuntime.RecoveryContext()
        _ = ClawRuntime.attemptRecovery(.providerFailure, context: &ctx)
        let result = ClawRuntime.attemptRecovery(.providerFailure, context: &ctx)
        guard case .escalationRequired = result else {
            XCTFail("expected escalationRequired on second attempt")
            return
        }
    }

    func testSummaryCompressionRespectsBudget() {
        let long = Array(repeating: "- item", count: 100).joined(separator: "\n")
        let result = ClawRuntime.compressSummary(long)
        XCTAssertLessThanOrEqual(result.compressedLines, 24)
    }

    func testTrustResolverNoPromptReturnsNotRequired() {
        let resolver = ClawRuntime.TrustResolver(config: ClawRuntime.TrustConfig())
        let decision = resolver.resolve(cwd: "/tmp", screenText: "nothing here")
        if case .notRequired = decision {
            // ok
        } else {
            XCTFail("expected notRequired")
        }
    }

    func testMcpNamingPrefix() {
        XCTAssertEqual(ClawRuntime.MCP.toolPrefix(serverName: "hello world"), "mcp__hello_world__")
        XCTAssertEqual(
            ClawRuntime.MCP.toolName(serverName: "srv", toolName: "do-thing"),
            "mcp__srv__do-thing"
        )
    }
}

final class ClawCommandsPortTests: XCTestCase {

    func testParseHelp() throws {
        let parsed = try ClawCommands.parse("/help")
        XCTAssertEqual(parsed, .help)
    }

    func testParseAliases() throws {
        let parsed = try ClawCommands.parse("/plugin list")
        XCTAssertEqual(parsed, .plugins(action: "list", target: nil))
    }

    func testSuggestSlashCommands() {
        let suggestions = ClawCommands.suggestSlashCommands("/hel")
        XCTAssertTrue(suggestions.contains("/help"))
    }

    func testSkillsDispatchClassification() {
        XCTAssertEqual(ClawCommands.classifySkillsSlashCommand(nil), .local)
        XCTAssertEqual(
            ClawCommands.classifySkillsSlashCommand("coding-helper"),
            .invoke("$coding-helper")
        )
    }
}

final class ClawToolsPortTests: XCTestCase {

    func testMvpToolSpecsCoverBuiltins() {
        let names = Set(ClawTools.mvpToolSpecs().map(\.name))
        XCTAssertTrue(names.contains("bash"))
        XCTAssertTrue(names.contains("read_file"))
        XCTAssertTrue(names.contains("grep_search"))
    }

    func testNormalizeAllowedToolsExpandsAliases() {
        let normalized = ClawTools.GlobalToolRegistry.normalizeAllowedTools(["read, Write, glob"])
        XCTAssertTrue(normalized.contains("read_file"))
        XCTAssertTrue(normalized.contains("write_file"))
        XCTAssertTrue(normalized.contains("glob_search"))
    }

    func testLaneCompletionDetectorRequiresGreenAndPush() {
        let output = ClawTools.AgentOutput(
            agentId: "agent-1", name: "demo", description: "",
            status: "completed", laneEvents: [], currentBlocker: nil,
            derivedState: "done", error: nil
        )
        XCTAssertNil(ClawTools.detectLaneCompletion(output: output, testGreen: false, hasPushed: true))
        XCTAssertNotNil(ClawTools.detectLaneCompletion(output: output, testGreen: true, hasPushed: true))
    }
}

final class ClawMockServicePortTests: XCTestCase {

    func testDetectScenarioFromMarker() {
        let req = ClawAPI.MessageRequest(
            model: "claude-sonnet-4-6",
            maxTokens: 1024,
            messages: [.userText("please run PARITY_SCENARIO:streaming_text now")]
        )
        XCTAssertEqual(ClawMockService.detectScenario(req), .streamingText)
    }

    func testBuildStreamFramesEmitsMessageStart() {
        let req = ClawAPI.MessageRequest(
            model: "claude-sonnet-4-6",
            maxTokens: 1024,
            messages: []
        )
        let body = ClawMockService.buildStreamFrames(for: req, scenario: .streamingText)
        XCTAssertTrue(body.contains("message_start"))
        XCTAssertTrue(body.contains("message_stop"))
    }
}
