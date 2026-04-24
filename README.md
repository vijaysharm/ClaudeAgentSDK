# Claude Agent SDK for Swift

A Swift Package Manager library for building Claude-powered agents in Swift. Three independent layers are provided:

| Layer | API | Requires |
|---|---|---|
| **Native** | `ClaudeAgent` | Anthropic API key |
| **CLI wrapper** | `ClaudeAgentSDK.query()` / `Session` | `claude` binary |
| **Claw Code ports** | `ClawAPI` / `ClawRuntime` / `ClawPlugins` / `ClawCommands` / `ClawTools` / `ClawTelemetry` / `ClawCompatHarness` / `ClawMockService` | — (library code only) |

The first two expose an `AsyncSequence`-based streaming API and share the same `TerminalRenderer`. The **Claw Code ports** are a Swift-6 port of the non-TUI pieces of [instructkr/claude-code](https://github.com/instructkr/claude-code) — a provider-agnostic API client, multi-provider routing, permission engine, sandbox, hooks, MCP naming + lifecycle, session/compaction, plugin + command registries, a mock service, and more.

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

## Claw Code Ports

A Swift 6 port of the non-TUI crates from [instructkr/claude-code](https://github.com/instructkr/claude-code) (the "Claw Code" Rust reference implementation). Each namespace is independent — you can use them à la carte without adopting the native agent or CLI wrapper.

| Namespace | What it covers | Rough LOC |
|---|---|---|
| `ClawAPI` | Provider-agnostic wire types, error classification, SSE parser, prompt-cache, Anthropic + OpenAI-compat clients, façade `ProviderClient` | ~2.3k |
| `ClawTelemetry` | `ClientIdentity`, request profiles, analytics events, `SessionTracer`, JSONL + in-memory sinks | ~0.4k |
| `ClawRuntime` | Bootstrap plan, sandbox types, token usage + pricing, permissions + rule matcher + enforcer, bash validation, trust resolver, recovery recipes, policy engine, summary compression, branch/git context, OAuth + PKCE, MCP naming + lifecycle, lane events, task/team/cron registries, worker boot, config loader, hook runner, file ops, session + compaction, prompt builder, LSP + SSE + remote bootstrap | ~3.6k |
| `ClawPlugins` | Plugin manifest, definitions, registry, install records | ~0.4k |
| `ClawCommands` | Slash-command spec table, parser, fuzzy suggestions, skills classifier | ~0.4k |
| `ClawTools` | Tool spec manifest, global tool registry, lane-completion detector, minimal PDF text extractor | ~0.5k |
| `ClawCompatHarness` | Upstream-TypeScript manifest extractor | ~0.2k |
| `ClawMockService` | Deterministic scenario detection + SSE frame builder for test harnesses | ~0.2k |

### ClawAPI — Multi-provider Messages API

Direct-to-Anthropic (or xAI, OpenAI, DashScope) client with retry, streaming, and prompt caching. Independent of `ClaudeAgent` — you can build your own agent loop on top.

```swift
import ClaudeAgentSDK

let request = ClawAPI.MessageRequest(
    model: "claude-sonnet-4-6",
    maxTokens: 1024,
    messages: [.userText("Summarize the Swift Package Manager docs in 3 bullets.")],
    system: "You are a concise tech writer."
)

let client = try ClawAPI.AnthropicClient(fromEnvironment: ProcessInfo.processInfo.environment)
let response = try await client.sendMessage(request)
print(response.content)  // [.text("• …"), ...]
print(response.usage.totalTokens())
```

Streaming with `AsyncSequence`:

```swift
for try await event in client.streamMessage(request) {
    switch event {
    case .contentBlockDelta(let delta):
        if case .textDelta(let t) = delta.delta { print(t, terminator: "") }
    case .messageStop: print()
    default: break
    }
}
```

Provider-agnostic façade — routes by model name, reads env vars for OpenAI / xAI / DashScope (Qwen/Kimi):

```swift
let grok = try ClawAPI.ProviderClient.forModel("grok-3")       // → xAI
let gpt = try ClawAPI.ProviderClient.forModel("gpt-5-turbo")   // → OpenAI
let kimi = try ClawAPI.ProviderClient.forModel("kimi-k2.5")    // → DashScope
let response = try await grok.sendMessage(request)
```

On-disk prompt cache with FNV-1a fingerprinting and TTL:

```swift
let cache = ClawAPI.PromptCache(config: ClawAPI.PromptCacheConfig(sessionId: "my-app"))
let client = try ClawAPI.AnthropicClient(fromEnvironment: ProcessInfo.processInfo.environment)
    .withPromptCache(cache)
let response = try await client.sendMessage(request)  // writes to cache
let cached = try await client.sendMessage(request)    // cache hit (if < TTL)
```

### ClawRuntime — Permissions, Policy, Sandbox, Hooks

Permission modes + rule matchers match the Rust crate's grammar (`Tool(pattern)`, `Tool(prefix:*)`):

```swift
let rules = ClawRuntime.RuntimePermissionRuleConfig(
    allow: ["Bash(ls *)", "Read"],
    deny: ["Bash(rm *)"],
    ask: ["Write"]
)
let policy = ClawRuntime.PermissionPolicy(activeMode: .workspaceWrite)
    .withPermissionRules(rules)
    .withToolRequirement("Write", .workspaceWrite)

switch policy.authorize(tool: "Bash", input: #"{"command":"ls -la"}"#) {
case .allow: print("OK")
case .deny(let reason): print("denied:", reason)
}
```

Permission **enforcer** with quick-path classifiers for file-write and bash:

```swift
let enforcer = ClawRuntime.PermissionEnforcer(
    ClawRuntime.PermissionPolicy(activeMode: .readOnly)
)
enforcer.checkFileWrite(path: "/tmp/x", workspaceRoot: "/tmp")   // .denied
enforcer.checkBash(command: "git status")                        // .allowed (read-only whitelist)
enforcer.checkBash(command: "rm -rf /")                          // .denied
```

Bash-command validation and classification:

```swift
switch ClawRuntime.BashValidator.validateReadOnly("rm -rf foo", mode: .readOnly) {
case .block(let reason): print("blocked:", reason)
case .warn(let msg): print("warning:", msg)
case .allow: break
}

// CommandIntent.destructive, .network, .packageManagement, etc.
let intent = ClawRuntime.BashValidator.classify("apt-get install foo")
```

Policy engine — declarative rules over `LaneContext`:

```swift
let engine = ClawRuntime.PolicyEngine(rules: [
    ClawRuntime.PolicyRule(
        name: "closeout-green-lanes",
        condition: .and([.laneCompleted, .greenAt(level: 3)]),
        action: .closeoutLane,
        priority: 0
    ),
    ClawRuntime.PolicyRule(
        name: "warn-stale-branches",
        condition: .staleBranch,
        action: .notify(channel: "#eng-lanes"),
        priority: 1
    ),
])
let actions = engine.evaluate(laneContext)
```

Hook runner — dispatches shell commands with JSON payload on stdin:

```swift
let runner = ClawRuntime.HookRunner(config: ClawRuntime.RuntimeHookConfig(
    preToolUse: ["./hooks/check-secret-in-input.sh"],
    postToolUse: ["./hooks/log-tool-use.sh"]
))
let result = runner.runPreToolUse(toolName: "Bash", toolInput: #"{"command":"ls"}"#)
if result.denied { print("blocked by hook:", result.messages) }
if let decision = result.permissionDecision { /* .allow / .deny / .ask */ }
```

Conversation session with compaction:

```swift
var session = ClawRuntime.Session(sessionId: "demo", workspaceRoot: "/repo", model: "claude-sonnet-4-6")
session.pushUserText("Help me refactor the parser")
session.pushMessage(.assistant([.text("Sure — here's a plan…")]))

// When history gets large
if ClawRuntime.shouldCompact(session, config: ClawRuntime.CompactionConfig()) {
    let result = ClawRuntime.compactSession(session, config: ClawRuntime.CompactionConfig())
    session = result.compactedSession
    print("Compacted \(result.removedMessageCount) messages")
}
```

Trust resolver and stale-branch check:

```swift
let resolver = ClawRuntime.TrustResolver(config: ClawRuntime.TrustConfig(
    allowlisted: ["/Users/me/work"]
))
let decision = resolver.resolve(cwd: "/Users/me/work/repo", screenText: screenOutput)
// .notRequired or .required(policy: .autoTrust / .requireApproval / .deny, events: […])

switch ClawRuntime.checkBranchFreshness(branch: "feature/x", mainRef: "origin/main") {
case .fresh: break
case .stale(let behind, _): print("behind main by \(behind) commits")
case .diverged(let ahead, let behind, _): print("\(ahead) ahead, \(behind) behind")
}
```

OAuth + PKCE:

```swift
let pkce = ClawRuntime.generatePkcePair()
let state = ClawRuntime.generateState()
let authReq = ClawRuntime.OAuthAuthorizationRequest.fromConfig(
    config, redirectUri: "http://localhost:8765/callback",
    state: state, pkce: pkce
)
print(authReq.buildURL())  // open in browser
// … after redirect with ?code=… &state=… …
let callback = ClawRuntime.parseOAuthCallbackQuery(queryString)
```

Task / team / cron registries (actor-based, Sendable-safe):

```swift
let tasks = ClawRuntime.TaskRegistry()
let task = await tasks.create(prompt: "Write the PR description", description: "docs task")
await tasks.setStatus(task.taskId, .running)
await tasks.appendOutput(task.taskId, "…output chunk…")
```

### ClawPlugins — Plugin Manifest + Registry

```swift
// Load a plugin's manifest from disk
let manifest = try ClawPlugins.loadManifest(fromDirectory: "/path/to/my-plugin")

// Build a registry from installed plugins
let registry = ClawPlugins.PluginRegistry(plugins: [
    ClawPlugins.RegisteredPlugin(
        definition: .external(ClawPlugins.ExternalPlugin(
            metadata: .init(
                id: "my-plugin@external", name: manifest.name,
                version: manifest.version, description: manifest.description,
                kind: .external, source: "/path/to/my-plugin",
                defaultEnabled: manifest.defaultEnabled, root: "/path/to/my-plugin"
            ),
            hooks: manifest.hooks, lifecycle: manifest.lifecycle, tools: []
        )),
        enabled: true
    )
])

let hooks = registry.aggregatedHooks()           // merged PreToolUse / PostToolUse / …
let tools = try registry.aggregatedTools()        // throws on duplicate names
```

### ClawCommands — Slash-command Registry

Parse user input like `/compact` or `/plugins install ./my-plugin`:

```swift
switch try ClawCommands.parse("/plugins install ./my-plugin") {
case .plugins(action: "install", target: let target):
    print("install", target ?? "")
case .compact: print("compact the session")
case .help: print(ClawCommands.slashCommandSpecs())
default: break
}
```

Fuzzy suggestions for mistyped commands:

```swift
ClawCommands.suggestSlashCommands("/comp")    // → ["/compact", "/config"]
ClawCommands.suggestSlashCommands("/hel")     // → ["/help"]
```

Skills dispatch (distinguishes local management from `$name` invocation):

```swift
switch ClawCommands.classifySkillsSlashCommand("coding-helper") {
case .local: break                             // list/install/help
case .invoke(let target): print(target)        // "$coding-helper"
}
```

### ClawTools — Tool Manifest + PDF Extractor

```swift
// Built-in tool specs (bash, read_file, write_file, edit_file, glob_search, grep_search)
for spec in ClawTools.mvpToolSpecs() {
    print(spec.name, spec.requiredPermission)
}

// Global tool registry with plugin tools folded in
let registry = try ClawTools.GlobalToolRegistry.builtin()
    .withPluginTools(pluginTools)
    .withEnforcer(enforcer)

let result = registry.search(query: "grep", maxResults: 3)
print(result.matches)  // ["grep_search", ...]

// Normalize allowed_tools input (handles aliases: read → read_file, etc.)
let allowed = ClawTools.GlobalToolRegistry.normalizeAllowedTools(["read, write, glob"])

// PDF text extraction
let text = try ClawToolsPdfExtract.extractText(path: "/path/to/doc.pdf")

// Lane-completion detector (for agent orchestration)
if let laneCtx = ClawTools.detectLaneCompletion(
    output: agentOutput, testGreen: true, hasPushed: true
) {
    let actions = ClawTools.evaluateCompletedLane(laneCtx)
    // → [.closeoutLane, .cleanupSession]
}
```

### ClawTelemetry — Sinks + SessionTracer

```swift
let sink = try ClawTelemetry.JsonlTelemetrySink(path: "/var/log/claude/telemetry.jsonl")
let tracer = ClawTelemetry.SessionTracer(sessionId: "session-123", sink: sink)

tracer.recordHTTPRequestStarted(attempt: 1, method: "POST", path: "/v1/messages")
tracer.recordHTTPRequestSucceeded(
    attempt: 1, method: "POST", path: "/v1/messages",
    status: 200, requestId: "req_abc"
)
tracer.recordAnalytics(ClawTelemetry.AnalyticsEvent(
    namespace: "api", action: "message_usage",
    properties: ["total_tokens": .int(1240), "cost_usd": .string("$0.0031")]
))
```

Anthropic request profile — injects `anthropic-version`, `anthropic-beta`, `user-agent` headers and merges `extra_body` into JSON:

```swift
let profile = ClawTelemetry.AnthropicRequestProfile(
    clientIdentity: .init(appName: "myapp", appVersion: "1.0")
)
let headers = profile.headerPairs()
let body = try profile.renderJSONBody(request)
```

### ClawMockService — Test Scenario Detector

Use in tests to drive deterministic responses without a real API. Transport-less — wire it into any HTTP server you like.

```swift
let request = ClawAPI.MessageRequest(
    model: "claude-sonnet-4-6", maxTokens: 512,
    messages: [.userText("PARITY_SCENARIO:streaming_text please")]
)
if let scenario = ClawMockService.detectScenario(request) {
    let frames = ClawMockService.buildStreamFrames(for: request, scenario: scenario)
    // ship via your HTTP mock as text/event-stream body
}
```

### ClawCompatHarness — Extract Upstream TS Manifest

Recover the canonical command/tool/bootstrap manifest from an upstream Claude Code TypeScript checkout:

```swift
if let paths = ClawCompatHarness.UpstreamPaths.fromWorkspaceDir(cwd) {
    let manifest = try ClawCompatHarness.extractManifest(paths)
    print(manifest.commands.entries)      // [/help, /compact, …]
    print(manifest.tools.entries)         // [BashTool, ReadTool, …]
    print(manifest.bootstrap.phases)      // [.cliEntry, .fastPathVersion, …]
}
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

### Claw Code Ports — Component Map

The ported namespaces are independent of `ClaudeAgent` and `ClaudeAgentSDK`. They form a layered library — each layer depends only on types from the layers below it, so you can adopt any subset.

```
╔═══════════════════════════════════════════════════════════════════════════╗
║                         Your Swift Application                            ║
║                                                                           ║
║     (build any harness — or reuse the built-in ClaudeAgent above)         ║
╚══╤═════════════════════╤═══════════════════╤═══════════════════╤══════════╝
   │                     │                   │                   │
   ▼                     ▼                   ▼                   ▼
┌────────────────┐  ┌──────────────┐  ┌────────────────┐  ┌──────────────┐
│  ClawCommands  │  │  ClawTools   │  │  ClawPlugins   │  │ ClawCompat-  │
│                │  │              │  │                │  │   Harness    │
│ • SlashCommand │  │ • ToolSpec   │  │ • Manifest     │  │              │
│ • parse(…)     │  │ • Registry   │  │ • Registry     │  │ • TS-source  │
│ • suggestions  │  │ • PDF extract│  │ • RegisteredP. │  │   manifest   │
│ • SkillsDisp.  │  │ • lane-      │  │ • InstallRecord│  │   extractor  │
│                │  │   completion │  │                │  │              │
└────┬───────────┘  └──────┬───────┘  └───────┬────────┘  └──────┬───────┘
     │                     │                  │                  │
     │         ┌───────────▼──────────────────▼───────┐          │
     │         │              ClawRuntime              │          │
     │         │                                       │          │
     │         │  Permissions        Sandbox           │          │
     │         │  PermissionEnforcer ContainerEnv.     │          │
     │         │  BashValidator      Session + Compact │          │
     │         │  PolicyEngine       Usage / Pricing   │          │
     │         │  PromptBuilder      OAuth (PKCE)      │          │
     │         │  HookRunner         MCP naming        │          │
     │         │  TrustResolver      MCP lifecycle     │          │
     │         │  FileOps            Lane events       │          │
     │         │  ConfigLoader       Worker state      │          │
     │         │  TaskRegistry       Recovery recipes  │          │
     │         │  TeamRegistry       SSE parser        │          │
     │         │  CronRegistry       Branch/git ctx    │          │
     │         └────┬──────────────────────────────┬───┘          │
     │              │                              │              │
     ▼              ▼                              ▼              ▼
┌─────────────────────────────┐          ┌───────────────────────────────┐
│          ClawAPI            │          │        ClawTelemetry          │
│                             │          │                               │
│  MessageRequest / Response  │          │  ClientIdentity               │
│  ApiError (classification)  │          │  AnthropicRequestProfile      │
│  SseParser + StreamEvent    │          │  AnalyticsEvent               │
│  PromptCache (FNV-1a + TTL) │          │  SessionTracer                │
│                             │          │  JsonlTelemetrySink           │
│  AnthropicClient  (retry)   │          │  MemoryTelemetrySink          │
│  OpenAiCompatClient         │          └───────────────────────────────┘
│    (xAI / OpenAI /                           ▲
│     DashScope — translates                   │
│     to /chat/completions)                    │  attach to
│                                              │  record http,
│  ProviderClient (façade)                     │  analytics,
│    • resolveModelAlias                       │  session traces
│    • detectProviderKind                      │
│    • preflight                               │
└──────────┬────────────────┬──────────────────┘
           │                │
    ┌──────▼─────┐   ┌──────▼──────────┐
    │ Anthropic  │   │ OpenAI / xAI /  │
    │    API     │   │ DashScope APIs  │
    └────────────┘   └─────────────────┘

┌───────────────────────────────────────────────────────────────────────────┐
│                           ClawMockService                                 │
│                                                                           │
│   • detectScenario(request) — finds "PARITY_SCENARIO:<name>" markers      │
│   • buildMessageResponse / buildStreamFrames — deterministic payloads     │
│   • transport-less: plug into a SwiftNIO / Network.framework server       │
│     when you want over-the-wire behavior                                  │
└───────────────────────────────────────────────────────────────────────────┘
```

### Claw Code Ports — Request Flow

A typical agent harness built on the ports looks like this:

```
 user prompt
      │
      ▼
┌──────────────────────┐
│  ClawCommands.parse  │──▶  /compact  → run ClawRuntime.compactSession
└──────────┬───────────┘      /help    → render ClawCommands.specs
           │ (not a slash command — real prompt)
           ▼
┌───────────────────────────┐
│  ClawRuntime.SystemPrompt │  builds prompt: intro + bullets + env +
│      Builder.render()     │  project context + CLAUDE.md files
└──────────┬────────────────┘
           │
           ▼
┌───────────────────────────┐
│  ClawRuntime.HookRunner   │  PreToolUse hooks may deny/ask/rewrite input
│  .runPreToolUse(…)        │
└──────────┬────────────────┘
           │ allowed
           ▼
┌───────────────────────────┐
│  ClawRuntime.Permission   │  authorize(tool, input, prompter)
│  Policy.authorize(…)      │  → .allow / .deny(reason)
└──────────┬────────────────┘
           │ allowed
           ▼
┌───────────────────────────┐
│  ClawAPI.ProviderClient   │  detects provider by model, preflights
│  .streamMessage(request)  │  context-window, applies retry/backoff,
└──────────┬────────────────┘  writes into PromptCache, emits
           │                   AsyncThrowingStream<StreamEvent>
           ▼
 Anthropic / OpenAI-compat
 provider — streamed back
 through AnthropicClient or
 OpenAiCompatClient.StreamState
           │
           ▼
┌────────────────────────────┐
│  (your harness) execute    │
│   tool calls, yield        │
│   tool_result blocks,      │
│   run PostToolUse hooks    │──▶  ClawRuntime.HookRunner
└──────────┬─────────────────┘     .runPostToolUse(…)
           │
           ▼
 loop until assistant stops
           │
           ▼
┌────────────────────────────┐
│  ClawRuntime.UsageTracker  │  aggregate tokens, estimate cost via
│                            │  ClawRuntime.pricingForModel
└──────────┬─────────────────┘
           │
           ▼
┌────────────────────────────┐
│  ClawTelemetry.Session-    │  ship http + analytics + session
│     Tracer.record(…)       │  trace records to JSONL / memory sinks
└────────────────────────────┘
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
| `ClawAPI.ProviderClient` | Façade over Anthropic / xAI / OpenAI / DashScope |
| `ClawAPI.AnthropicClient` | Retry + prompt-cache + SSE Anthropic client |
| `ClawAPI.OpenAiCompatClient` | Translates Anthropic shapes ↔ `/chat/completions` |
| `ClawAPI.MessageRequest` / `MessageResponse` | Provider-agnostic wire types |
| `ClawAPI.StreamEvent` | Codable streaming event enum |
| `ClawAPI.ApiError` | Retryable / context-window / auth classification |
| `ClawAPI.PromptCache` | On-disk completion cache (actor, FNV-1a hash) |
| `ClawRuntime.PermissionPolicy` / `PermissionEnforcer` | Rule + mode based authorization |
| `ClawRuntime.BashValidator` | Command intent + read-only validation |
| `ClawRuntime.PolicyEngine` | Lane-rule evaluation over `LaneContext` |
| `ClawRuntime.HookRunner` | Shell-command hooks (PreToolUse / PostToolUse / …) |
| `ClawRuntime.Session` / `compactSession` | Multi-turn history with auto-compaction |
| `ClawRuntime.TaskRegistry` / `TeamRegistry` / `CronRegistry` / `WorkerRegistry` | Actor-based lifecycle registries |
| `ClawPlugins.PluginRegistry` / `PluginManifest` | Plugin manifest + aggregated hooks/tools |
| `ClawCommands.SlashCommand` / `parse` | Typed slash-command parser + suggestions |
| `ClawTools.ToolSpec` / `GlobalToolRegistry` | Tool spec manifest + search |
| `ClawTelemetry.SessionTracer` | Per-session HTTP + analytics tracer |
| `ClawMockService.Scenario` | Deterministic test scenario detection |

### Concurrency

The library is built for Swift 6 strict concurrency:

- All public types are `Sendable`
- `AnyCodable` uses a recursive enum (not `Any`) for full `Sendable` conformance
- `AgentLoop` and `TerminalRenderer` are `actor` types — zero data races under the strict concurrency checker
- `Query` and `Session` use `@unchecked Sendable` with internal `NSLock` synchronisation
- Callbacks are typed as `@Sendable`

## License

See [LICENSE](LICENSE) for details.
