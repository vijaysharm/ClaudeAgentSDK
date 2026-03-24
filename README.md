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
    case .result(.success(let result)):
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
    case .system(.initialize(let init)):
        print("Session started: model=\(init.model)")

    case .assistant(let msg):
        // Extract text content from the assistant message
        if let content = msg.message["content"]?.arrayValue {
            for block in content {
                if let text = block["text"]?.stringValue {
                    print(text)
                }
            }
        }

    case .result(.success(let result)):
        print("Done: \(result.result)")
        print("Cost: $\(result.totalCostUsd), Duration: \(result.durationMs)ms")

    case .result(.error(let error)):
        print("Error: \(error.errors.joined(separator: ", "))")

    default:
        break
    }
}
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
    continueSession: true,  // Resume most recent session
    // resume: "session-uuid",  // Resume specific session
    persistSession: false,  // Don't save to disk

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
    case .system(.initialize(let msg)):
        // Session initialized — model, tools, version info
        break
    case .system(.status(let msg)):
        // Status update (e.g., "compacting")
        break
    case .system(.apiRetry(let msg)):
        // API request being retried
        break
    case .system(.taskStarted(let msg)):
        // Background task started
        break
    case .system(.taskProgress(let msg)):
        // Background task progress
        break
    case .system(.taskNotification(let msg)):
        // Background task completed/failed/stopped
        break
    case .system(.hookStarted(let msg)),
         .system(.hookProgress(let msg)),
         .system(.hookResponse(let msg)):
        // Hook execution events
        break

    // Assistant messages
    case .assistant(let msg):
        // Claude's response (msg.message is AnyCodable — the full API response)
        break
    case .streamEvent(let msg):
        // Partial streaming event (when includePartialMessages is true)
        break

    // Results
    case .result(.success(let result)):
        // Query completed successfully
        // result.result — text output
        // result.totalCostUsd — cost
        // result.usage — token usage
        break
    case .result(.error(let error)):
        // Query failed
        // error.errors — error messages
        // error.subtype — "error_max_turns", "error_max_budget_usd", etc.
        break

    // Other events
    case .toolProgress(let msg):
        // Long-running tool progress
        break
    case .toolUseSummary(let msg):
        // Summary of tool executions
        break
    case .rateLimitEvent(let msg):
        // Rate limit status update
        break
    case .promptSuggestion(let msg):
        // Suggested next prompt
        break

    // User messages (from session replay)
    case .user(let msg):
        break
    case .userReplay(let msg):
        break
    case .authStatus(let msg):
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

On iOS, all types (`SDKMessage`, `Options`, `AnyCodable`, etc.) are fully available for use in your data layer. Calling `ClaudeAgentSDK.query()` on iOS throws `ClaudeAgentSDKError.unsupportedPlatform` since `Foundation.Process` is not available.

## Architecture

The SDK communicates with the Claude Code CLI by:

1. Spawning `claude` with `--print --output-format stream-json --verbose`
2. Reading newline-delimited JSON from stdout
3. Writing JSON messages to stdin (for streaming input mode)
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
| `ClaudeAgentSDK` | Entry point — `query()` function |
| `Query` | `AsyncSequence<SDKMessage>` with control methods |
| `Options` | Configuration (model, permissions, tools, etc.) |
| `SDKMessage` | Discriminated enum of all CLI message types |
| `SDKResultMessage` | Success or error result |
| `AnyCodable` | Type-erased JSON value (`Sendable`, recursive enum) |

### Concurrency

The library is built for Swift 6 strict concurrency:

- All public types are `Sendable`
- `AnyCodable` uses a recursive enum (not `Any`) for full `Sendable` conformance
- `Query` uses `@unchecked Sendable` with internal `NSLock` synchronization
- Callbacks are typed as `@Sendable`
- Zero data races under the strict concurrency checker

## Phase 2 (Planned)

The following features from the TypeScript SDK are not yet ported:

- **V2 Session API** — `SDKSession` for multi-turn conversations
- **Full Settings type** — Complete settings schema
- **Hook callback system** — Programmatic hook registration
- **MCP SDK server creation** — In-process MCP tools
- **Bridge API** — claude.ai bridge transport
- **Session management** — `listSessions`, `getSessionInfo`, `renameSession`, etc.
- **Streaming input** — `AsyncStream<SDKUserMessage>` prompt variant

## License

See [LICENSE](LICENSE) for details.
