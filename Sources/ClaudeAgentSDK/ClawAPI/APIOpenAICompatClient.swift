import Foundation

extension ClawAPI {

    // MARK: - Config

    public struct OpenAiCompatConfig: Sendable, Equatable {
        public let providerName: String
        public let apiKeyEnv: String
        public let baseUrlEnv: String
        public let defaultBaseUrl: String
        public let maxRequestBodyBytes: Int

        public static let xai = OpenAiCompatConfig(
            providerName: "xAI",
            apiKeyEnv: "XAI_API_KEY",
            baseUrlEnv: "XAI_BASE_URL",
            defaultBaseUrl: "https://api.x.ai/v1",
            maxRequestBodyBytes: 50 * 1024 * 1024
        )

        public static let openai = OpenAiCompatConfig(
            providerName: "OpenAI",
            apiKeyEnv: "OPENAI_API_KEY",
            baseUrlEnv: "OPENAI_BASE_URL",
            defaultBaseUrl: "https://api.openai.com/v1",
            maxRequestBodyBytes: 100 * 1024 * 1024
        )

        public static let dashscope = OpenAiCompatConfig(
            providerName: "DashScope",
            apiKeyEnv: "DASHSCOPE_API_KEY",
            baseUrlEnv: "DASHSCOPE_BASE_URL",
            defaultBaseUrl: "https://dashscope.aliyuncs.com/compatible-mode/v1",
            maxRequestBodyBytes: 6 * 1024 * 1024
        )
    }

    // MARK: - Classification helpers

    public static func isReasoningModel(_ model: String) -> Bool {
        let trimmed = model.lowercased()
        let segment = trimmed.split(separator: "/").last.map(String.init) ?? trimmed
        if segment.hasPrefix("o1") || segment.hasPrefix("o3") || segment.hasPrefix("o4") {
            return true
        }
        if segment == "grok-3-mini" { return true }
        if segment.hasPrefix("qwen-qwq") || segment.hasPrefix("qwq") { return true }
        if segment.contains("thinking") { return true }
        return false
    }

    public static func modelRejectsIsErrorField(_ model: String) -> Bool {
        resolveModelAlias(model).lowercased().hasPrefix("kimi")
    }

    static func stripRoutingPrefix(_ model: String) -> String {
        if let slash = model.firstIndex(of: "/") {
            let prefix = model[..<slash].lowercased()
            if ["openai", "xai", "grok", "qwen", "kimi"].contains(prefix) {
                return String(model[model.index(after: slash)...])
            }
        }
        return model
    }

    // MARK: - Client

    public final class OpenAiCompatClient: @unchecked Sendable {
        public let http: URLSession
        public let apiKey: String
        public let config: OpenAiCompatConfig
        public let baseURL: String
        public let retryPolicy: RetryPolicy

        public init(
            apiKey: String,
            config: OpenAiCompatConfig,
            baseURL: String? = nil,
            retryPolicy: RetryPolicy = RetryPolicy(),
            http: URLSession = ClawAPI.makeHTTPClient()
        ) {
            self.apiKey = apiKey
            self.config = config
            self.baseURL = baseURL ?? config.defaultBaseUrl
            self.retryPolicy = retryPolicy
            self.http = http
        }

        public static func fromEnvironment(
            config: OpenAiCompatConfig,
            env: [String: String] = ProcessInfo.processInfo.environment
        ) throws -> OpenAiCompatClient {
            let key = ClawAPI.envOrDotenv(env, key: config.apiKeyEnv)
            guard !key.isEmpty else {
                throw ApiError.missingCredentials(
                    provider: config.providerName,
                    envVars: [config.apiKeyEnv]
                )
            }
            let base = ClawAPI.envOrDotenv(env, key: config.baseUrlEnv)
            return OpenAiCompatClient(
                apiKey: key,
                config: config,
                baseURL: base.isEmpty ? config.defaultBaseUrl : base
            )
        }

        // MARK: API

