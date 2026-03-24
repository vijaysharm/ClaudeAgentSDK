import Testing
import Foundation
@testable import ClaudeAgentSDK

@Suite("CLI Argument Builder")
struct CLIArgumentBuilderTests {

    @Test("Basic prompt generates minimal args")
    func basicPrompt() {
        let options = Options()
        let args = CLIArgumentBuilder.buildArguments(
            options: options,
            prompt: "Hello",
            isStreaming: false
        )
        #expect(args.contains("--print"))
        #expect(args.contains("--output-format"))
        #expect(args.contains("stream-json"))
        #expect(args.contains("--verbose"))
        #expect(args.last == "Hello")
        #expect(!args.contains("--input-format"))
    }

    @Test("Streaming mode adds input-format")
    func streamingMode() {
        let options = Options()
        let args = CLIArgumentBuilder.buildArguments(
            options: options,
            prompt: nil,
            isStreaming: true
        )
        #expect(args.contains("--input-format"))
        #expect(args.contains("stream-json"))
    }

    @Test("Model option")
    func modelOption() {
        let options = Options(model: "claude-opus-4-6")
        let args = CLIArgumentBuilder.buildArguments(
            options: options,
            prompt: "test",
            isStreaming: false
        )
        let modelIdx = args.firstIndex(of: "--model")!
        #expect(args[modelIdx + 1] == "claude-opus-4-6")
    }

    @Test("Permission mode option")
    func permissionMode() {
        let options = Options(permissionMode: .bypassPermissions)
        let args = CLIArgumentBuilder.buildArguments(
            options: options,
            prompt: "test",
            isStreaming: false
        )
        let idx = args.firstIndex(of: "--permission-mode")!
        #expect(args[idx + 1] == "bypassPermissions")
    }

    @Test("Dangerously skip permissions flag")
    func skipPermissions() {
        let options = Options(allowDangerouslySkipPermissions: true)
        let args = CLIArgumentBuilder.buildArguments(
            options: options,
            prompt: "test",
            isStreaming: false
        )
        #expect(args.contains("--dangerously-skip-permissions"))
    }

    @Test("Allowed tools")
    func allowedTools() {
        let options = Options(allowedTools: ["Bash", "Read"])
        let args = CLIArgumentBuilder.buildArguments(
            options: options,
            prompt: "test",
            isStreaming: false
        )
        let idx = args.firstIndex(of: "--allowed-tools")!
        #expect(args[idx + 1] == "Bash")
        #expect(args[idx + 2] == "Read")
    }

    @Test("Max turns and budget")
    func maxTurnsAndBudget() {
        let options = Options(maxTurns: 5, maxBudgetUsd: 1.5)
        let args = CLIArgumentBuilder.buildArguments(
            options: options,
            prompt: "test",
            isStreaming: false
        )
        let turnsIdx = args.firstIndex(of: "--max-turns")!
        #expect(args[turnsIdx + 1] == "5")
        let budgetIdx = args.firstIndex(of: "--max-budget-usd")!
        #expect(args[budgetIdx + 1] == "1.5")
    }

    @Test("Continue session flag")
    func continueSession() {
        let options = Options(continueSession: true)
        let args = CLIArgumentBuilder.buildArguments(
            options: options,
            prompt: "test",
            isStreaming: false
        )
        #expect(args.contains("--continue"))
    }

    @Test("Resume session")
    func resumeSession() {
        let options = Options(resume: "abc-123")
        let args = CLIArgumentBuilder.buildArguments(
            options: options,
            prompt: "test",
            isStreaming: false
        )
        let idx = args.firstIndex(of: "--resume")!
        #expect(args[idx + 1] == "abc-123")
    }

    @Test("Custom system prompt")
    func customSystemPrompt() {
        let options = Options(systemPrompt: .custom("Be helpful"))
        let args = CLIArgumentBuilder.buildArguments(
            options: options,
            prompt: "test",
            isStreaming: false
        )
        let idx = args.firstIndex(of: "--system-prompt")!
        #expect(args[idx + 1] == "Be helpful")
    }

    @Test("Append system prompt")
    func appendSystemPrompt() {
        let options = Options(systemPrompt: .presetWithAppend("Also be concise"))
        let args = CLIArgumentBuilder.buildArguments(
            options: options,
            prompt: "test",
            isStreaming: false
        )
        let idx = args.firstIndex(of: "--append-system-prompt")!
        #expect(args[idx + 1] == "Also be concise")
    }

    @Test("Debug flag")
    func debugFlag() {
        let options = Options(debug: true)
        let args = CLIArgumentBuilder.buildArguments(
            options: options,
            prompt: "test",
            isStreaming: false
        )
        #expect(args.contains("--debug"))
    }

    @Test("Effort level")
    func effortLevel() {
        let options = Options(effort: .low)
        let args = CLIArgumentBuilder.buildArguments(
            options: options,
            prompt: "test",
            isStreaming: false
        )
        let idx = args.firstIndex(of: "--effort")!
        #expect(args[idx + 1] == "low")
    }

    @Test("Extra args passthrough")
    func extraArgs() {
        let options = Options(extraArgs: ["verbose": nil, "name": "test-session"])
        let args = CLIArgumentBuilder.buildArguments(
            options: options,
            prompt: "test",
            isStreaming: false
        )
        #expect(args.contains("--verbose"))
        let nameIdx = args.firstIndex(of: "--name")!
        #expect(args[nameIdx + 1] == "test-session")
    }

    @Test("No session persistence")
    func noSessionPersistence() {
        let options = Options(persistSession: false)
        let args = CLIArgumentBuilder.buildArguments(
            options: options,
            prompt: "test",
            isStreaming: false
        )
        #expect(args.contains("--no-session-persistence"))
    }
}
