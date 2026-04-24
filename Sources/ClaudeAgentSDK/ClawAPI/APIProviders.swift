import Foundation

extension ClawAPI {

    // MARK: - Provider enumeration + metadata

    public enum ProviderKind: String, Sendable, Codable, Equatable, Hashable {
        case anthropic
        case xai
        case openai
    }

    public struct ProviderMetadata: Sendable, Equatable {
        public let provider: ProviderKind
        public let authEnv: String
        public let baseUrlEnv: String
        public let defaultBaseUrl: String

        public init(provider: ProviderKind, authEnv: String, baseUrlEnv: String, defaultBaseUrl: String) {
            self.provider = provider
            self.authEnv = authEnv
            self.baseUrlEnv = baseUrlEnv
            self.defaultBaseUrl = defaultBaseUrl
        }
    }

    public struct ModelTokenLimit: Sendable, Equatable {
        public let maxOutputTokens: UInt32
        public let contextWindowTokens: UInt32
    }

    // MARK: - Static registry

    /// Alias → canonical model id. Kept in one place for clarity.
    public static let modelRegistry: [String: (canonical: String, metadata: ProviderMetadata)] = [
        "opus": ("claude-opus-4-6", anthropicMetadata),
        "sonnet": ("claude-sonnet-4-6", anthropicMetadata),
        "haiku": ("claude-haiku-4-5-20251213", anthropicMetadata),
        "grok": ("grok-3", xaiMetadata),
        "grok-3": ("grok-3", xaiMetadata),
        "grok-mini": ("grok-3-mini", xaiMetadata),
        "grok-3-mini": ("grok-3-mini", xaiMetadata),
        "grok-2": ("grok-2", xaiMetadata),
        "kimi": ("kimi-k2.5", dashscopeMetadata),
    ]

    public static let anthropicMetadata = ProviderMetadata(
        provider: .anthropic,
        authEnv: "ANTHROPIC_API_KEY",
        baseUrlEnv: "ANTHROPIC_BASE_URL",
        defaultBaseUrl: "https://api.anthropic.com"
    )

    public static let xaiMetadata = ProviderMetadata(
        provider: .xai,
        authEnv: "XAI_API_KEY",
        baseUrlEnv: "XAI_BASE_URL",
        defaultBaseUrl: "https://api.x.ai/v1"
    )

    public static let openaiMetadata = ProviderMetadata(
        provider: .openai,
        authEnv: "OPENAI_API_KEY",
        baseUrlEnv: "OPENAI_BASE_URL",
        defaultBaseUrl: "https://api.openai.com/v1"
    )

    public static let dashscopeMetadata = ProviderMetadata(
        provider: .openai,
        authEnv: "DASHSCOPE_API_KEY",
        baseUrlEnv: "DASHSCOPE_BASE_URL",
        defaultBaseUrl: "https://dashscope.aliyuncs.com/compatible-mode/v1"
    )

    // MARK: - Model alias + metadata helpers

    public static func resolveModelAlias(_ model: String) -> String {
        let trimmed = model.trimmingCharacters(in: .whitespaces).lowercased()
        if let entry = modelRegistry[trimmed] { return entry.canonical }
        return model.trimmingCharacters(in: .whitespaces)
    }