        public func sendMessage(_ request: MessageRequest) async throws -> MessageResponse {
            var req = request
            req.stream = false
            try ClawAPI.preflightMessageRequest(req)
            let urlReq = try buildRequest(req)
            let (data, resp) = try await http.data(for: urlReq)
            try enforceStatus(response: resp, body: data, model: req.model)
            return try normalizeResponse(data: data, model: req.model, response: resp)
        }

        public func streamMessage(_ request: MessageRequest) -> AsyncThrowingStream<StreamEvent, Error> {
            let req = request.withStreaming()
            return AsyncThrowingStream { continuation in
                Task {
                    do {
                        try ClawAPI.preflightMessageRequest(req)
                        let urlReq = try self.buildRequest(req)
                        let (bytes, resp) = try await self.http.bytes(for: urlReq)
                        try self.enforceStatus(response: resp, body: Data(), model: req.model)
                        let state = StreamState(model: req.model)
                        for try await line in bytes.lines {
                            if line.hasPrefix("data: ") {
                                let payload = String(line.dropFirst("data: ".count))
                                if payload == "[DONE]" { break }
                                if let chunk = ChatCompletionChunk.decode(payload) {
                                    state.ingest(chunk: chunk) { continuation.yield($0) }
                                }
                            }
                        }
                        state.finish { continuation.yield($0) }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
            }
        }

        // MARK: - Build request body

        func buildRequest(_ request: MessageRequest) throws -> URLRequest {
            var urlString = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if !urlString.hasSuffix("/chat/completions") {
                urlString += "/chat/completions"
            }
            guard let url = URL(string: urlString) else {
                throw ApiError.io("invalid baseURL: \(urlString)")
            }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

            let body = Self.buildChatCompletionRequest(request, config: config)
            let data = try JSONSerialization.data(
                withJSONObject: body, options: [.sortedKeys]
            )
            if data.count > config.maxRequestBodyBytes {
                throw ApiError.requestBodySizeExceeded(
                    estimatedBytes: data.count,
                    maxBytes: config.maxRequestBodyBytes,
                    provider: config.providerName
                )
            }
            req.httpBody = data
            return req
        }

        /// Produce an OpenAI `/chat/completions` payload from an Anthropic
        /// ``MessageRequest``. Public so tests can inspect the translation.
        public static func buildChatCompletionRequest(
            _ request: MessageRequest, config: OpenAiCompatConfig
        ) -> [String: Any] {
            var messages: [[String: Any]] = []
            if let system = request.system, !system.isEmpty {
                messages.append(["role": "system", "content": system])
            }
            let wireModel = stripRoutingPrefix(request.model)
            for msg in request.messages {
                messages.append(contentsOf: translateMessage(msg, model: wireModel))
            }
            messages = sanitizeToolMessagePairing(messages)

            let maxKey = wireModel.hasPrefix("gpt-5") ? "max_completion_tokens" : "max_tokens"
            var payload: [String: Any] = [
                "model": wireModel,
                maxKey: request.maxTokens,
                "messages": messages,
                "stream": request.stream,
            ]
            if request.stream && config.providerName == "OpenAI" {
                payload["stream_options"] = ["include_usage": true]
            }
            if let tools = request.tools, !tools.isEmpty {
                payload["tools"] = tools.map(openaiToolDefinition(_:))
            }
            if let tc = request.toolChoice {
                payload["tool_choice"] = openaiToolChoice(tc)
            }
            if !isReasoningModel(wireModel) {
                if let t = request.temperature { payload["temperature"] = t }
                if let p = request.topP { payload["top_p"] = p }
                if let f = request.frequencyPenalty { payload["frequency_penalty"] = f }
                if let pp = request.presencePenalty { payload["presence_penalty"] = pp }
            }
            if let stop = request.stop, !stop.isEmpty { payload["stop"] = stop }
            if let re = request.reasoningEffort { payload["reasoning_effort"] = re }
            return payload
        }

        /// Translate a single Anthropic input message into OpenAI chat messages.
        public static func translateMessage(
            _ msg: InputMessage, model: String
        ) -> [[String: Any]] {
            switch msg.role {
            case "assistant":
                var text = ""
                var toolCalls: [[String: Any]] = []
                for block in msg.content {
                    switch block {
                    case .text(let t): text += t
                    case .toolUse(let id, let name, let input):
                        let argsString: String
                        if let data = try? JSONEncoder().encode(input),
                           let s = String(data: data, encoding: .utf8) {
                            argsString = s
                        } else {
                            argsString = "{}"
                        }
                        toolCalls.append([
                            "id": id,
                            "type": "function",
                            "function": ["name": name, "arguments": argsString],
                        ])
                    default: break
                    }
                }
                if text.isEmpty && toolCalls.isEmpty { return [] }
                var m: [String: Any] = ["role": "assistant"]
                if !text.isEmpty { m["content"] = text }
                if !toolCalls.isEmpty { m["tool_calls"] = toolCalls }
                return [m]
            default:
                var out: [[String: Any]] = []
                for block in msg.content {
                    switch block {
                    case .text(let t):
                        out.append(["role": "user", "content": t])
                    case .toolResult(let id, let content, let isError):
                        var m: [String: Any] = [
                            "role": "tool",
                            "tool_call_id": id,
                            "content": flattenToolResultContent(content),
                        ]
                        if !modelRejectsIsErrorField(model) {
                            m["is_error"] = isError
                        }
                        out.append(m)
                    case .toolUse: break
                    }
                }
                return out
            }
        }

        public static func flattenToolResultContent(_ blocks: [ToolResultContentBlock]) -> String {
            var parts: [String] = []
            for b in blocks {
                switch b {
                case .text(let t): parts.append(t)
                case .json(let v):
                    if let data = try? JSONEncoder().encode(v),
                       let s = String(data: data, encoding: .utf8) {
                        parts.append(s)
                    }
                }
            }
            return parts.joined(separator: "\n")
        }

        public static func sanitizeToolMessagePairing(_ messages: [[String: Any]]) -> [[String: Any]] {
            var result: [[String: Any]] = []
            for msg in messages {
                if let role = msg["role"] as? String, role == "tool" {
                    // find nearest non-tool predecessor
                    if let predecessor = result.reversed().first(where: { ($0["role"] as? String) != "tool" }),
                       let predRole = predecessor["role"] as? String {
                        if predRole == "assistant" {
                            let toolCalls = predecessor["tool_calls"] as? [[String: Any]] ?? []
                            let callId = msg["tool_call_id"] as? String ?? ""
                            let matches = toolCalls.contains {
                                ($0["id"] as? String) == callId
                            }
                            if matches { result.append(msg) }
                            // else drop orphaned tool message
                        } else {
                            result.append(msg)
                        }
                    } else {
                        // no predecessor; drop
                    }
                } else {
                    result.append(msg)
                }
            }
            return result
        }

        static func openaiToolDefinition(_ t: ToolDefinition) -> [String: Any] {
            var params: [String: Any] = [:]
            if let data = try? JSONEncoder().encode(t.inputSchema),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                params = obj
            }
            normalizeObjectSchema(&params)
            var function: [String: Any] = ["name": t.name, "parameters": params]
            if let d = t.description { function["description"] = d }
            return ["type": "function", "function": function]
        }

        static func openaiToolChoice(_ tc: ToolChoice) -> Any {
            switch tc {
            case .auto: return "auto"
            case .any: return "required"
            case .tool(let name):
                return ["type": "function", "function": ["name": name]]
            }
        }

        static func normalizeObjectSchema(_ obj: inout [String: Any]) {
            if let type = obj["type"] as? String, type == "object" {
                if obj["properties"] == nil { obj["properties"] = [String: Any]() }
                if obj["additionalProperties"] == nil { obj["additionalProperties"] = false }
            }
            if var props = obj["properties"] as? [String: Any] {
                for (k, v) in props {
                    if var sub = v as? [String: Any] {
                        normalizeObjectSchema(&sub)
                        props[k] = sub
                    }
                }
                obj["properties"] = props
            }
            if var items = obj["items"] as? [String: Any] {
                normalizeObjectSchema(&items)
                obj["items"] = items
            }
        }

        // MARK: - Response parsing

        private func normalizeResponse(
            data: Data, model: String, response: URLResponse
        ) throws -> MessageResponse {
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw ApiError.jsonDeserialize(
                    provider: config.providerName, model: model,
                    body: String(data: data, encoding: .utf8) ?? "",
                    detail: "non-object response"
                )
            }
            if let err = obj["error"] as? [String: Any] {
                let msg = err["message"] as? String
                let typeStr = err["type"] as? String
                let statusCode: Int = {
                    if let c = err["code"] as? Int { return c }
                    if let s = err["code"] as? String, let v = Int(s) { return v }
                    return 400
                }()
                throw ApiError.api(
                    status: StatusCode(statusCode),
                    errorType: typeStr,
                    message: msg,
                    requestId: (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "request-id"),
                    body: String(data: data, encoding: .utf8) ?? "",
                    retryable: [408, 409, 429, 500, 502, 503, 504].contains(statusCode),
                    suggestedAction: AnthropicClient.suggestedAction(for: statusCode)
                )
            }
            let id = obj["id"] as? String ?? ""
            let responseModel = obj["model"] as? String ?? model
            let choices = obj["choices"] as? [[String: Any]] ?? []
            guard let first = choices.first else {
                throw ApiError.invalidSseFrame(
                    "chat completion response missing choices"
                )
            }
            var content: [OutputContentBlock] = []
            if let message = first["message"] as? [String: Any] {
                if let text = message["content"] as? String, !text.isEmpty {
                    content.append(.text(text))
                }
                if let toolCalls = message["tool_calls"] as? [[String: Any]] {
                    for tc in toolCalls {
                        let id = tc["id"] as? String ?? ""
                        if let fn = tc["function"] as? [String: Any],
                           let name = fn["name"] as? String {
                            let rawArgs = fn["arguments"] as? String ?? "{}"
                            let input = parseToolArguments(rawArgs)
                            content.append(.toolUse(id: id, name: name, input: input))
                        }
                    }
                }
            }
            let usage = obj["usage"] as? [String: Any] ?? [:]
            let inputTokens = (usage["prompt_tokens"] as? UInt32) ?? 0
            let outputTokens = (usage["completion_tokens"] as? UInt32) ?? 0
            var resp = MessageResponse(
                id: id,
                kind: "message",
                role: "assistant",
                content: content,
                model: responseModel,
                stopReason: normalizeFinishReason(first["finish_reason"] as? String),
                stopSequence: nil,
                usage: Usage(inputTokens: inputTokens, outputTokens: outputTokens),
                requestId: (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "request-id")
            )
            if resp.requestId == nil, let http = response as? HTTPURLResponse {
                resp.requestId = http.value(forHTTPHeaderField: "x-request-id")
            }
            return resp
        }

