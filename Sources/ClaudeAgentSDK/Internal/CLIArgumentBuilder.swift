import Foundation

/// Builds CLI arguments from ``Options`` for spawning the Claude Code process.
enum CLIArgumentBuilder {
    /// Build the CLI argument array for a query.
    ///
    /// - Parameters:
    ///   - options: The query options.
    ///   - prompt: The prompt string (nil for streaming input mode).
    ///   - isStreaming: Whether streaming input mode is used.
    /// - Returns: Array of CLI arguments (not including the executable path).
    static func buildArguments(
        options: Options,
        prompt: String?,
        isStreaming: Bool
    ) -> [String] {
        var args: [String] = []

        // Always use print mode with stream-json output
        args.append("--print")
        args.append("--output-format")
        args.append("stream-json")
        args.append("--verbose")

        if isStreaming {
            args.append("--input-format")
            args.append("stream-json")
        }

        if let model = options.model {
            args.append("--model")
            args.append(model)
        }

        if let permissionMode = options.permissionMode {
            args.append("--permission-mode")
            args.append(permissionMode.rawValue)
        }

        if options.allowDangerouslySkipPermissions == true {
            args.append("--dangerously-skip-permissions")
        }

        if let allowedTools = options.allowedTools, !allowedTools.isEmpty {
            args.append("--allowed-tools")
            args.append(contentsOf: allowedTools)
        }

        if let disallowedTools = options.disallowedTools, !disallowedTools.isEmpty {
            args.append("--disallowed-tools")
            args.append(contentsOf: disallowedTools)
        }

        if let tools = options.tools {
            switch tools {
            case .specific(let names):
                args.append("--tools")
                args.append(contentsOf: names)
            case .preset:
                break
            }
        }

        if let additionalDirectories = options.additionalDirectories, !additionalDirectories.isEmpty {
            args.append("--add-dir")
            args.append(contentsOf: additionalDirectories)
        }

        if let maxTurns = options.maxTurns {
            args.append("--max-turns")
            args.append(String(maxTurns))
        }

        if let maxBudget = options.maxBudgetUsd {
            args.append("--max-budget-usd")
            args.append(String(maxBudget))
        }

        if let effort = options.effort {
            args.append("--effort")
            args.append(effort.rawValue)
        }

        if let resume = options.resume {
            args.append("--resume")
            args.append(resume)
        }

        if let sessionId = options.sessionId {
            args.append("--session-id")
            args.append(sessionId)
        }

        if options.continueSession == true {
            args.append("--continue")
        }

        if options.forkSession == true {
            args.append("--fork-session")
        }

        switch options.systemPrompt {
        case .custom(let prompt):
            args.append("--system-prompt")
            args.append(prompt)
        case .presetWithAppend(let append):
            args.append("--append-system-prompt")
            args.append(append)
        case .preset, .none:
            break
        }

        if let maxThinkingTokens = options.maxThinkingTokens {
            args.append("--max-thinking-tokens")
            args.append(String(maxThinkingTokens))
        }

        if options.includePartialMessages == true {
            args.append("--include-partial-messages")
        }

        if options.debug == true {
            args.append("--debug")
        }

        if let debugFile = options.debugFile {
            args.append("--debug-file")
            args.append(debugFile)
        }

        if let fallbackModel = options.fallbackModel {
            args.append("--fallback-model")
            args.append(fallbackModel)
        }

        if options.persistSession == false {
            args.append("--no-session-persistence")
        }

        if let betas = options.betas, !betas.isEmpty {
            args.append("--betas")
            args.append(contentsOf: betas)
        }

        if let agent = options.agent {
            args.append("--agent")
            args.append(agent)
        }

        if let agents = options.agents, !agents.isEmpty {
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            if let data = try? encoder.encode(agents),
               let json = String(data: data, encoding: .utf8) {
                args.append("--agents")
                args.append(json)
            }
        }

        if let mcpServers = options.mcpServers, !mcpServers.isEmpty {
            let encoder = JSONEncoder()
            if let data = try? encoder.encode(["mcpServers": mcpServers]),
               let json = String(data: data, encoding: .utf8) {
                args.append("--mcp-config")
                args.append(json)
            }
        }

        if let settingSources = options.settingSources, !settingSources.isEmpty {
            args.append("--setting-sources")
            args.append(settingSources.map(\.rawValue).joined(separator: ","))
        }

        if options.strictMcpConfig == true {
            args.append("--strict-mcp-config")
        }

        if let outputFormat = options.outputFormat {
            let encoder = JSONEncoder()
            if let data = try? encoder.encode(outputFormat.schema),
               let json = String(data: data, encoding: .utf8) {
                args.append("--json-schema")
                args.append(json)
            }
        }

        // Extra args passthrough
        if let extraArgs = options.extraArgs {
            for (key, value) in extraArgs.sorted(by: { $0.key < $1.key }) {
                args.append("--\(key)")
                if let value {
                    args.append(value)
                }
            }
        }

        // Prompt goes last (as a positional argument)
        if let prompt, !isStreaming {
            args.append(prompt)
        }

        return args
    }
}
