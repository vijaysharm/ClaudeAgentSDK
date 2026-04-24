import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

// MARK: - TerminalRenderer

/// Renders an ``SDKMessage`` stream to the terminal in the style of the Claude Code CLI.
///
/// The renderer replicates the visual row-based experience of `claude` at the terminal:
/// - **Streaming text** appears character-by-character as tokens arrive.
/// - **Tool-use rows** show an animated spinner while executing, then a ✓ checkmark on completion.
/// - **Status lines** (e.g. "Thinking…") appear transiently and are cleared by the next event.
/// - **API retries and rate limits** surface as brief notices.
/// - **Cost/token summary** is printed at the end of each query.
///
/// ## Basic Usage
///
/// ```swift
/// let query = try ClaudeAgentSDK.query(prompt: "List files in this directory")
/// try await TerminalRenderer.run(query)
/// ```
///
/// ## Custom Configuration
///
/// ```swift
/// let config = TerminalRenderer.Config(showCostSummary: false, colorEnabled: true)
/// try await TerminalRenderer.run(query, config: config)
/// ```
///
/// ## Session Usage
///
/// ```swift
/// let session = try ClaudeAgentSDK.createSession(options: SessionOptions(model: "claude-sonnet-4-6"))
/// let renderer = TerminalRenderer()
///
/// try await session.send("Hello!")
/// try await renderer.render(session.stream())
///
/// try await session.send("What did I just say?")
/// try await renderer.render(session.stream())
///
/// session.close()
/// ```
public actor TerminalRenderer {

    // MARK: - Configuration

    /// Configuration for ``TerminalRenderer``.
    public struct Config: Sendable {
        /// Show tool-execution rows with spinner and elapsed time.
        public var showToolRows: Bool
        /// Show the cost/token/duration summary after the result.
        public var showCostSummary: Bool
        /// Show transient status lines (e.g. "Thinking…").
        public var showStatusLines: Bool
        /// Show API retry notices.
        public var showRetryNotices: Bool
        /// Show context-compaction notices.
        public var showCompactionNotices: Bool
        /// `true` = always color, `false` = never color, `nil` = auto-detect from TTY.
        public var colorEnabled: Bool?
        /// `true` = always animate spinner, `false` = never, `nil` = auto-detect from TTY.
        public var spinnerEnabled: Bool?

        public init(
            showToolRows: Bool = true,
            showCostSummary: Bool = true,
            showStatusLines: Bool = true,
            showRetryNotices: Bool = true,
            showCompactionNotices: Bool = true,
            colorEnabled: Bool? = nil,
            spinnerEnabled: Bool? = nil
        ) {
            self.showToolRows = showToolRows
            self.showCostSummary = showCostSummary
            self.showStatusLines = showStatusLines
            self.showRetryNotices = showRetryNotices
            self.showCompactionNotices = showCompactionNotices
            self.colorEnabled = colorEnabled
            self.spinnerEnabled = spinnerEnabled
        }

        public static let `default` = Config()
    }

    // MARK: - Private State

    private let config: Config
    private let style: StyledText
    private let useSpinner: Bool

    // --- Cursor tracking ---
    // We maintain a simple model: is the cursor at the very start of a line,
    // partway through a line, or sitting at the end of a "live" row that can
    // be overwritten with \r?
    private var cursorAtLineStart: Bool = true
    private var liveRow: LiveRow = .none

    // --- Stream-event book-keeping ---
    // Maps content-block index (from the Anthropic streaming protocol) to the
    // tool-use ID that block represents.
    private var indexToToolId: [Int: String] = [:]
    // Accumulates the partial JSON input for each in-flight tool call.
    private var toolInputBuffers: [String: String] = [:]
    // The tool name for each tool-use ID.
    private var toolNames: [String: String] = [:]
    // Pre-formatted display argument string extracted from the tool input JSON.
    private var toolDisplayArgs: [String: String] = [:]

    // --- Tool row display state ---
    // Ordered list of tool-use IDs we have emitted rows for (newest last).
    private var toolRowOrder: [String] = []
    // Per-tool row state (elapsed time, completion flag, display info).
    private var toolRowStates: [String: ToolRowState] = [:]
    // The tool whose row is currently being animated.
    private var liveToolId: String? = nil

    // --- Spinner animation ---
    private var spinnerFrame: Int = 0
    private var spinnerTask: Task<Void, Never>? = nil

    // MARK: - Supporting Types

    private enum LiveRow: Equatable {
        case none
        case status          // Transient status line — can be overwritten with \r
        case tool(id: String) // Animated tool row — finalize with \n before moving on
    }

    private struct ToolRowState {
        let toolId: String
        let toolName: String
        let displayArgs: String
        var elapsedSeconds: Double
        var isComplete: Bool
    }

    // MARK: - Initialisation

    public init(config: Config = .default) {
        self.config = config
        let isTTY = ANSI.isTTY
        self.style = StyledText(useColors: config.colorEnabled ?? isTTY)
        self.useSpinner = config.spinnerEnabled ?? isTTY
    }

    // MARK: - Public Entry Points

    /// Render a stream of ``SDKMessage`` values to stdout and return when the stream ends.
    ///
    /// This is the primary convenience static method. It creates a fresh renderer,
    /// processes every message in `stream`, then returns.
    ///
    /// - Parameters:
    ///   - stream: Any `AsyncSequence` of ``SDKMessage`` — typically a ``Query`` or
    ///     the sequence returned by ``Session/stream()``.
    ///   - config: Visual configuration.
    public static func run<S: AsyncSequence>(
        _ stream: S,
        config: Config = .default
    ) async throws where S.Element == SDKMessage {
        let renderer = TerminalRenderer(config: config)
        try await renderer.render(stream)
    }

    /// Render a stream of ``SDKMessage`` values to stdout.
    ///
    /// Unlike the static ``run(_:config:)`` entry point, calling this on an existing
    /// instance carries over internal state (tool tracking, cursor position) across
    /// multiple calls — useful for multi-turn sessions where you call
    /// ``Session/stream()`` repeatedly.
    ///
    /// - Parameter stream: Any `AsyncSequence` of ``SDKMessage``.
    public nonisolated func render<S: AsyncSequence>(_ stream: S) async throws where S.Element == SDKMessage {
        do {
            for try await message in stream {
                await handle(message)
            }
        } catch {
            await finish(error: error)
            throw error
        }
        await finish(error: nil)
    }

    // MARK: - Cleanup

    private func finish(error: Error?) {
        spinnerTask?.cancel()
        spinnerTask = nil

        // Ensure output ends on a clean new line
        switch liveRow {
        case .none:
            if !cursorAtLineStart { rawWrite("\n") }
        case .status:
            rawWrite(ANSI.crClear)
        case .tool(let id):
            if let state = toolRowStates[id], !state.isComplete {
                // Interrupted mid-execution — show final row without checkmark
                rawWrite("\n")
            }
        }
        cursorAtLineStart = true
        liveRow = .none

        if let error {
            printLine(style.boldRed("  ✗ Error: \(error.localizedDescription)"))
        }
    }

    // MARK: - Message Dispatch

    private func handle(_ message: SDKMessage) {
        switch message {
        case .streamEvent(let partial):
            handleStreamEvent(partial)
        case .assistant(let msg):
            handleAssistant(msg)
        case .user(let msg):
            handleUser(msg)
        case .userReplay:
            break  // Session replay — ignore for display
        case .toolProgress(let progress):
            handleToolProgress(progress)
        case .toolUseSummary(let summary):
            handleToolUseSummary(summary)
        case .system(let event):
            handleSystemEvent(event)
        case .rateLimitEvent(let event):
            handleRateLimit(event)
        case .authStatus(let auth):
            handleAuthStatus(auth)
        case .result(let result):
            handleResult(result)
        case .promptSuggestion:
            break
        }
    }

    // MARK: - Stream Events (Anthropic streaming protocol)

    private func handleStreamEvent(_ partial: SDKPartialAssistantMessage) {
        guard case .object(let obj) = partial.event,
              let typeStr = obj["type"]?.stringValue else { return }

        switch typeStr {

        case "content_block_start":
            guard let blockObj = obj["content_block"]?.objectValue,
                  let blockType = blockObj["type"]?.stringValue,
                  let index = obj["index"]?.intValue else { return }

            if blockType == "tool_use" {
                let toolId = blockObj["id"]?.stringValue ?? UUID().uuidString
                let toolName = blockObj["name"]?.stringValue ?? "tool"
                indexToToolId[index] = toolId
                toolNames[toolId] = toolName
                toolInputBuffers[toolId] = ""
                toolDisplayArgs[toolId] = ""
            }

        case "content_block_delta":
            guard let index = obj["index"]?.intValue,
                  let deltaObj = obj["delta"]?.objectValue,
                  let deltaType = deltaObj["type"]?.stringValue else { return }

            switch deltaType {
            case "text_delta":
                let text = deltaObj["text"]?.stringValue ?? ""
                if !text.isEmpty { appendStreamingText(text) }

            case "thinking_delta":
                // Extended thinking blocks — render dimmed
                let text = deltaObj["thinking"]?.stringValue ?? ""
                if !text.isEmpty { appendStreamingText(style.dim(text)) }

            case "input_json_delta":
                let partial = deltaObj["partial_json"]?.stringValue ?? ""
                if let toolId = indexToToolId[index] {
                    toolInputBuffers[toolId]? += partial
                }

            default:
                break
            }

        case "content_block_stop":
            guard let index = obj["index"]?.intValue,
                  let toolId = indexToToolId[index] else { return }
            // Tool input JSON is now complete — compute the display argument string.
            if let toolName = toolNames[toolId],
               let inputJson = toolInputBuffers[toolId] {
                toolDisplayArgs[toolId] = extractDisplayArgs(toolName: toolName, inputJson: inputJson)
            }

        case "message_delta":
            // Contains stop_reason — end of Claude's response for this turn.
            if !cursorAtLineStart {
                rawWrite("\n")
                cursorAtLineStart = true
                liveRow = .none
            }

        case "message_stop":
            // Belt-and-suspenders: ensure we end on a clean line.
            if !cursorAtLineStart {
                rawWrite("\n")
                cursorAtLineStart = true
                liveRow = .none
            }

        default:
            break
        }
    }

    // MARK: - Assistant Message

    private func handleAssistant(_ msg: SDKAssistantMessage) {
        // The complete assistant message arrives AFTER all its streamEvent chunks.
        // For text content we've already streamed, we skip re-printing.
        // We use this only to surface errors (e.g. rate limit, auth failures).
        if let error = msg.error {
            switch error {
            case .authenticationFailed:
                printLine(style.boldRed("  ✗ Authentication failed. Run `claude` to log in."))
            case .billingError:
                printLine(style.boldRed("  ✗ Billing error. Check your account at claude.ai."))
            case .rateLimit:
                // Usually preceded by a rateLimitEvent — suppress duplicate.
                break
            case .maxOutputTokens:
                printLine(style.yellow("  ⚠ Response truncated (max output tokens reached)."))
            case .invalidRequest:
                printLine(style.boldRed("  ✗ Invalid request."))
            case .serverError:
                printLine(style.boldRed("  ✗ Server error. Please try again."))
            case .unknown:
                break
            }
        }
    }

    // MARK: - User Message (tool results)

    private func handleUser(_ msg: SDKUserMessage) {
        // A user message whose parentToolUseId is set is a tool result.
        // This is the authoritative "tool completed" signal.
        if let toolUseId = msg.parentToolUseId {
            completeToolRow(toolUseId: toolUseId)
        }
    }

    // MARK: - Tool Progress

    private func handleToolProgress(_ progress: SDKToolProgressMessage) {
        guard config.showToolRows else { return }

        let toolId = progress.toolUseId
        let elapsed = progress.elapsedTimeSeconds

        if toolRowStates[toolId] != nil {
            // Already have a row — update elapsed time and refresh if it's live.
            toolRowStates[toolId]?.elapsedSeconds = elapsed
            if toolId == liveToolId, case .tool(let id) = liveRow, id == toolId {
                let state = toolRowStates[toolId]!
                rawWrite(ANSI.crClear + formatToolRow(state: state))
            }
        } else {
            // First progress event for this tool — create the row.
            let displayArgs = toolDisplayArgs[toolId] ?? ""
            let state = ToolRowState(
                toolId: toolId,
                toolName: progress.toolName,
                displayArgs: displayArgs,
                elapsedSeconds: elapsed,
                isComplete: false
            )
            toolRowStates[toolId] = state
            toolRowOrder.append(toolId)

            // If another tool is currently live, finalize it first.
            if case .tool(let currentId) = liveRow, currentId != toolId {
                finalizeCurrentLiveRow()
            }

            ensureAtLineStart()
            rawWrite(formatToolRow(state: state))
            cursorAtLineStart = false
            liveRow = .tool(id: toolId)
            liveToolId = toolId

            startSpinner()
        }
    }

    private func completeToolRow(toolUseId: String) {
        guard toolRowStates[toolUseId] != nil else { return }
        toolRowStates[toolUseId]?.isComplete = true

        if toolUseId == liveToolId, case .tool(let id) = liveRow, id == toolUseId {
            let state = toolRowStates[toolUseId]!
            rawWrite(ANSI.crClear + formatToolRow(state: state) + "\n")
            cursorAtLineStart = true
            liveRow = .none
            liveToolId = nil
            stopSpinner()
        }
    }

    // MARK: - Tool Use Summary

    private func handleToolUseSummary(_ summary: SDKToolUseSummaryMessage) {
        guard !summary.summary.isEmpty else { return }
        printLine(style.gray("  \(summary.summary)"))
    }

    // MARK: - System Events

    private func handleSystemEvent(_ event: SDKSystemEvent) {
        switch event {

        case .initialize:
            break  // Intentionally silent — init metadata is not user-visible output.

        case .status(let msg):
            guard config.showStatusLines, let status = msg.status, !status.isEmpty else { return }
            showStatusLine(status)

        case .apiRetry(let msg):
            guard config.showRetryNotices else { return }
            let delay = String(format: "%.1f", Double(msg.retryDelayMs) / 1000.0)
            let text = "  ↻ Retrying (attempt \(msg.attempt)/\(msg.maxRetries), wait \(delay)s)…"
            printLine(style.yellow(text))

        case .compactBoundary:
            guard config.showCompactionNotices else { return }
            printLine(style.gray("  ✦ Compressing context…"))

        case .taskStarted(let task):
            printLine(style.dim("  ⊕ " + task.description))

        case .taskProgress(let task):
            if let last = task.lastToolName {
                showStatusLine("Working… (\(last))")
            }

        case .taskNotification(let task):
            let icon = task.status == "completed" ? "✓" : "✗"
            let text = "  \(icon) \(task.summary)"
            if task.status == "completed" {
                printLine(style.green(text))
            } else {
                printLine(style.red(text))
            }

        case .localCommandOutput(let cmd):
            guard !cmd.content.isEmpty else { return }
            ensureAtLineStart()
            rawWrite(style.gray(cmd.content))
            cursorAtLineStart = cmd.content.hasSuffix("\n")

        case .hookStarted, .hookProgress, .hookResponse:
            break  // Internal hook lifecycle — not user-visible

        case .filesPersisted:
            break

        case .elicitationComplete:
            break
        }
    }

    // MARK: - Rate Limit

    private func handleRateLimit(_ event: SDKRateLimitEvent) {
        let info = event.rateLimitInfo
        var text = "  ⏸ Rate limited"
        if let resetsAt = info.resetsAt {
            let date = Date(timeIntervalSince1970: resetsAt)
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            text += " — resets at \(formatter.string(from: date))"
        }
        printLine(style.yellow(text))
    }

    // MARK: - Auth Status

    private func handleAuthStatus(_ auth: SDKAuthStatusMessage) {
        if auth.isAuthenticating {
            showStatusLine("Authenticating…")
        } else if let error = auth.error {
            printLine(style.boldRed("  ✗ Auth error: \(error)"))
        }
    }

    // MARK: - Result

    private func handleResult(_ result: SDKResultMessage) {
        switch result {
        case .success(let success):
            handleSuccess(success)
        case .error(let error):
            handleError(error)
        }
    }

    private func handleSuccess(_ success: SDKResultSuccess) {
        ensureAtLineStart()
        guard config.showCostSummary else { return }

        let totalTokens = success.usage.inputTokens + success.usage.outputTokens
        let durationSec = Double(success.durationMs) / 1000.0

        var parts: [String] = []
        if success.totalCostUsd > 0 {
            parts.append(formatCost(success.totalCostUsd))
        }
        parts.append(formatTokens(totalTokens))
        parts.append(String(format: "%.1fs", durationSec))

        let summary = parts.joined(separator: style.gray(" · "))
        printLine(style.gray("  ") + style.dim(summary))
    }

    private func handleError(_ error: SDKResultError) {
        ensureAtLineStart()
        let subtypeLabel: String
        switch error.subtype {
        case SDKResultErrorSubtype.errorMaxTurns.rawValue:
            subtypeLabel = "max turns reached"
        case SDKResultErrorSubtype.errorMaxBudgetUsd.rawValue:
            subtypeLabel = "budget limit reached"
        default:
            subtypeLabel = error.subtype
        }
        printLine(style.boldRed("  ✗ Stopped: \(subtypeLabel)"))
        for msg in error.errors {
            printLine(style.red("    \(msg)"))
        }

        if config.showCostSummary && error.totalCostUsd > 0 {
            let durationSec = Double(error.durationMs) / 1000.0
            let totalTokens = error.usage.inputTokens + error.usage.outputTokens
            printLine(style.gray("  \(formatCost(error.totalCostUsd)) · \(formatTokens(totalTokens)) · \(String(format: "%.1fs", durationSec))"))
        }
    }

    // MARK: - Spinner

    private func startSpinner() {
        guard useSpinner else { return }
        spinnerTask?.cancel()
        spinnerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(80))
                guard !Task.isCancelled else { break }
                await self?.tickSpinner()
            }
        }
    }

    private func stopSpinner() {
        spinnerTask?.cancel()
        spinnerTask = nil
    }

    /// Called by the spinner task on every animation frame.
    func tickSpinner() {
        spinnerFrame = (spinnerFrame + 1) % ANSI.spinnerFrames.count
        guard let toolId = liveToolId,
              case .tool(let id) = liveRow, id == toolId,
              let state = toolRowStates[toolId], !state.isComplete else { return }
        rawWrite(ANSI.crClear + formatToolRow(state: state))
    }

    // MARK: - Line / Cursor Helpers

    /// Write text to stdout without any formatting.
    private func rawWrite(_ text: String) {
        guard !text.isEmpty, let data = text.data(using: .utf8) else { return }
        FileHandle.standardOutput.write(data)
    }

    /// Append streaming text to the current line.
    private func appendStreamingText(_ text: String) {
        switch liveRow {
        case .status:
            // Clear the transient status line and start fresh text below it.
            rawWrite(ANSI.crClear)
            cursorAtLineStart = true
            liveRow = .none
        case .tool:
            // Streaming text appearing after tool rows: move to the next line.
            finalizeCurrentLiveRow()
        case .none:
            break
        }
        rawWrite(text)
        if let last = text.last {
            cursorAtLineStart = (last == "\n")
        } else {
            cursorAtLineStart = false
        }
        liveRow = .none
    }

    /// Print a full line followed by a newline, correctly handling the current cursor state.
    private func printLine(_ text: String) {
        ensureAtLineStart()
        rawWrite(text + "\n")
        cursorAtLineStart = true
        liveRow = .none
    }

    /// Display a transient status line (e.g. "Thinking…") that will be overwritten by the
    /// next real content. If a status line is already live, replace it in-place.
    private func showStatusLine(_ text: String) {
        let formatted = style.dim("  \(text)")
        switch liveRow {
        case .status:
            rawWrite(ANSI.crClear + formatted)
        case .tool:
            finalizeCurrentLiveRow()
            rawWrite(formatted)
        case .none:
            ensureAtLineStart()
            rawWrite(formatted)
        }
        cursorAtLineStart = false
        liveRow = .status
    }

    /// Ensure the cursor is at the start of a new line, handling any live row appropriately.
    private func ensureAtLineStart() {
        switch liveRow {
        case .none:
            if !cursorAtLineStart {
                rawWrite("\n")
                cursorAtLineStart = true
            }
        case .status:
            rawWrite(ANSI.crClear)
            cursorAtLineStart = true
            liveRow = .none
        case .tool:
            finalizeCurrentLiveRow()
        }
    }

    /// Finalize (end) the currently live tool row by printing a newline after it.
    /// The row stays visible on screen in its last spinner/checkmark state.
    private func finalizeCurrentLiveRow() {
        rawWrite("\n")
        cursorAtLineStart = true
        liveRow = .none
        // Do NOT clear liveToolId here — that is only cleared when the tool actually
        // completes (i.e., we receive the user message with the tool result).
    }

    // MARK: - Tool Row Formatting

    private func formatToolRow(state: ToolRowState) -> String {
        let icon: String
        if state.isComplete {
            icon = style.boldGreen("✓")
        } else {
            let frame = ANSI.spinnerFrames[spinnerFrame]
            icon = style.boldCyan(frame)
        }
        let name = style.bold(state.toolName)
        let args = state.displayArgs.isEmpty ? "" : style.dim("(\(state.displayArgs))")
        let elapsed = style.gray(String(format: " · %.1fs", state.elapsedSeconds))
        return "  \(icon) \(name)\(args)\(elapsed)"
    }

    // MARK: - Tool Argument Extraction

    /// Extract a human-readable argument summary from a tool's JSON input.
    private func extractDisplayArgs(toolName: String, inputJson: String) -> String {
        guard !inputJson.isEmpty,
              let data = inputJson.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(AnyCodable.self, from: data),
              case .object(let dict) = decoded else { return "" }

        let toolLower = toolName.lowercased()

        // Shell execution
        if toolLower.contains("bash") || toolLower == "execute_bash" || toolLower == "shell" {
            if let cmd = dict["command"]?.stringValue ?? dict["cmd"]?.stringValue {
                return truncate(cmd, to: 60)
            }
        }

        // Web fetch / search
        if toolLower.contains("web") || toolLower.contains("fetch") || toolLower.contains("search") {
            if let url = dict["url"]?.stringValue { return truncate(url, to: 60) }
            if let query = dict["query"]?.stringValue { return truncate(query, to: 50) }
        }

        // File path keys (Read, Write, Edit, Glob, etc.)
        for key in ["path", "file_path", "filename", "file", "target_file"] {
            if let val = dict[key]?.stringValue { return val }
        }

        // Pattern / query keys (Grep, Glob)
        for key in ["pattern", "regex", "glob", "query"] {
            if let val = dict[key]?.stringValue { return truncate(val, to: 50) }
        }

        // URL
        if let url = dict["url"]?.stringValue { return truncate(url, to: 60) }

        // Fallback: first non-empty string value in the dict
        for (_, val) in dict {
            if let str = val.stringValue, !str.isEmpty {
                return truncate(str, to: 40)
            }
        }

        return ""
    }

    private func truncate(_ str: String, to maxLen: Int) -> String {
        guard str.count > maxLen else { return str }
        return String(str.prefix(maxLen)) + "…"
    }

    // MARK: - Formatting Helpers

    private func formatCost(_ usd: Double) -> String {
        if usd < 0.01 {
            return String(format: "$%.4f", usd)
        } else {
            return String(format: "$%.2f", usd)
        }
    }

    private func formatTokens(_ count: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return (formatter.string(from: NSNumber(value: count)) ?? "\(count)") + " tokens"
    }
}

