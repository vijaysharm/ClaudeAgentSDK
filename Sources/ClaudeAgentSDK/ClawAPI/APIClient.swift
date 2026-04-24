import Foundation

extension ClawAPI {

    /// Top-level provider-agnostic client. Dispatches to the right provider
    /// client based on the model name or environment.
    public final class ProviderClient: @unchecked Sendable {
        public enum Inner: @unchecked Sendable {
            case anthropic(AnthropicClient)
            case xai(OpenAiCompatClient)
            case openai(OpenAiCompatClient)
        }

        public let inner: Inner
        public let kind: ProviderKind

        public init(_ inner: Inner) {
            self.inner = inner
            switch inner {
            case .anthropic: self.kind = .anthropic
            case .xai: self.kind = .xai
            case .openai: self.kind = .openai
            }
        }

        /// Build a client for the given model, falling back to env vars.
        public static func forModel(
            _ model: String,
            anthropicAuth: AuthSource? = nil,
            env: [String: String] = ProcessInfo.processInfo.environment
        ) throws -> ProviderClient {
            let canonical = resolveModelAlias(model)
            let kind = detectProviderKind(canonical, environment: env)
            switch kind {
            case .anthropic:
                if let auth = anthropicAuth {
                    return ProviderClient(.anthropic(AnthropicClient(auth: auth)))
                }
                return try ProviderClient(.anthropic(AnthropicClient(fromEnvironment: env)))
            case .xai:
                return try ProviderClient(.xai(
                    OpenAiCompatClient.fromEnvironment(config: .xai, env: env)
                ))
            case .openai:
                let config: OpenAiCompatConfig
                if let metadata = metadataForModel(canonical, environment: env),
                   metadata.authEnv == "DASHSCOPE_API_KEY" {
                    config = .dashscope
                } else {
                    config = .openai
                }
                return try ProviderClient(.openai(
                    OpenAiCompatClient.fromEnvironment(config: config, env: env)
                ))
            }
        }

        public func sendMessage(_ request: MessageRequest) async throws -> MessageResponse {
            switch inner {
            case .anthropic(let c): return try await c.sendMessage(request)
            case .xai(let c): return try await c.sendMessage(request)
            case .openai(let c): return try await c.sendMessage(request)
            }
        }

        public func streamMessage(_ request: MessageRequest) -> AsyncThrowingStream<StreamEvent, Error> {
            switch inner {
            case .anthropic(let c): return c.streamMessage(request)
            case .xai(let c): return c.streamMessage(request)
            case .openai(let c): return c.streamMessage(request)
            }
        }

        public var anthropicClient: AnthropicClient? {
            if case .anthropic(let c) = inner { return c }
            return nil
        }
    }

    // MARK: - Convenience env readers

    public static func readBaseURL(
        _ env: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        let v = envOrDotenv(env, key: "ANTHROPIC_BASE_URL")
        return v.isEmpty ? "https://api.anthropic.com" : v
    }

    public static func readXaiBaseURL(
        _ env: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        let v = envOrDotenv(env, key: "XAI_BASE_URL")
        return v.isEmpty ? "https://api.x.ai/v1" : v
    }

    public static func hasAuthFromEnvOrSaved(
        _ env: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        !envOrDotenv(env, key: "ANTHROPIC_API_KEY").isEmpty
            || !envOrDotenv(env, key: "ANTHROPIC_AUTH_TOKEN").isEmpty
    }
}
