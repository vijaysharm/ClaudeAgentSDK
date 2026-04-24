import Foundation

extension ClawRuntime {

    public typealias GreenLevel = UInt8

    public enum ReconcileReason: String, Sendable, Codable, Equatable {
        case alreadyMerged = "already_merged"
        case superseded
        case emptyDiff = "empty_diff"
        case manualClose = "manual_close"
    }

    public enum LaneBlocker: String, Sendable, Codable, Equatable {
        case none
        case startup
        case external
    }

    public enum ReviewStatus: String, Sendable, Codable, Equatable {
        case pending, approved, rejected
    }

    public enum DiffScope: String, Sendable, Codable, Equatable {
        case full, scoped
    }

    public indirect enum PolicyCondition: Sendable, Equatable {
        case and([PolicyCondition])
        case or([PolicyCondition])
        case greenAt(level: GreenLevel)
        case staleBranch
        case startupBlocked
        case laneCompleted
        case laneReconciled
        case reviewPassed
        case scopedDiff
        case timedOut(duration: TimeInterval)

        public static let staleBranchThreshold: TimeInterval = 3600

        public func matches(_ c: LaneContext) -> Bool {
            switch self {
            case .and(let conds):
                return conds.isEmpty || conds.allSatisfy { $0.matches(c) }
            case .or(let conds):
                return conds.contains { $0.matches(c) }
            case .greenAt(let level): return c.greenLevel >= level
            case .staleBranch: return c.branchFreshness >= PolicyCondition.staleBranchThreshold
            case .startupBlocked: return c.blocker == .startup
            case .laneCompleted: return c.completed
            case .laneReconciled: return c.reconciled
            case .reviewPassed: return c.reviewStatus == .approved
            case .scopedDiff: return c.diffScope == .scoped
            case .timedOut(let d): return c.branchFreshness >= d
            }
        }
    }

    public indirect enum PolicyAction: Sendable, Equatable {
        case mergeToDev
        case mergeForward
        case recoverOnce
        case escalate(reason: String)
        case closeoutLane
        case cleanupSession
        case reconcile(reason: ReconcileReason)
        case notify(channel: String)
        case block(reason: String)
        case chain([PolicyAction])
    }

    public struct PolicyRule: Sendable, Equatable {
        public var name: String
        public var condition: PolicyCondition
        public var action: PolicyAction
        public var priority: UInt32

        public init(name: String, condition: PolicyCondition, action: PolicyAction, priority: UInt32) {
            self.name = name
            self.condition = condition
            self.action = action
            self.priority = priority
        }

        public func matches(_ c: LaneContext) -> Bool { condition.matches(c) }
    }

    public struct LaneContext: Sendable, Equatable {
        public var laneId: String
        public var greenLevel: GreenLevel
        public var branchFreshness: TimeInterval
        public var blocker: LaneBlocker
        public var reviewStatus: ReviewStatus
        public var diffScope: DiffScope
        public var completed: Bool
        public var reconciled: Bool

        public init(
            laneId: String, greenLevel: GreenLevel,
            branchFreshness: TimeInterval, blocker: LaneBlocker,
            reviewStatus: ReviewStatus, diffScope: DiffScope,
            completed: Bool = false, reconciled: Bool = false
        ) {
            self.laneId = laneId
            self.greenLevel = greenLevel
            self.branchFreshness = branchFreshness
            self.blocker = blocker
            self.reviewStatus = reviewStatus
            self.diffScope = diffScope
            self.completed = completed
            self.reconciled = reconciled
        }

        public static func reconciled(laneId: String) -> LaneContext {
            LaneContext(
                laneId: laneId, greenLevel: 0, branchFreshness: 0,
                blocker: .none, reviewStatus: .pending, diffScope: .scoped,
                completed: true, reconciled: true
            )
        }
    }

    public struct PolicyEngine: Sendable, Equatable {
        public let rules: [PolicyRule]

        public init(rules: [PolicyRule]) {
            self.rules = rules.sorted(by: { $0.priority < $1.priority })
        }

        public func evaluate(_ c: LaneContext) -> [PolicyAction] {
            var out: [PolicyAction] = []
            for rule in rules where rule.matches(c) {
                switch rule.action {
                case .chain(let acts): out.append(contentsOf: acts)
                default: out.append(rule.action)
                }
            }
            return out
        }
    }

    public static func evaluate(_ engine: PolicyEngine, context: LaneContext) -> [PolicyAction] {
        engine.evaluate(context)
    }
}