// MARK: - AgentEvent Rendering (Native Loop)

extension TerminalRenderer {

    /// Render a stream of ``AgentEvent`` values emitted by the native ``AgentLoop``.
    ///
    /// This overload provides the same rich terminal experience as the SDK message
    /// renderer, but consumes events from the native Swift implementation that makes
    /// direct Anthropic API calls without the `claude` binary.
    ///
    /// ```swift
    /// let agent = try ClaudeAgent()
    /// let renderer = TerminalRenderer()
    /// try await renderer.render(agent.run("List files in the repo"))
    /// ```
    public nonisolated func render<S: AsyncSequence>(_ stream: S) async throws where S.Element == AgentEvent {
        do {
            for try await event in stream {
                await handleAgentEvent(event)
            }
        } catch {
            await finish(error: error)
            throw error
        }
        await finish(error: nil)
    }

    // MARK: - AgentEvent dispatch

    private func handleAgentEvent(_ event: AgentEvent) {
        switch event {
        case .textDelta(let text):
            if !text.isEmpty { appendStreamingText(text) }

        case .thinkingDelta(let text):
            if !text.isEmpty { appendStreamingText(style.dim(text)) }

        case .toolUseStarted(let id, let name, let input):
            guard config.showToolRows else { return }
            handleAgentToolStarted(id: id, name: name, input: input)

        case .toolProgress(let id, let name, let elapsed):
            guard config.showToolRows else { return }
            handleAgentToolProgress(id: id, name: name, elapsedSeconds: elapsed)

        case .toolResult(let id, let name, _, let isError, let durationMs):
            guard config.showToolRows else { return }
            handleAgentToolResult(id: id, name: name, isError: isError, durationMs: durationMs)

        case .status(let text):
            guard config.showStatusLines, !text.isEmpty else { return }
            showStatusLine(text)

        case .contextCompaction:
            guard config.showCompactionNotices else { return }
            printLine(style.gray("  ✦ Compressing context…"))

        case .apiRetry(let attempt, let maxAttempts, let delaySeconds):
            guard config.showRetryNotices else { return }
            let delay = String(format: "%.1f", delaySeconds)
            printLine(style.yellow("  ↻ Retrying (attempt \(attempt)/\(maxAttempts), wait \(delay)s)…"))

        case .rateLimited(let resetsAt):
            var text = "  ⏸ Rate limited"
            if let date = resetsAt {
                let formatter = DateFormatter()
                formatter.dateFormat = "HH:mm:ss"
                text += " — resets at \(formatter.string(from: date))"
            }
            printLine(style.yellow(text))

        case .completed(let stats):
            ensureAtLineStart()
            guard config.showCostSummary else { return }
            let durationSec = Double(stats.durationMs) / 1000.0
            var parts: [String] = []
            if stats.estimatedCostUsd > 0 {
                parts.append(formatCost(stats.estimatedCostUsd))
            }
            parts.append(formatTokens(stats.totalTokens))
            parts.append(String(format: "%.1fs", durationSec))
            let summary = parts.joined(separator: style.gray(" · "))
            printLine(style.gray("  ") + style.dim(summary))

        case .failed(let reason, let errors):
            ensureAtLineStart()
            printLine(style.boldRed("  ✗ Stopped: \(reason)"))
            for msg in errors { printLine(style.red("    \(msg)")) }
        }
    }

