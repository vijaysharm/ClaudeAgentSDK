import Foundation

extension ClawRuntime {

    public enum FailureScenario: String, Sendable, Codable, Equatable, CaseIterable {
        case trustPromptUnresolved = "trust_prompt_unresolved"
        case promptMisdelivery = "prompt_misdelivery"
        case staleBranch = "stale_branch"
        case compileRedCrossCrate = "compile_red_cross_crate"
        case mcpHandshakeFailure = "mcp_handshake_failure"
        case partialPluginStartup = "partial_plugin_startup"
        case providerFailure = "provider_failure"

        public static func fromWorkerFailureKind(_ kind: WorkerFailureKind) -> FailureScenario {
            switch kind {
            case .trustGate: return .trustPromptUnresolved
            case .promptDelivery: return .promptMisdelivery
            case .protocolFailure: return .mcpHandshakeFailure
            case .provider, .startupNoEvidence: return .providerFailure
            }
        }
    }

    public enum RecoveryStep: Sendable, Equatable {
        case acceptTrustPrompt
        case redirectPromptToAgent
        case rebaseBranch
        case cleanBuild
        case retryMcpHandshake(timeoutMs: UInt64)
        case restartPlugin(name: String)
        case restartWorker
        case escalateToHuman(reason: String)
    }

    public enum EscalationPolicy: String, Sendable, Codable, Equatable {
        case alertHuman
        case logAndContinue
        case abort
    }

    public struct RecoveryRecipe: Sendable, Equatable {
        public var scenario: FailureScenario
        public var steps: [RecoveryStep]
        public var maxAttempts: UInt32
        public var escalationPolicy: EscalationPolicy
    }

    public enum RecoveryResult: Sendable, Equatable {
        case recovered(stepsTaken: UInt32)
        case partialRecovery(recovered: [RecoveryStep], remaining: [RecoveryStep])
        case escalationRequired(reason: String)
    }

    public enum RecoveryEvent: Sendable, Equatable {
        case recoveryAttempted(FailureScenario, RecoveryRecipe, RecoveryResult)
        case recoverySucceeded
        case recoveryFailed
        case escalated
    }

    public struct RecoveryContext: Sendable, Equatable {
        public var attempts: [FailureScenario: UInt32] = [:]
        public var events: [RecoveryEvent] = []
        public var failAtStep: Int?

        public init(failAtStep: Int? = nil) {
            self.failAtStep = failAtStep
        }

        public mutating func withFailAtStep(_ index: Int) -> RecoveryContext {
            failAtStep = index
            return self
        }

        public func attemptCount(_ s: FailureScenario) -> UInt32 {
            attempts[s] ?? 0
        }
    }

    /// Rust's `worker_boot::WorkerFailureKind` — kept in this file so we don't
    /// need to forward-declare it across the port.
    public enum WorkerFailureKind: String, Sendable, Codable, Equatable {
        case trustGate = "trust_gate"
        case promptDelivery = "prompt_delivery"
        case protocolFailure = "protocol"
        case provider
        case startupNoEvidence = "startup_no_evidence"
    }

    public static func recipeFor(_ scenario: FailureScenario) -> RecoveryRecipe {
        switch scenario {
        case .trustPromptUnresolved:
            return RecoveryRecipe(
                scenario: scenario,
                steps: [.acceptTrustPrompt],
                maxAttempts: 1, escalationPolicy: .alertHuman
            )
        case .promptMisdelivery:
            return RecoveryRecipe(
                scenario: scenario, steps: [.redirectPromptToAgent],
                maxAttempts: 1, escalationPolicy: .alertHuman
            )
        case .staleBranch:
            return RecoveryRecipe(
                scenario: scenario, steps: [.rebaseBranch, .cleanBuild],
                maxAttempts: 1, escalationPolicy: .alertHuman
            )
        case .compileRedCrossCrate:
            return RecoveryRecipe(
                scenario: scenario, steps: [.cleanBuild],
                maxAttempts: 1, escalationPolicy: .alertHuman
            )
        case .mcpHandshakeFailure:
            return RecoveryRecipe(
                scenario: scenario,
                steps: [.retryMcpHandshake(timeoutMs: 5000)],
                maxAttempts: 1, escalationPolicy: .abort
            )
        case .partialPluginStartup:
            return RecoveryRecipe(
                scenario: scenario,
                steps: [.restartPlugin(name: "stalled"),
                        .retryMcpHandshake(timeoutMs: 3000)],
                maxAttempts: 1, escalationPolicy: .logAndContinue
            )
        case .providerFailure:
            return RecoveryRecipe(
                scenario: scenario, steps: [.restartWorker],
                maxAttempts: 1, escalationPolicy: .alertHuman
            )
        }
    }

    public static func attemptRecovery(
        _ scenario: FailureScenario, context: inout RecoveryContext
    ) -> RecoveryResult {
        let recipe = recipeFor(scenario)
        let attempts = context.attemptCount(scenario)
        if attempts >= recipe.maxAttempts {
            let result = RecoveryResult.escalationRequired(reason: "max attempts exceeded")
            context.events.append(.recoveryAttempted(scenario, recipe, result))
            context.events.append(.escalated)
            return result
        }
        context.attempts[scenario] = attempts + 1

        var recovered: [RecoveryStep] = []
        var remaining: [RecoveryStep] = []
        var failed = false
        for (i, step) in recipe.steps.enumerated() {
            if let fail = context.failAtStep, i == fail {
                remaining = Array(recipe.steps[i...])
                failed = true
                break
            }
            recovered.append(step)
        }
        let result: RecoveryResult
        if !failed {
            result = .recovered(stepsTaken: UInt32(recovered.count))
            context.events.append(.recoveryAttempted(scenario, recipe, result))
            context.events.append(.recoverySucceeded)
        } else if recovered.isEmpty {
            result = .escalationRequired(reason: "first step failed")
            context.events.append(.recoveryAttempted(scenario, recipe, result))
            context.events.append(.escalated)
        } else {
            result = .partialRecovery(recovered: recovered, remaining: remaining)
            context.events.append(.recoveryAttempted(scenario, recipe, result))
            context.events.append(.recoveryFailed)
        }
        return result
    }
}