        private func parseToolArguments(_ s: String) -> AnyCodable {
            if let data = s.data(using: .utf8),
               let v = try? JSONDecoder().decode(AnyCodable.self, from: data) {
                return v
            }
            return .object(["raw": .string(s)])
        }

        private func normalizeFinishReason(_ reason: String?) -> String? {
            switch reason {
            case "stop": return "end_turn"
            case "tool_calls": return "tool_use"
            default: return reason
            }
        }

        private func enforceStatus(response: URLResponse, body: Data, model: String) throws {
            guard let http = response as? HTTPURLResponse else { return }
            let status = StatusCode(http.statusCode)
            if status.isSuccess { return }
            let retryable = [408, 409, 429, 500, 502, 503, 504].contains(http.statusCode)
            var errorType: String?
            var message: String?
            if let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
               let err = obj["error"] as? [String: Any] {
                errorType = err["type"] as? String
                message = err["message"] as? String
            }
            throw ApiError.api(
                status: status,
                errorType: errorType,
                message: message,
                requestId: http.value(forHTTPHeaderField: "request-id"),
                body: String(data: body, encoding: .utf8) ?? "",
                retryable: retryable,
                suggestedAction: AnthropicClient.suggestedAction(for: http.statusCode)
            )
        }
    }

    // MARK: - Streaming translation

