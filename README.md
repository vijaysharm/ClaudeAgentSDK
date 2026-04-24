# Claude Agent SDK for Swift

A Swift Package Manager library for building Claude-powered agents in Swift. Two independent approaches are provided:

| Approach | API | Requires |
|---|---|---|
| **Native** | `ClaudeAgent` | Anthropic API key |
| **CLI wrapper** | `ClaudeAgentSDK.query()` / `Session` | `claude` binary |

Both expose an `AsyncSequence`-based streaming API and share the same `TerminalRenderer` for a rich terminal experience.

---

## Requirements

- **Swift 6.0+** (strict concurrency enforced)
- **macOS 15+** (process spawning via `Foundation.Process`)
- **iOS 18+** (types compile; process spawning is unavailable)

The **native** path additionally requires an Anthropic API key (`ANTHROPIC_API_KEY` env var or `AgentOptions.apiKey`).
The **CLI wrapper** path additionally requires the [Claude Code CLI](https://claude.ai/download) (`claude` binary).

## Installation

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/vijaysharm/ClaudeAgentSDK.git", from: "0.1.0"),
],
targets: [
    .target(name: "MyApp", dependencies: [
        .product(name: "ClaudeAgentSDK", package: "ClaudeAgentSDK"),
    ])
]
```

---

## Native Agent (`ClaudeAgent`)

Makes direct Anthropic API calls — **no `claude` binary required**. Implements the full agentic loop: streaming, tool execution, retries, and conversation history.

### Quick Start

```swift
import ClaudeAgentSDK

// ANTHROPIC_API_KEY is read from the environment automatically
let agent = try ClaudeAgent()

for try await event in agent.run("What Swift files are in this directory?") {
    switch event {
    case .textDelta(let text):
        print(text, terminator: "")
    case .toolUseStarted(_, let name, _):
        print("\n⠋ \(name)…", terminator: "")
    case .toolResult(_, let name, _, _, _):
        print("\r✓ \(name)   ")
    case .completed(let stats):
        print("\n$\(String(format: "%.4f", stats.estimatedCostUsd)) · \(stats.totalTokens) tokens")
    default:
        break
    }
}
```

### Terminal Rendering (Built-in)

`TerminalRenderer` gives a full Claude Code–style terminal experience with animated spinners, tool rows, and cost summary. No extra code needed:

```swift
let agent = try ClaudeAgent()
try await agent.runInTerminal("Refactor the authentication module")
```

Output:

```
The authentication module currently uses…
  ⠹ read_file(Sources/Auth/Auth.swift) · 0.3s
  ✓ read_file(Sources/Auth/Auth.swift) · 0.4s
  ⠼ edit_file(Sources/Auth/Auth.swift) · 0.1s
  ✓ edit_file(Sources/Auth/Auth.swift) · 0.6s
Here's what I changed…
  $0.0031 · 2,847 tokens · 3.2s
```

### Interactive REPL

```swift
let agent = try ClaudeAgent()
try await agent.runInteractiveTerminal()
// > What does Package.swift depend on?
// ...
// > Now explain the transport layer
// ...   (conversation history is kept between turns)
// > exit
```

### Consuming `AgentEvent` Directly

```swift
let agent = try ClaudeAgent()