    // MARK: - Native tool row handlers

    private func handleAgentToolStarted(id: String, name: String, input: [String: AnyCodable]) {
        let displayArgs = computeDisplayArgs(toolName: name, input: input)

        let state = ToolRowState(
            toolId: id,
            toolName: name,
            displayArgs: displayArgs,
            elapsedSeconds: 0,
            isComplete: false
        )
        toolRowStates[id] = state
        toolRowOrder.append(id)

        if case .tool(let currentId) = liveRow, currentId != id {
            finalizeCurrentLiveRow()
        }

        ensureAtLineStart()
        rawWrite(formatToolRow(state: state))
        cursorAtLineStart = false
        liveRow = .tool(id: id)
        liveToolId = id

        startSpinner()
    }

    private func handleAgentToolProgress(id: String, name: String, elapsedSeconds: Double) {
        if toolRowStates[id] != nil {
            toolRowStates[id]?.elapsedSeconds = elapsedSeconds
            if id == liveToolId, case .tool(let lid) = liveRow, lid == id,
               let state = toolRowStates[id], !state.isComplete {
                rawWrite(ANSI.crClear + formatToolRow(state: state))
            }
        } else {
            // Received progress before started — create the row now
            handleAgentToolStarted(id: id, name: name, input: [:])
            toolRowStates[id]?.elapsedSeconds = elapsedSeconds
        }
    }

