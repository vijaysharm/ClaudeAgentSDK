import Foundation

/// Namespace for types ported from the Rust `runtime` crate of
/// `instructkr/claude-code`.
///
/// This layer does not execute any agent loop itself — it provides the
/// configuration, permission, policy, hook, session, MCP client, and worker
/// state machinery that a harness can compose on top of the ``ClawAPI`` client.
public enum ClawRuntime {}