    /// Stream state machine that translates OpenAI streaming chunks into
    /// Anthropic-shaped ``StreamEvent`` values.
    final class StreamState {
        let model: String
        private var messageStarted = false
        private var textStarted = false
        private var textFinished = false
        private var finished = false
        private var stopReason: String?
        private var usage: Usage?
        private var toolCalls: [UInt32: ToolCallState] = [:]

        init(model: String) { self.model = model }

        func ingest(chunk: ChatCompletionChunk, emit: (StreamEvent) -> Void) {
            if !messageStarted {
                messageStarted = true
                let msg = MessageResponse(
                    id: chunk.id,
                    model: chunk.model ?? model,
                    usage: Usage()
                )
                emit(.messageStart(MessageStartEvent(message: msg)))
            }
            if let u = chunk.usage {
                usage = Usage(
                    inputTokens: u.promptTokens,
                    outputTokens: u.completionTokens
                )
            }
            for choice in chunk.choices {
                if let content = choice.delta.content, !content.isEmpty {
                    if !textStarted {
                        textStarted = true
                        emit(.contentBlockStart(ContentBlockStartEvent(
                            index: 0, contentBlock: .text("")
                        )))
                    }
                    emit(.contentBlockDelta(ContentBlockDeltaEvent(
                        index: 0, delta: .textDelta(content)
                    )))
                }
                for delta in choice.delta.toolCalls {
                    let state = toolCalls[delta.index] ?? ToolCallState(openaiIndex: delta.index)
                    var mut = state
                    mut.apply(delta)
                    // emit start if we just learned the name
                    if mut.name != nil, !mut.started {
                        mut.started = true
                        let id = mut.id ?? "tool_call_\(mut.openaiIndex)"
                        emit(.contentBlockStart(ContentBlockStartEvent(
                            index: mut.blockIndex(),
                            contentBlock: .toolUse(id: id, name: mut.name!, input: .object([:]))
                        )))
                    }
                    if mut.started, mut.arguments.count > mut.emittedLen {
                        let start = mut.arguments.index(mut.arguments.startIndex, offsetBy: mut.emittedLen)
                        let suffix = String(mut.arguments[start...])
                        emit(.contentBlockDelta(ContentBlockDeltaEvent(
                            index: mut.blockIndex(),
                            delta: .inputJsonDelta(suffix)
                        )))
                        mut.emittedLen = mut.arguments.count
                    }
                    toolCalls[delta.index] = mut
                }
                if let reason = choice.finishReason {
                    let normalized: String
                    switch reason {
                    case "stop": normalized = "end_turn"
                    case "tool_calls": normalized = "tool_use"
                    default: normalized = reason
                    }
                    stopReason = normalized
                    if normalized == "tool_use" {
                        for (key, var state) in toolCalls where state.started && !state.stopped {
                            emit(.contentBlockStop(ContentBlockStopEvent(index: state.blockIndex())))
                            state.stopped = true
                            toolCalls[key] = state
                        }
                    }
                }
            }
        }