    public static func metadataForModel(
        _ model: String, environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> ProviderMetadata? {
        let canonical = resolveModelAlias(model).lowercased()
        if canonical.hasPrefix("claude") { return anthropicMetadata }
        if canonical.hasPrefix("grok") { return xaiMetadata }
        if canonical.hasPrefix("openai/") || canonical.hasPrefix("gpt-") { return openaiMetadata }
        if canonical.hasPrefix("qwen/") || canonical.hasPrefix("qwen-") { return dashscopeMetadata }
        if canonical.hasPrefix("kimi/") || canonical.hasPrefix("kimi-") { return dashscopeMetadata }
        _ = environment  // reserved for future env-based routing
        return nil
    }

    /// Detect which provider should handle a model, consulting env vars for
    /// unknown models. Mirrors the precedence logic in `api::providers`.
    public static func detectProviderKind(
        _ model: String, environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> ProviderKind {
        if let m = metadataForModel(model, environment: environment) { return m.provider }
        let openaiBase = environment["OPENAI_BASE_URL"] ?? ""
        let openaiKey = envOrDotenv(environment, key: "OPENAI_API_KEY")
        if !openaiBase.isEmpty && !openaiKey.isEmpty { return .openai }
        if !envOrDotenv(environment, key: "ANTHROPIC_API_KEY").isEmpty
            || !envOrDotenv(environment, key: "ANTHROPIC_AUTH_TOKEN").isEmpty {
            return .anthropic
        }
        if !openaiKey.isEmpty { return .openai }
        if !envOrDotenv(environment, key: "XAI_API_KEY").isEmpty { return .xai }
        if !openaiBase.isEmpty { return .openai }
        return .anthropic
    }

    // MARK: - Max tokens

    public static func modelTokenLimit(_ model: String) -> ModelTokenLimit? {
        let canonical = resolveModelAlias(model).lowercased()
        switch canonical {
        case "claude-opus-4-6":
            return ModelTokenLimit(maxOutputTokens: 32_000, contextWindowTokens: 200_000)
        case "claude-sonnet-4-6", "claude-haiku-4-5-20251213":
            return ModelTokenLimit(maxOutputTokens: 64_000, contextWindowTokens: 200_000)
        case "grok-3", "grok-3-mini":
            return ModelTokenLimit(maxOutputTokens: 64_000, contextWindowTokens: 131_072)
        case "kimi-k2.5", "kimi-k1.5":
            return ModelTokenLimit(maxOutputTokens: 16_384, contextWindowTokens: 256_000)
        default: return nil
        }
    }

    public static func maxTokensForModel(_ model: String) -> UInt32 {
        if let limit = modelTokenLimit(model) { return limit.maxOutputTokens }
        return resolveModelAlias(model).lowercased().contains("opus") ? 32_000 : 64_000
    }

    public static func maxTokensForModel(_ model: String, override: UInt32?) -> UInt32 {
        override ?? maxTokensForModel(model)
    }

    // MARK: - Preflight

    /// Estimate input tokens for a value via serialized byte count / 4.
    public static func estimateSerializedTokens(_ value: some Encodable) -> UInt32 {
        let bytes = (try? JSONEncoder().encode(value)) ?? Data()
        return UInt32(bytes.count / 4 + 1)
    }

    /// Preflight check against known model context windows. Returns nil if
    /// no context-window info is known for the model.
    public static func preflightMessageRequest(_ request: MessageRequest) throws {
        guard let limit = modelTokenLimit(request.model) else { return }
        var total: UInt32 = 0
        total &+= request.messages.reduce(0) { $0 &+ estimateSerializedTokens($1) }
        if let system = request.system {
            total &+= estimateSerializedTokens(system)
        }
        if let tools = request.tools {
            total &+= estimateSerializedTokens(tools)
        }
        if let tc = request.toolChoice {
            total &+= estimateSerializedTokens(tc)
        }
        let requested = request.maxTokens
        let sum = total &+ requested
        if sum > limit.contextWindowTokens {
            throw ApiError.contextWindowExceeded(
                model: resolveModelAlias(request.model),
                estimatedInputTokens: total,
                requestedOutputTokens: requested,
                estimatedTotalTokens: sum,
                contextWindowTokens: limit.contextWindowTokens
            )
        }
    }

    // MARK: - dotenv support

    /// Parse minimal `.env` file content into a dictionary.
    public static func parseDotenv(_ content: String) -> [String: String] {
        var result: [String: String] = [:]
        for rawLine in content.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = String(rawLine)
            // strip CR from CRLF
            if line.hasSuffix("\r") { line.removeLast() }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            // strip leading "export "
            var body = trimmed
            if body.hasPrefix("export ") { body.removeFirst("export ".count) }
            guard let eq = body.firstIndex(of: "=") else { continue }
            let key = body[..<eq].trimmingCharacters(in: .whitespaces)
            if key.isEmpty { continue }
            var value = String(body[body.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            // strip matched paired quotes
            if value.count >= 2 {
                let first = value.first!, last = value.last!
                if (first == "\"" && last == "\"") || (first == "'" && last == "'") {
                    value.removeFirst()
                    value.removeLast()
                }
            }
            result[key] = value
        }
        return result
    }

    /// Load `.env` from the current working directory, if present.
    public static func loadDotenvFile(_ path: String) -> [String: String]? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let s = String(data: data, encoding: .utf8) else { return nil }
        return parseDotenv(s)
    }

    /// Look up a key in the given environment, falling back to `./.env`.
    public static func envOrDotenv(_ env: [String: String], key: String) -> String {
        if let v = env[key], !v.isEmpty { return v }
        let cwd = FileManager.default.currentDirectoryPath
        let dotenv = (cwd as NSString).appendingPathComponent(".env")
        if let vals = loadDotenvFile(dotenv), let v = vals[key], !v.isEmpty {
            return v
        }
        return ""
    }

    /// Compose an Anthropic "missing credentials" hint if a foreign provider
    /// env var is set (indicating possible misrouting).
    public static func anthropicMissingCredentialsHint(
        _ env: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        let foreign: [(String, String, String)] = [
            ("OPENAI_API_KEY", "OpenAI",
             "set ANTHROPIC_API_KEY or pass --model openai/<name> / gpt-<name>."),
            ("XAI_API_KEY", "xAI",
             "set ANTHROPIC_API_KEY or pass --model grok-3."),
            ("DASHSCOPE_API_KEY", "DashScope",
             "set ANTHROPIC_API_KEY or pass --model qwen-<name> / kimi-<name>."),
        ]
        for (key, label, fix) in foreign {
            if !envOrDotenv(env, key: key).isEmpty {
                return "I see \(key) is set — if you meant to use the \(label) provider, \(fix)"
            }
        }
        return nil
    }

    public static func anthropicMissingCredentialsError(
        _ env: [String: String] = ProcessInfo.processInfo.environment
    ) -> ApiError {
        .missingCredentials(
            provider: "Anthropic",
            envVars: ["ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_API_KEY"],
            hint: anthropicMissingCredentialsHint(env)
        )
    }
}
