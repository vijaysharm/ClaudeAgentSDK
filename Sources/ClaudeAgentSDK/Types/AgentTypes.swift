import Foundation

/// Definition for a custom subagent that can be invoked via the Agent tool.
public struct AgentDefinition: Codable, Sendable {
    /// Natural language description of when to use this agent.
    public let description: String
    /// Array of allowed tool names. If omitted, inherits all tools from parent.
    public let tools: [String]?
    /// Array of tool names to explicitly disallow for this agent.
    public let disallowedTools: [String]?
    /// The agent's system prompt.
    public let prompt: String
    /// Model alias or full model ID. If omitted, uses the main model.
    public let model: String?
    /// Maximum number of agentic turns before stopping.
    public let maxTurns: Int?
    /// Array of skill names to preload into the agent context.
    public let skills: [String]?

    public init(
        description: String,
        prompt: String,
        tools: [String]? = nil,
        disallowedTools: [String]? = nil,
        model: String? = nil,
        maxTurns: Int? = nil,
        skills: [String]? = nil
    ) {
        self.description = description
        self.prompt = prompt
        self.tools = tools
        self.disallowedTools = disallowedTools
        self.model = model
        self.maxTurns = maxTurns
        self.skills = skills
    }
}

/// Information about an available subagent.
public struct AgentInfo: Codable, Sendable {
    /// Agent type identifier.
    public let name: String
    /// Description of when to use this agent.
    public let description: String
    /// Model alias this agent uses.
    public let model: String?
}
