import Foundation

/// Pending tool call extracted during an assistant turn.
private struct PendingToolCall {
    let id: String
    let name: String
    var inputJson: String
    var input: [String: AnyCodable] = [:]
}

/// The core agentic loop: streams an assistant turn, runs tool calls, repeats.
public actor AgentLoop {
    private let client: AnthropicClient
    private let options: AgentOptions
    private var history: [ApiMessage] = []
    private var totalInput = 0
    private var totalOutput = 0
    private var totalCacheRead = 0
    private var totalCacheWrite = 0
    private var turnCount = 0

    public init(options: AgentOptions) throws {
        let key = options.apiKey
            ?? ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"]
            ?? ""
        guard !key.isEmpty else { throw AgentError.missingAPIKey }
        self.client = AnthropicClient(apiKey: key, baseURL: options.apiBaseURL)
        self.options = options
    }

    /// Reset conversation history for a fresh run.
    public func reset() {
        history = []
        totalInput = 0; totalOutput = 0; totalCacheRead = 0; totalCacheWrite = 0
        turnCount = 0
    }

    /// Run the agent on a prompt, yielding ``AgentEvent`` values.
    public nonisolated func run(prompt: String) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                await runLoop(prompt: prompt, continuation: continuation)
            }
        }
    }

    // MARK: - Core Loop

    private func runLoop(
        prompt: String,
        continuation: AsyncThrowingStream<AgentEvent, Error>.Continuation
    ) async {
        history.append(ApiMessage(role: "user", content: .text(prompt)))

        let startMs = Date()
        var keepGoing = true

        do {
            while keepGoing {
                turnCount += 1
                if let max = options.maxTurns, turnCount > max {
                    continuation.yield(.failed(
                        reason: "max turns reached",
                        errors: ["Stopped after \(options.maxTurns!) turns"]
                    ))
                    continuation.finish()
                    return
                }

                continuation.yield(.status("Thinking…"))

                let (pendingTools, outputTokens) = try await streamTurnWithRetry(
                    continuation: continuation
                )
                totalOutput += outputTokens

                if pendingTools.isEmpty {
                    keepGoing = false
                } else {
                    let resultBlocks = try await executeTools(pendingTools, continuation: continuation)
                    history.append(ApiMessage(role: "user", content: .blocks(resultBlocks)))
                }
            }

            let elapsed = Int(Date().timeIntervalSince(startMs) * 1000)
            continuation.yield(.completed(AgentStats(
                inputTokens: totalInput,
                outputTokens: totalOutput,
                cacheReadTokens: totalCacheRead,
                cacheWriteTokens: totalCacheWrite,
                estimatedCostUsd: estimateCost(),
                durationMs: elapsed,
                numTurns: turnCount
            )))
            continuation.finish()
        } catch {
            continuation.yield(.failed(
                reason: error.localizedDescription,
                errors: [error.localizedDescription]
            ))
            continuation.finish(throwing: error)
        }
    }

    // MARK: - Retry Wrapper

    private func streamTurnWithRetry(
        continuation: AsyncThrowingStream<AgentEvent, Error>.Continuation
    ) async throws -> (tools: [PendingToolCall], outputTokens: Int) {
        var delay = 2.0
        for attempt in 1...(options.maxRetries + 1) {
            do {
                return try await streamTurn(continuation: continuation)
            } catch let err as AnthropicAPIError where err.type == "rate_limit_error" {
                continuation.yield(.rateLimited(resetsAt: nil))
                if attempt > options.maxRetries { throw err }
                continuation.yield(.apiRetry(attempt: attempt, maxAttempts: options.maxRetries, delaySeconds: delay))
                try await Task.sleep(for: .seconds(delay))
                delay = min(delay * 2, 60)
            } catch {
                if attempt > options.maxRetries { throw error }
                continuation.yield(.apiRetry(attempt: attempt, maxAttempts: options.maxRetries, delaySeconds: delay))
                try await Task.sleep(for: .seconds(delay))
                delay = min(delay * 2, 60)
            }
        }
        // Unreachable but required by the compiler
        throw AgentError.maxTurnsReached(options.maxRetries)
    }

    // MARK: - Stream One Turn

    private func streamTurn(
        continuation: AsyncThrowingStream<AgentEvent, Error>.Continuation
    ) async throws -> (tools: [PendingToolCall], outputTokens: Int) {

        let request = buildRequest()
        var pendingTools: [Int: PendingToolCall] = [:]
        var assistantBlocks: [ContentBlock] = []
        var currentTextBuffer = ""
        var currentThinkingBuffer = ""
        var outputTokens = 0

        for try await event in client.stream(request: request) {
            switch event {
            case .messageStart(let e):
                totalInput += e.inputTokens

            case .contentBlockStart(let e):
                switch e.block.type {
                case "text":
                    currentTextBuffer = ""
                case "thinking":
                    currentThinkingBuffer = ""
                case "tool_use":
                    guard let id = e.block.id, let name = e.block.name else { break }
                    pendingTools[e.index] = PendingToolCall(id: id, name: name, inputJson: "")
                default:
                    break
                }

            case .contentBlockDelta(let e):
                switch e.delta.type {
                case "text_delta":
                    if let text = e.delta.text, !text.isEmpty {
                        continuation.yield(.textDelta(text))
                        currentTextBuffer += text
                    }
                case "thinking_delta":
                    if let thinking = e.delta.thinking, !thinking.isEmpty {
                        continuation.yield(.thinkingDelta(thinking))
                        currentThinkingBuffer += thinking
                    }
                case "input_json_delta":
                    if let partial = e.delta.partialJson {
                        pendingTools[e.index]?.inputJson += partial
                    }
                default:
                    break
                }

            case .contentBlockStop(let index):
                if var call = pendingTools[index] {
                    if let data = call.inputJson.data(using: .utf8),
                       let raw = try? JSONDecoder().decode(AnyCodable.self, from: data),
                       case .object(let dict) = raw {
                        call.input = dict
                    }
                    pendingTools[index] = call

                    continuation.yield(.toolUseStarted(id: call.id, name: call.name, input: call.input))

                    let parsedInput: AnyCodable
                    if call.inputJson.isEmpty {
                        parsedInput = .null
                    } else {
                        parsedInput = (try? JSONDecoder().decode(AnyCodable.self, from: Data(call.inputJson.utf8))) ?? .null
                    }
                    assistantBlocks.append(.toolUse(ToolUseBlock(id: call.id, name: call.name, input: parsedInput)))

                } else if !currentTextBuffer.isEmpty {
                    assistantBlocks.append(.text(TextBlock(text: currentTextBuffer)))
                    currentTextBuffer = ""
                } else if !currentThinkingBuffer.isEmpty {
                    assistantBlocks.append(.thinking(ThinkingBlock(thinking: currentThinkingBuffer)))
                    currentThinkingBuffer = ""
                }

            case .messageDelta(let e):
                outputTokens += e.outputTokens ?? 0

            case .messageStop:
                break

            case .ping:
                break

            case .error(let err):
                throw err
            }
        }

        if !currentTextBuffer.isEmpty {
            assistantBlocks.append(.text(TextBlock(text: currentTextBuffer)))
        }

        history.append(ApiMessage(
            role: "assistant",
            content: assistantBlocks.isEmpty ? .text("") : .blocks(assistantBlocks)
        ))

        let completedTools = pendingTools.sorted { $0.key < $1.key }.map { $0.value }
        return (completedTools, outputTokens)
    }

    // MARK: - Tool Execution

    private func executeTools(
        _ calls: [PendingToolCall],
        continuation: AsyncThrowingStream<AgentEvent, Error>.Continuation
    ) async throws -> [ContentBlock] {
        let context = ToolContext(
            workingDirectory: options.workingDirectory ?? FileManager.default.currentDirectoryPath,
            permissionMode: options.permissionMode
        )
        let toolMap = Dictionary(uniqueKeysWithValues: options.tools.map { ($0.name, $0) })

        var resultBlocks: [ContentBlock] = []

        for call in calls {
            let startDate = Date()

            guard let tool = toolMap[call.name] else {
                let errOutput = "Tool not found: \(call.name)"
                resultBlocks.append(.toolResult(ToolResultBlock(
                    toolUseId: call.id, content: errOutput, isError: true
                )))
                continuation.yield(.toolResult(
                    id: call.id, name: call.name,
                    output: errOutput, isError: true, durationMs: 0
                ))
                continue
            }

            // Progress timer: yields an event every 500ms while tool runs
            let callId = call.id
            let callName = call.name
            let timerTask = Task.detached {
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
                    let elapsed = Date().timeIntervalSince(startDate)
                    continuation.yield(.toolProgress(id: callId, name: callName, elapsedSeconds: elapsed))
                }
            }

            let output: ToolOutput
            do {
                output = try await tool.execute(input: call.input, context: context)
            } catch {
                timerTask.cancel()
                output = .error(error.localizedDescription)
            }
            timerTask.cancel()

            let durationMs = Int(Date().timeIntervalSince(startDate) * 1000)
            continuation.yield(.toolResult(
                id: call.id, name: call.name,
                output: output.content, isError: output.isError,
                durationMs: durationMs
            ))
            resultBlocks.append(.toolResult(ToolResultBlock(
                toolUseId: call.id,
                content: output.content,
                isError: output.isError ? true : nil
            )))
        }

        return resultBlocks
    }

    // MARK: - Request Builder

    private func buildRequest() -> MessageRequest {
        let toolDefs: [ToolDefinition] = options.tools.map {
            ToolDefinition(name: $0.name, description: $0.description, inputSchema: $0.inputSchema)
        }

        let thinking: ThinkingRequestConfig? = options.thinkingEnabled
            ? ThinkingRequestConfig(budgetTokens: options.thinkingBudgetTokens)
            : nil

        return MessageRequest(
            model: options.model,
            maxTokens: options.maxTokens,
            messages: history,
            system: options.systemPrompt,
            tools: toolDefs.isEmpty ? nil : toolDefs,
            stream: true,
            thinking: thinking
        )
    }

    // MARK: - Cost Estimation

    private func estimateCost() -> Double {
        // Approximate pricing for claude-sonnet-4-6 per million tokens
        let inputCost  = Double(totalInput)      / 1_000_000.0 * 3.00
        let outputCost = Double(totalOutput)     / 1_000_000.0 * 15.0
        let cacheRead  = Double(totalCacheRead)  / 1_000_000.0 * 0.30
        let cacheWrite = Double(totalCacheWrite) / 1_000_000.0 * 3.75
        return inputCost + outputCost + cacheRead + cacheWrite
    }
}