    private func handleAgentToolResult(id: String, name: String, isError: Bool, durationMs: Int) {
        if toolRowStates[id] == nil {
            handleAgentToolStarted(id: id, name: name, input: [:])
        }
        toolRowStates[id]?.isComplete = true
        toolRowStates[id]?.elapsedSeconds = Double(durationMs) / 1000.0

        if id == liveToolId, case .tool(let lid) = liveRow, lid == id,
           let state = toolRowStates[id] {
            rawWrite(ANSI.crClear + formatToolRow(state: state) + "\n")
            cursorAtLineStart = true
            liveRow = .none
            liveToolId = nil
            stopSpinner()
        }
    }

    // MARK: - Display arg computation from [String: AnyCodable]

    private func computeDisplayArgs(toolName: String, input: [String: AnyCodable]) -> String {
        let toolLower = toolName.lowercased()

        if toolLower.contains("bash") || toolLower == "shell" || toolLower == "execute_bash" {
            if let cmd = input["command"]?.stringValue ?? input["cmd"]?.stringValue {
                return truncate(cmd, to: 60)
            }
        }
        if toolLower.contains("web") || toolLower.contains("fetch") || toolLower.contains("search") {
            if let url = input["url"]?.stringValue { return truncate(url, to: 60) }
            if let q = input["query"]?.stringValue { return truncate(q, to: 50) }
        }
        for key in ["path", "file_path", "filename", "file", "target_file"] {
            if let val = input[key]?.stringValue { return val }
        }
        for key in ["pattern", "regex", "glob", "query"] {
            if let val = input[key]?.stringValue { return truncate(val, to: 50) }
        }
        if let url = input["url"]?.stringValue { return truncate(url, to: 60) }
        for (_, val) in input {
            if let str = val.stringValue, !str.isEmpty { return truncate(str, to: 40) }
        }
        return ""
    }
}