        func finish(emit: (StreamEvent) -> Void) {
            if finished { return }
            finished = true
            if textStarted && !textFinished {
                textFinished = true
                emit(.contentBlockStop(ContentBlockStopEvent(index: 0)))
            }
            for (_, var state) in toolCalls {
                if !state.started, state.name != nil {
                    state.started = true
                    let id = state.id ?? "tool_call_\(state.openaiIndex)"
                    emit(.contentBlockStart(ContentBlockStartEvent(
                        index: state.blockIndex(),
                        contentBlock: .toolUse(id: id, name: state.name!, input: .object([:]))
                    )))
                }
                if state.started, state.arguments.count > state.emittedLen {
                    let start = state.arguments.index(state.arguments.startIndex, offsetBy: state.emittedLen)
                    let suffix = String(state.arguments[start...])
                    emit(.contentBlockDelta(ContentBlockDeltaEvent(
                        index: state.blockIndex(), delta: .inputJsonDelta(suffix)
                    )))
                    state.emittedLen = state.arguments.count
                }
                if state.started, !state.stopped {
                    emit(.contentBlockStop(ContentBlockStopEvent(index: state.blockIndex())))
                }
            }
            if messageStarted {
                emit(.messageDelta(MessageDeltaEvent(
                    delta: MessageDelta(stopReason: stopReason ?? "end_turn", stopSequence: nil),
                    usage: usage ?? Usage()
                )))
                emit(.messageStop(MessageStopEvent()))
            }
        }
    }