for try await event in agent.run("Summarize the codebase") {
    switch event {
    case .textDelta(let chunk):
        print(chunk, terminator: "")

    case .thinkingDelta(let thought):
        // Extended thinking / reasoning blocks (when enabled)
        break

    case .toolUseStarted(let id, let name, let input):
        print("\nCalling \(name) with \(input)")

    case .toolProgress(let id, let name, let elapsed):
        print("\r\(name) running… \(String(format: "%.1fs", elapsed))", terminator: "")

    case .toolResult(let id, let name, let output, let isError, let ms):
        print("\n\(name) finished in \(ms)ms: \(output.prefix(100))")

    case .status(let text):
        print("[\(text)]")

    case .apiRetry(let attempt, let max, let delay):
        print("Retry \(attempt)/\(max) in \(delay)s…")

    case .rateLimited(let resetsAt):
        print("Rate limited" + (resetsAt.map { " until \($0)" } ?? ""))

    case .completed(let stats):
        print("""
            Done in \(stats.numTurns) turn(s):
              Input:  \(stats.inputTokens) tokens
              Output: \(stats.outputTokens) tokens
              Cost:   $\(String(format: "%.4f", stats.estimatedCostUsd))
              Time:   \(stats.durationMs)ms
            """)

    case .failed(let reason, let errors):
        print("Failed: \(reason)")
        errors.forEach { print("  - \($0)") }

    case .contextCompaction:
        print("Context compacted")
    }
}
```

### Configuration

```swift
let agent = try ClaudeAgent(options: AgentOptions(
    model: "claude-opus-4-7",
    maxTokens: 16_384,
    apiKey: "sk-ant-...",          // or set ANTHROPIC_API_KEY
    maxRetries: 5,
    tools: [BashTool(), ReadFileTool(), WebFetchTool()],   // custom tool subset
    workingDirectory: "/path/to/project",
    maxTurns: 20,
    systemPrompt: "You are a senior Swift engineer. Prefer value types.",
    thinkingEnabled: true,
    thinkingBudgetTokens: 10_000,
    permissionMode: .default       // .readOnly | .bypassPermissions
))
```

### Custom Tools

```swift
struct DatabaseQueryTool: AgentTool {
    let name = "query_db"
    let description = "Run a read-only SQL query against the app database."

    let inputSchema: AnyCodable = .object([
        "type": "object",
        "properties": .object([
            "sql": .object(["type": "string", "description": "SELECT statement to execute"])
        ]),
        "required": .array([.string("sql")])
    ])

    func execute(input: [String: AnyCodable], context: ToolContext) async throws -> ToolOutput {
        guard let sql = input["sql"]?.stringValue else {
            return .error("Missing sql parameter")
        }
        // Run against your actual database
        let rows = try await myDatabase.query(sql)
        return ToolOutput(content: rows.description)
    }
}

