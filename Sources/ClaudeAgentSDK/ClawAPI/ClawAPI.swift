import Foundation

/// Provider-agnostic API surface ported from the Rust `api` crate of
/// the instructkr/claude-code (Claw Code) project.
///
/// The types live inside the ``ClawAPI`` caseless-enum namespace to avoid
/// colliding with the existing ``Native/Anthropic`` layer. The two paths
/// are intentionally independent — ``ClawAPI`` speaks to multiple
/// providers (Anthropic, xAI, OpenAI-compatible endpoints such as DashScope
/// for Qwen/Kimi) via a façade client, with prompt-cache, retry, and SSE
/// translation baked in.
///
/// See:
/// - ``ClawAPI/MessageRequest`` for the request body
/// - ``ClawAPI/ProviderClient`` for the façade entry point
/// - ``ClawAPI/PromptCache`` for the on-disk completion cache
public enum ClawAPI {}