    struct ToolCallState {
        var openaiIndex: UInt32
        var id: String?
        var name: String?
        var arguments: String = ""
        var emittedLen: Int = 0
        var started: Bool = false
        var stopped: Bool = false

        mutating func apply(_ delta: DeltaToolCall) {
            if let id = delta.id { self.id = id }
            if let n = delta.function.name { self.name = n }
            if let args = delta.function.arguments { arguments += args }
        }

        func blockIndex() -> UInt32 { openaiIndex + 1 }
    }

    // MARK: - Wire-level chunk DTOs

    struct ChatCompletionChunk: Sendable {
        let id: String
        let model: String?
        let choices: [ChunkChoice]
        let usage: OpenAiUsage?

        static func decode(_ payload: String) -> ChatCompletionChunk? {
            guard let data = payload.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            let id = obj["id"] as? String ?? ""
            let model = obj["model"] as? String
            let usage: OpenAiUsage? = {
                guard let u = obj["usage"] as? [String: Any] else { return nil }
                return OpenAiUsage(
                    promptTokens: UInt32((u["prompt_tokens"] as? Int) ?? 0),
                    completionTokens: UInt32((u["completion_tokens"] as? Int) ?? 0)
                )
            }()
            var choices: [ChunkChoice] = []
            for c in obj["choices"] as? [[String: Any]] ?? [] {
                let delta = c["delta"] as? [String: Any] ?? [:]
                let content = delta["content"] as? String
                var toolCalls: [DeltaToolCall] = []
                for tc in delta["tool_calls"] as? [[String: Any]] ?? [] {
                    let idx = UInt32((tc["index"] as? Int) ?? 0)
                    let tid = tc["id"] as? String
                    var fnName: String?, fnArgs: String?
                    if let fn = tc["function"] as? [String: Any] {
                        fnName = fn["name"] as? String
                        fnArgs = fn["arguments"] as? String
                    }
                    toolCalls.append(DeltaToolCall(
                        index: idx,
                        id: tid,
                        function: DeltaFunction(name: fnName, arguments: fnArgs)
                    ))
                }
                choices.append(ChunkChoice(
                    delta: ChunkDelta(content: content, toolCalls: toolCalls),
                    finishReason: c["finish_reason"] as? String
                ))
            }
            return ChatCompletionChunk(id: id, model: model, choices: choices, usage: usage)
        }
    }

    struct ChunkChoice: Sendable {
        let delta: ChunkDelta
        let finishReason: String?
    }

    struct ChunkDelta: Sendable {
        let content: String?
        let toolCalls: [DeltaToolCall]
    }

    struct DeltaToolCall: Sendable {
        let index: UInt32
        let id: String?
        let function: DeltaFunction
    }

    struct DeltaFunction: Sendable {
        let name: String?
        let arguments: String?
    }

    struct OpenAiUsage: Sendable {
        let promptTokens: UInt32
        let completionTokens: UInt32
    }
}