let agent = try ClaudeAgent(options: AgentOptions(
    tools: [DatabaseQueryTool()] + defaultAgentTools()
))
```

### Built-in Tools

| Tool | Name | Description |
|------|------|-------------|
| `BashTool` | `bash` | Run shell commands via `/bin/bash -c` (macOS only) |
| `ReadFileTool` | `read_file` | Read a file with line numbers, offset, and limit |
| `WriteFileTool` | `write_file` | Create or overwrite a file |
| `EditFileTool` | `edit_file` | Exact-string replacement within a file |
| `GlobTool` | `glob` | Find files by pattern (e.g. `**/*.swift`) |
| `GrepTool` | `grep` | Regex search across files |
| `WebFetchTool` | `web_fetch` | Fetch a URL and return stripped text |

---

## CLI Wrapper (`ClaudeAgentSDK`)

Wraps the `claude` binary via subprocess. Gives access to all Claude Code features including hooks, MCP servers, agents, and persistent sessions.

### Quick Start

```swift
import ClaudeAgentSDK

let query = try ClaudeAgentSDK.query(
    prompt: "What files are in the current directory?",
    options: Options(model: "claude-sonnet-4-6")
)

for try await message in query {
    if case let .result(.success(result)) = message {
        print(result.result)
    }
}
```

### Terminal Rendering

```swift
try await ClaudeAgentSDK.runInTerminal(
    prompt: "Review the test coverage",
    options: Options(model: "claude-sonnet-4-6")
)
```

Interactive REPL:

```swift
try await ClaudeAgentSDK.runInteractiveTerminal(
    options: SessionOptions(model: "claude-sonnet-4-6")
)
```

### Multi-turn Sessions

```swift
let session = try ClaudeAgentSDK.createSession(
    options: SessionOptions(model: "claude-sonnet-4-6")
)

// Turn 1
try await session.send("What is 2 + 2?")
for try await message in session.stream() {
    if case let .result(.success(result)) = message {
        print(result.result) // "4"
    }
}

// Turn 2 — context is maintained
try await session.send("Multiply that by 10")
for try await message in session.stream() {
    if case let .result(.success(result)) = message {
        print(result.result) // "40"
    }
}

session.close()
```

### One-shot Prompt

```swift
let result = try await ClaudeAgentSDK.prompt(
    "What is the capital of France?",
    options: SessionOptions(model: "claude-sonnet-4-6")
)

if case let .success(r) = result {
    print(r.result) // "Paris"
}
```

### Resume a Session

```swift
let session = try ClaudeAgentSDK.resumeSession(
    "existing-session-uuid",
    options: SessionOptions(model: "claude-sonnet-4-6")
)
try await session.send("Continue where we left off")
for try await message in session.stream() { ... }
```

### Streaming Input

```swift
let query = try ClaudeAgentSDK.queryStreaming(options: Options(maxTurns: 1))

try await query.sendMessage("What is 3 + 3?")
query.endInput()

for try await message in query {
    if case let .result(.success(result)) = message {
        print(result.result) // "6"
    }
}
```

Or feed from an `AsyncStream`:

```swift
let (stream, continuation) = AsyncStream<SDKUserMessage>.makeStream()
let query = try ClaudeAgentSDK.query(prompt: stream, options: Options())

continuation.yield(SDKUserMessage.text("Hello"))
continuation.finish()

for try await message in query { ... }
```

### Handling All Message Types

```swift
for try await message in query {
    switch message {
    case let .system(.initialize(msg)):
        print("Session started: model=\(msg.model)")
    case let .system(.status(msg)):
        print("Status: \(msg.status ?? "")")
    case let .system(.apiRetry(msg)):
        print("Retrying (attempt \(msg.attempt)/\(msg.maxRetries))…")
    case let .system(.taskStarted(msg)):
        print("Task started: \(msg.description)")
    case let .assistant(msg):
        // Full Anthropic API response object
        break
    case let .streamEvent(partial):
        // Incremental streaming event
        break
    case let .toolProgress(msg):
        print("\(msg.toolName): \(msg.elapsedTimeSeconds)s")
    case let .rateLimitEvent(msg):
        print("Rate limited, resets at: \(msg.rateLimitInfo.resetsAt ?? 0)")
    case let .result(.success(result)):
        print("Done: \(result.result)")
        print("Cost: $\(result.totalCostUsd) · \(result.durationMs)ms")
    case let .result(.error(error)):
        print("Error (\(error.subtype)): \(error.errors.joined(separator: ", "))")
    default:
        break
    }
}
```

### Configuration

```swift
let options = Options(
    model: "claude-opus-4-7",
    cwd: "/path/to/project",
    systemPrompt: .presetWithAppend("Always explain your reasoning."),
    permissionMode: .acceptEdits,
    allowedTools: ["Read", "Grep", "Glob"],
    disallowedTools: ["Bash"],
    maxTurns: 10,
    maxBudgetUsd: 1.0,
    thinking: .adaptive,
    effort: .high,
    continueSession: true,
    env: ["MY_VAR": "value"],
    stderr: { line in print("[stderr] \(line)") },
    pathToClaudeCodeExecutable: "\(NSHomeDirectory())/.local/bin/claude"
)
```

### Permission Handling

```swift
let options = Options(
    canUseTool: { toolName, input, options in
        // Allow read-only tools automatically
        if ["Read", "Glob", "Grep"].contains(toolName) {
            return .allow()
        }
        // Block destructive shell commands
        if toolName == "Bash",
           let cmd = input["command"]?.stringValue,
           cmd.contains("rm ") {
            return .deny(message: "Destructive commands are not allowed")
        }
        return .allow()
    }
)
```

### Control Methods

```swift
let query = try ClaudeAgentSDK.query(prompt: "…", options: options)

try await query.interrupt()           // Interrupt current execution
try await query.setModel("claude-opus-4-7")
try await query.setPermissionMode(.acceptEdits)
try await query.sendMessage("Follow-up")
query.endInput()                      // Close stdin
query.close()                         // Terminate
```

### Structured Output

```swift
let options = Options(
    outputFormat: .jsonSchema([
        "type": "object",
        "properties": [
            "summary": ["type": "string"],
            "issues": ["type": "array", "items": ["type": "string"]]
        ],
        "required": ["summary", "issues"]
    ])
)
```

### MCP Servers

```swift
let options = Options(
    mcpServers: [
        "local-tools": .stdio(McpStdioServerConfig(
            command: "node",
            args: ["./mcp-server.js"]
        )),
        "remote": .http(McpHttpServerConfig(
            url: "https://mcp.example.com",
            headers: ["Authorization": "Bearer \(token)"]
        ))
    ]
)
```

### Session Management

```swift
// List recent sessions
let sessions = try await ClaudeAgentSDK.listSessions(
    options: ListSessionsOptions(limit: 10)
)
for session in sessions {
    print("\(session.sessionId): \(session.summary)")
}

// Rename / tag
try await ClaudeAgentSDK.renameSession("session-uuid", title: "Auth Refactor")
try await ClaudeAgentSDK.tagSession("session-uuid", tag: "important")

// Fork from a specific message
let fork = try await ClaudeAgentSDK.forkSession(
    "session-uuid",
    upToMessageId: "message-uuid",
    title: "Alternative approach"
)
```

---

## Terminal Renderer

Both paths share `TerminalRenderer`, which replicates the Claude Code CLI's visual style:

```swift
// Use with native agent
let renderer = TerminalRenderer()
try await renderer.render(agent.run("Explain the auth module"))

// Use with CLI wrapper
let renderer = TerminalRenderer()
try await renderer.render(session.stream())

// Static convenience (creates a new renderer internally)
try await TerminalRenderer.run(query)
```

### Configuration

```swift
let config = TerminalRenderer.Config(
    showToolRows: true,         // Spinner rows for each tool call
    showCostSummary: true,      // "$0.0023 · 1,847 tokens · 4.1s" at the end
    showStatusLines: true,      // Transient "Thinking…" status
    showRetryNotices: true,     // "↻ Retrying (attempt 1/3, wait 2.0s)…"
    showCompactionNotices: true, // "✦ Compressing context…"
    colorEnabled: true,         // nil = auto-detect from TTY
    spinnerEnabled: true        // nil = auto-detect from TTY
)

try await TerminalRenderer.run(query, config: config)
```

---

## Platform Support

| Feature | macOS 15+ | iOS 18+ |
|---|:-:|:-:|
| `ClaudeAgent` (native) | ✓ | ✓ |
| `BashTool` | ✓ | — |
| File/web tools | ✓ | ✓ |
| `TerminalRenderer` | ✓ | — |
| `ClaudeAgentSDK.query()` | ✓ | — |
| `ClaudeAgentSDK.createSession()` | ✓ | — |
| All types & models | ✓ | ✓ |

On iOS, `ClaudeAgent` works for text/file/web tasks. `BashTool`, `TerminalRenderer`, and the CLI wrapper throw `ClaudeAgentSDKError.unsupportedPlatform`.

---

## Architecture

### Component Diagram

```
╔══════════════════════════════════════════════════════════════════════════╗
║                         Your Swift Application                           ║
╚════════════════════╤════════════════════════╤════════════════════════════╝
                     │                        │
          ┌──────────▼──────────┐   ┌─────────▼──────────┐
          │    ClaudeAgent      │   │  ClaudeAgentSDK     │
          │  (native / direct)  │   │  (CLI wrapper)      │
          └──────────┬──────────┘   └─────────┬──────────┘
                     │                        │
          ┌──────────▼──────────┐   ┌─────────▼──────────┐
          │  AgentLoop (actor)  │   │    Query / Session  │
          │                     │   │                     │
          │  • conversation     │   │  • AsyncSequence    │
          │    history          │   │    of SDKMessage    │
          │  • retry logic      │   │  • control methods  │
          │  • while(true) loop │   │    (interrupt, etc) │
          └──┬───────────────┬──┘   └─────────┬──────────┘
             │               │                │
    ┌────────▼───────┐  ┌────▼────────┐  ┌───▼────────────────┐
    │ AnthropicClient│  │  Tool Layer │  │  ProcessTransport   │
    │                │  │             │  │                     │
    │ URLSession SSE │  │ BashTool    │  │  Foundation.Process │
    │ SSEParser /    │  │ ReadFileTool│  │  stdin  → JSON cmds │
    │ LineAccumulator│  │ WriteFile   │  │  stdout ← JSON msgs │
    └────────┬───────┘  │ EditFile   │  └───────────┬─────────┘
             │          │ GlobTool   │              │
             │          │ GrepTool   │         ┌────▼────────────┐
    ┌────────▼───────┐  │ WebFetch   │         │   claude CLI    │
    │ Anthropic API  │  │ (custom…)  │         │   subprocess    │
    │ api.anthropic  │  └─────────── ┘         │                 │
    │ .com/v1/       │                          │  • agentic loop │
    │ messages       │                          │  • tool calls   │
    └────────────────┘                          │  • MCP servers  │
                                                │  • hooks        │
                                                └─────────────────┘

         ↓ AgentEvent stream           ↓ SDKMessage stream
╔════════════════════════════════════════════════════════════════════╗
║                       TerminalRenderer (actor)                     ║
║                                                                    ║
║  .textDelta      → stream to stdout                                ║
║  .toolUseStarted → print spinner row  ⠹ read_file(…) · 0.0s       ║
║  .toolProgress   → update in-place   ⠼ read_file(…) · 0.4s        ║
║  .toolResult     → finalize row      ✓ read_file(…) · 0.6s        ║
║  .status         → transient line (overwritten by next event)      ║
║  .apiRetry       → ↻ Retrying (attempt 1/3, wait 2.0s)…           ║
║  .rateLimited    → ⏸ Rate limited — resets at 14:32:00            ║
║  .completed      → $0.0031 · 2,847 tokens · 3.2s                  ║
╚════════════════════════════════════════════════════════════════════╝
```

### Native Agent — Data Flow

```
run("Refactor auth module")
        │
        ▼
  AgentLoop.runLoop()
        │
        ├─── POST /v1/messages ──────────────────────────────────────────▶ Anthropic API
        │         SSE stream                                              (streaming)
        │    ◀────────────────────────────────────────────────────────────
        │    message_start → content_block_start(text) → text_delta × N
        │    → content_block_stop → content_block_start(tool_use)
        │    → input_json_delta × N → content_block_stop → message_stop
        │
        ├─── yield .textDelta("The auth module currently…")
        ├─── yield .toolUseStarted("bash", {command: "ls Sources/"})
        │
        ├─── tool.execute() ──────────────────────────────────────────────▶  /bin/bash
        │    (500ms timer → yield .toolProgress every tick)              ◀────────────
        │
        ├─── yield .toolResult("bash", output, durationMs: 420)
        │
        ├─── append tool result to history
        │
        └─── POST /v1/messages (next turn with tool results in history)
             … repeat until no tool calls …
             yield .completed(AgentStats)
```

### CLI Wrapper — Data Flow

```
query(prompt: "…", options: options)
        │
        ▼
  ProcessTransport  ──── spawn ────────────────────────────▶  claude [args]
        │                                                           │
        │  write stdin: {"type":"user","message":{"role":…}}       │
        │                                                           │ processes &
        │  read stdout (newline-delimited JSON):                    │ streams JSON
        │  {"type":"system","subtype":"init",…}                    │
        │  {"type":"assistant","message":{…},"partial":true}       │
        │  {"type":"tool_progress",…}                               │
        │  {"type":"result","subtype":"success",…}  ◀──────────────┘
        │
        ▼
  Query (AsyncSequence<SDKMessage>)
        │
        ▼
  TerminalRenderer  or  your for-try-await loop
```

### Key Types

| Type | Description |
|------|-------------|
| `ClaudeAgent` | Native entry point — direct Anthropic API, no binary |
| `AgentLoop` | Actor implementing the agentic `while(true)` loop |
| `AgentEvent` | Events emitted by the native loop |
| `AgentOptions` | Configuration for the native agent |
| `AgentTool` | Protocol for custom tool implementations |
| `TerminalRenderer` | Actor that renders either path to the terminal |
| `ClaudeAgentSDK` | CLI wrapper entry point |
| `Query` | `AsyncSequence<SDKMessage>` with control methods |
| `Session` | Multi-turn CLI session with `send()`/`stream()` |
| `Options` / `SessionOptions` | Configuration for the CLI wrapper |
| `SDKMessage` | Discriminated enum of all CLI message types |
| `AnyCodable` | Type-erased JSON value (`Sendable`, recursive enum) |

### Concurrency

The library is built for Swift 6 strict concurrency:

- All public types are `Sendable`
- `AnyCodable` uses a recursive enum (not `Any`) for full `Sendable` conformance
- `AgentLoop` and `TerminalRenderer` are `actor` types — zero data races under the strict concurrency checker
- `Query` and `Session` use `@unchecked Sendable` with internal `NSLock` synchronisation
- Callbacks are typed as `@Sendable`

## License

See [LICENSE](LICENSE) for details.
