# Claude Agent SDK for Swift

A Swift Package Manager library that provides programmatic access to Claude Code's capabilities. Build autonomous agents that can understand codebases, edit files, run commands, and execute complex workflows — all from Swift.

This is a Swift port of Anthropic's official [TypeScript Claude Agent SDK](https://www.npmjs.com/package/@anthropic-ai/claude-agent-sdk), wrapping the Claude Code CLI.

## Requirements

- **Swift 6.0+** (strict concurrency enforced)
- **macOS 15+** (process spawning via `Foundation.Process`)
- **iOS 18+** (types compile; process spawning is unavailable — see [Platform Support](#platform-support))
- **Claude Code CLI** installed (`claude` binary)

## Installation

Add the package to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/vijaysharm/ClaudeAgentSDK.git", from: "0.1.0"),
]
```

Then add the dependency to your target:

```swift
.target(
    name: "MyApp",
    dependencies: [
        .product(name: "ClaudeAgentSDK", package: "ClaudeAgentSDK"),
    ]
)
```

## Quick Start

```swift
import ClaudeAgentSDK

let query = try ClaudeAgentSDK.query(
    prompt: "What files are in the current directory?",
    options: Options(model: "claude-sonnet-4-6")
)

for try await message in query {
    switch message {
    case let .result(.success(result)):
        print(result.result)
    default:
        break
    }
}
```

## Usage

### Basic Query

The primary entry point is `ClaudeAgentSDK.query()`, which spawns the Claude Code CLI and returns a `Query` — an `AsyncSequence` that yields `SDKMessage` values.

```swift
let query = try ClaudeAgentSDK.query(
    prompt: "Explain this codebase",
    options: Options(
        model: "claude-sonnet-4-6",
        maxTurns: 5,
        pathToClaudeCodeExecutable: "/usr/local/bin/claude"
    )
)

for try await message in query {
    switch message {
    case let .system(.initialize(initMsg)):
        print("Session started: model=\(initMsg.model)")

    case let .assistant(msg):
        if let content = msg.message["content"]?.arrayValue {
            for block in content {
                if let text = block["text"]?.stringValue {
                    print(text)
                }
            }
        }

    case let .result(.success(result)):
        print("Done: \(result.result)")
        print("Cost: $\(result.totalCostUsd), Duration: \(result.durationMs)ms")

    case let .result(.error(error)):
        print("Error: \(error.errors.joined(separator: ", "))")

    default:
        break
    }
}
```

### Multi-turn Sessions

Use the V2 Session API for multi-turn conversations where context is maintained across turns:

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
try await session.send("Now multiply that by 10")
for try await message in session.stream() {
    if case let .result(.success(result)) = message {
        print(result.result) // "40"
    }
}

session.close()
```

#### One-shot Prompt

For single-turn queries using the session protocol:

```swift
let result = try await ClaudeAgentSDK.prompt(
    "What is the capital of France?",
    options: SessionOptions(model: "claude-sonnet-4-6")
)

if case let .success(r) = result {
    print(r.result) // "Paris"
}
```

#### Resume a Session

```swift
let session = try ClaudeAgentSDK.resumeSession(
    "existing-session-uuid",
    options: SessionOptions(model: "claude-sonnet-4-6")
)
try await session.send("Continue where we left off")
for try await message in session.stream() { ... }
```

### Streaming Input

For manual control over when messages are sent:

```swift
let query = try ClaudeAgentSDK.queryStreaming(
    options: Options(maxTurns: 1)
)

try await query.sendMessage("What is 3 + 3?")
query.endInput()

for try await message in query {
    if case let .result(.success(result)) = message {
        print(result.result) // "6"
    }
}
```

Or drive input from an `AsyncStream`:

```swift
let (stream, continuation) = AsyncStream<SDKUserMessage>.makeStream()

let query = try ClaudeAgentSDK.query(prompt: stream, options: Options())

continuation.yield(SDKUserMessage.text("Hello"))
continuation.finish()

for try await message in query { ... }
```

### Session Management

List, inspect, and manage saved sessions:

```swift
// List recent sessions
let sessions = try await ClaudeAgentSDK.listSessions(
    options: ListSessionsOptions(limit: 10)
)
for session in sessions {
    print("\(session.sessionId): \(session.summary)")
}

// Get info for a specific session
if let info = try await ClaudeAgentSDK.getSessionInfo("session-uuid") {
    print("Title: \(info.summary)")
    print("Last modified: \(info.lastModified)")
}

// Read conversation messages
let messages = try await ClaudeAgentSDK.getSessionMessages(
    "session-uuid",
    limit: 20
)
for msg in messages {
    print("[\(msg.type)] \(msg.message)")
}

// Rename a session
try await ClaudeAgentSDK.renameSession("session-uuid", title: "My Project Review")

// Tag a session
try await ClaudeAgentSDK.tagSession("session-uuid", tag: "important")

// Fork a session (branch from a specific point)
let fork = try await ClaudeAgentSDK.forkSession(
    "session-uuid",
    upToMessageId: "message-uuid",
    title: "Alternative approach"
)
print("Forked to: \(fork.sessionId)")
```

### Configuration Options

The `Options` struct provides extensive configuration:

```swift
let options = Options(
    // Model selection
    model: "claude-opus-4-6",

    // Working directory
    cwd: "/path/to/project",

    // System prompt
    systemPrompt: .presetWithAppend("Always explain your reasoning."),

    // Permissions
    permissionMode: .acceptEdits,
    allowedTools: ["Read", "Grep", "Glob"],
    disallowedTools: ["Bash"],

    // Limits
    maxTurns: 10,
    maxBudgetUsd: 1.0,

    // Thinking/reasoning
    thinking: .adaptive,
    effort: .high,

    // Session management
    continueSession: true,
    persistSession: false,

    // Custom agents
    agent: "code-reviewer",
    agents: [
        "code-reviewer": AgentDefinition(
            description: "Reviews code for best practices",
            prompt: "You are a code reviewer...",
            tools: ["Read", "Grep", "Glob"]
        )
    ],

    // Environment
    env: ["ANTHROPIC_API_KEY": "sk-..."],

    // Debug
    debug: true,
    stderr: { line in print("[stderr] \(line)") },

    // Executable path
    pathToClaudeCodeExecutable: "\(NSHomeDirectory())/.local/bin/claude"
)
```

### Handling Messages

`SDKMessage` is a discriminated enum covering all message types from the CLI:

```swift
for try await message in query {
    switch message {
    // System events
    case let .system(.initialize(msg)):
        // Session initialized — model, tools, version info
        break
    case let .system(.status(msg)):
        // Status update (e.g., "compacting")
        break
    case let .system(.apiRetry(msg)):
        // API request being retried
        break
    case let .system(.taskStarted(msg)):
        // Background task started
        break
    case let .system(.taskProgress(msg)):
        // Background task progress
        break
    case let .system(.taskNotification(msg)):
        // Background task completed/failed/stopped
        break

    // Assistant messages
    case let .assistant(msg):
        // Claude's response (msg.message is AnyCodable — the full API response)
        break
    case let .streamEvent(msg):
        // Partial streaming event (when includePartialMessages is true)
        break

    // Results
    case let .result(.success(result)):
        // result.result — text output
        // result.totalCostUsd — cost
        // result.usage — token usage
        break
    case let .result(.error(error)):
        // error.errors — error messages
        // error.subtype — "error_max_turns", "error_max_budget_usd", etc.
        break

    // Other events
    case let .toolProgress(msg):
        // Long-running tool progress
        break
    case let .toolUseSummary(msg):
        // Summary of tool executions
        break
    case let .rateLimitEvent(msg):
        // Rate limit status update
        break
    case let .promptSuggestion(msg):
        // Suggested next prompt
        break

    // User messages (from session replay)
    case let .user(msg):
        break
    case let .userReplay(msg):
        break
    case let .authStatus(msg):
        break
    }
}
```

### Permission Handling

Provide a `canUseTool` callback to control which tools Claude can use:

```swift
let options = Options(
    canUseTool: { toolName, input, options in
        // Allow read-only tools automatically
        if ["Read", "Glob", "Grep"].contains(toolName) {
            return .allow()
        }

        // Deny destructive operations
        if toolName == "Bash" {
            if let command = input["command"]?.stringValue,
               command.contains("rm ") {
                return .deny(message: "Destructive commands not allowed")
            }
        }

        // Allow everything else
        return .allow()
    }
)
```

### Control Methods

The `Query` object provides control methods for interacting with the running session:

```swift
let query = try ClaudeAgentSDK.query(prompt: "...", options: options)

// Interrupt the current execution
try await query.interrupt()

// Change the model mid-session
try await query.setModel("claude-opus-4-6")

// Change permission mode
try await query.setPermissionMode(.acceptEdits)

// Send additional messages (streaming mode only)
try await query.sendMessage("Follow-up question")

// Close stdin (signal no more input)
query.endInput()

// Terminate the query
query.close()
```

### Structured Output

Use `outputFormat` for JSON schema-validated responses:

```swift
let options = Options(
    outputFormat: .jsonSchema([
        "type": "object",
        "properties": [
            "summary": ["type": "string"],
            "issues": [
                "type": "array",
                "items": ["type": "string"]
            ]
        ],
        "required": ["summary", "issues"]
    ])
)
```

### MCP Server Configuration

Configure Model Context Protocol servers:

```swift
let options = Options(
    mcpServers: [
        "my-server": .stdio(McpStdioServerConfig(
            command: "node",
            args: ["./my-mcp-server.js"]
        )),
        "remote-server": .http(McpHttpServerConfig(
            url: "https://mcp.example.com",
            headers: ["Authorization": "Bearer token"]
        ))
    ]
)
```

## Platform Support

| Platform | Types & Models | Process Spawning |
|----------|:-:|:-:|
| macOS 15+ | Yes | Yes |
| iOS 18+ | Yes | No |

On iOS, all types (`SDKMessage`, `Options`, `AnyCodable`, etc.) are fully available for use in your data layer. Calling `ClaudeAgentSDK.query()` or `ClaudeAgentSDK.createSession()` on iOS throws `ClaudeAgentSDKError.unsupportedPlatform` since `Foundation.Process` is not available.

## Architecture

The SDK communicates with the Claude Code CLI by:

1. Spawning `claude` with `--print --output-format stream-json --verbose`
2. Reading newline-delimited JSON from stdout
3. Writing JSON messages to stdin (for streaming input and sessions)
4. Routing control requests/responses (permissions, interrupts) over the same channel

```
┌──────────────┐         stdin (JSON)          ┌──────────────┐
│              │  ─────────────────────────────▶│              │
│  Swift App   │                                │  Claude CLI  │
│  (Query)     │  ◀─────────────────────────────│  Process     │
│              │         stdout (JSON lines)    │              │
└──────────────┘                                └──────────────┘
```

### Key Types

| Type | Description |
|------|-------------|
| `ClaudeAgentSDK` | Entry point — `query()`, `createSession()`, `prompt()`, session management |
| `Query` | `AsyncSequence<SDKMessage>` with control methods and streaming input |
| `Session` | Multi-turn conversation with `send()`/`stream()`/`close()` |
| `Options` | Configuration for `query()` (model, permissions, tools, etc.) |
| `SessionOptions` | Configuration for sessions (model is required) |
| `SDKMessage` | Discriminated enum of all CLI message types |
| `SDKResultMessage` | Success or error result |
| `AnyCodable` | Type-erased JSON value (`Sendable`, recursive enum) |
| `Settings` | CLI settings (permissions, model, MCP, hooks, etc.) with escape hatch |
| `HookEvent` | 23 hook event types for intercepting execution |
| `SdkMcpServer` | In-process MCP server with custom tool definitions |
| `BridgeSessionHandle` | SSE-based remote session handle (alpha) |

### Concurrency

The library is built for Swift 6 strict concurrency:

- All public types are `Sendable`
- `AnyCodable` uses a recursive enum (not `Any`) for full `Sendable` conformance
- `Query` and `Session` use `@unchecked Sendable` with internal `NSLock` synchronization
- `SdkMcpServer` uses Swift actors for safe concurrent tool dispatch
- Callbacks are typed as `@Sendable`
- Zero data races under the strict concurrency checker

## License

See [LICENSE](LICENSE) for details.
