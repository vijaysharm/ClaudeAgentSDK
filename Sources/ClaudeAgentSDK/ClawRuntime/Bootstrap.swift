import Foundation

extension ClawRuntime {

    /// Claw Code bootstrap phases, in the order they're exercised at startup.
    public enum BootstrapPhase: String, Codable, Sendable, CaseIterable, Equatable {
        case cliEntry
        case fastPathVersion
        case startupProfiler
        case systemPromptFastPath
        case chromeMcpFastPath
        case daemonWorkerFastPath
        case bridgeFastPath
        case daemonFastPath
        case backgroundSessionFastPath
        case templateFastPath
        case environmentRunnerFastPath
        case mainRuntime
    }

    public struct BootstrapPlan: Sendable, Equatable, Codable {
        public var phases: [BootstrapPhase]

        public init(phases: [BootstrapPhase]) {
            self.phases = phases
        }

        /// Canonical phase order used by `claude-code` at startup.
        public static func claudeCodeDefault() -> BootstrapPlan {
            BootstrapPlan(phases: [
                .cliEntry,
                .fastPathVersion,
                .startupProfiler,
                .systemPromptFastPath,
                .chromeMcpFastPath,
                .daemonWorkerFastPath,
                .bridgeFastPath,
                .daemonFastPath,
                .backgroundSessionFastPath,
                .templateFastPath,
                .environmentRunnerFastPath,
                .mainRuntime,
            ])
        }

        /// Build a plan from an arbitrary list, keeping only the first
        /// occurrence of each phase.
        public static func fromPhases(_ phases: [BootstrapPhase]) -> BootstrapPlan {
            var seen: Set<BootstrapPhase> = []
            var result: [BootstrapPhase] = []
            for p in phases where !seen.contains(p) {
                result.append(p)
                seen.insert(p)
            }
            return BootstrapPlan(phases: result)
        }
    }
}