// MARK: - ClaudeAgentSDK Convenience

extension ClaudeAgentSDK {

    // MARK: - Terminal Rendering

    /// Run a one-shot prompt and render the response to the terminal using ``TerminalRenderer``.
    ///
    /// This is the Swift equivalent of running `claude "prompt"` directly in the terminal.
    /// Streaming text, tool-execution rows, and a cost summary are all rendered automatically.
    ///
    /// ```swift
    /// try await ClaudeAgentSDK.runInTerminal(
    ///     prompt: "What's in the current directory?",
    ///     options: Options(model: "claude-sonnet-4-6")
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - prompt: The prompt to send to Claude.
    ///   - options: Query options (model, tools, permissions, etc.).
    ///   - rendererConfig: Visual configuration for the terminal renderer.
    public static func runInTerminal(
        prompt: String,
        options: Options = Options(),
        rendererConfig: TerminalRenderer.Config = .default
    ) async throws {
        let query = try query(prompt: prompt, options: options)
        try await TerminalRenderer.run(query, config: rendererConfig)
    }

    /// Run a multi-turn session loop in the terminal, reading prompts from stdin.
    ///
    /// This replicates the interactive `claude` REPL experience.  Each prompt is
    /// read from stdin, sent to Claude, and the response is rendered via
    /// ``TerminalRenderer``.  Type `exit` or send EOF (Ctrl-D) to quit.
    ///
    /// ```swift
    /// try await ClaudeAgentSDK.runInteractiveTerminal(
    ///     options: SessionOptions(model: "claude-sonnet-4-6")
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - options: Session options (model is required).
    ///   - rendererConfig: Visual configuration.
    ///   - inputPrompt: The REPL prompt shown to the user (default: `"> "`).
    public static func runInteractiveTerminal(
        options: SessionOptions,
        rendererConfig: TerminalRenderer.Config = .default,
        inputPrompt: String = "> "
    ) async throws {
        #if os(macOS)
        let session = try createSession(options: options)
        let renderer = TerminalRenderer(config: rendererConfig)
        defer { session.close() }

        let isTTY = ANSI.isTTY
        while true {
            if isTTY {
                if let data = inputPrompt.data(using: .utf8) {
                    FileHandle.standardOutput.write(data)
                }
            }
            guard let line = readLine(strippingNewline: true) else { break }  // EOF
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if trimmed.lowercased() == "exit" || trimmed.lowercased() == "quit" { break }

            try await session.send(trimmed)
            try await renderer.render(session.stream())
            print()  // Blank line between turns
        }
        #else
        throw ClaudeAgentSDKError.unsupportedPlatform
        #endif
    }
}
