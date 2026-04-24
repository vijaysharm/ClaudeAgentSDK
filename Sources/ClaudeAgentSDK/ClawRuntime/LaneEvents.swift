import Foundation

extension ClawRuntime {

    // MARK: - Enums

    public enum LaneEventName: String, Sendable, Codable, Equatable {
        case started = "lane.started"
        case ready = "lane.ready"
        case blocked = "lane.blocked"
        case red = "lane.red"
        case green = "lane.green"
        case promptMisdelivery = "lane.prompt_misdelivery"
        case commitCreated = "lane.commit.created"
        case prOpened = "lane.pr.opened"
        case mergeReady = "lane.merge.ready"
        case finished = "lane.finished"
        case failed = "lane.failed"
        case reconciled = "lane.reconciled"
        case merged = "lane.merged"
        case superseded = "lane.superseded"
        case closed = "lane.closed"
        case branchStale = "branch.stale_against_main"
        case branchWorkspaceMismatch = "branch.workspace_mismatch"
        case shipPrepared = "ship.prepared"
        case shipCommitsSelected = "ship.commits_selected"
        case shipMerged = "ship.merged"
        case shipPushedMain = "ship.pushed_main"
    }

    public enum LaneEventStatus: String, Sendable, Codable, Equatable {
        case running, ready, blocked, red, green, completed, failed
        case reconciled, merged, superseded, closed
    }

    public enum LaneFailureClass: String, Sendable, Codable, Equatable {
        case promptDelivery
        case trustGate
        case branchDivergence
        case compile
        case test
        case pluginStartup
        case mcpStartup
        case mcpHandshake
        case gatewayRouting
        case toolRuntime
        case workspaceMismatch
        case infra
    }

    public enum EventProvenance: String, Sendable, Codable, Equatable {
        case liveLane = "live_lane"
        case test, healthcheck, replay, transport
    }

    public enum WatcherAction: String, Sendable, Codable, Equatable {
        case act, observe, ignore
    }

    public enum BlockedSubphase: Sendable, Equatable, Codable {
        case trustPrompt(gateRepo: String)
        case promptDelivery(attempt: UInt32)
        case pluginInit(pluginName: String)
        case mcpHandshake(serverName: String, attempt: UInt32)
        case branchFreshness(behindMain: UInt32)
        case testHang(elapsedSecs: UInt32, testName: String)
        case reportPending(sinceSecs: UInt32)

        private enum CodingKeys: String, CodingKey {
            case type, gateRepo, attempt, pluginName
            case serverName, behindMain, elapsedSecs, testName, sinceSecs
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            switch try c.decode(String.self, forKey: .type) {
            case "trust_prompt":
                self = .trustPrompt(gateRepo: try c.decode(String.self, forKey: .gateRepo))
            case "prompt_delivery":
                self = .promptDelivery(attempt: try c.decode(UInt32.self, forKey: .attempt))
            case "plugin_init":
                self = .pluginInit(pluginName: try c.decode(String.self, forKey: .pluginName))
            case "mcp_handshake":
                self = .mcpHandshake(
                    serverName: try c.decode(String.self, forKey: .serverName),
                    attempt: try c.decode(UInt32.self, forKey: .attempt)
                )
            case "branch_freshness":
                self = .branchFreshness(behindMain: try c.decode(UInt32.self, forKey: .behindMain))
            case "test_hang":
                self = .testHang(
                    elapsedSecs: try c.decode(UInt32.self, forKey: .elapsedSecs),
                    testName: try c.decode(String.self, forKey: .testName)
                )
            case "report_pending":
                self = .reportPending(sinceSecs: try c.decode(UInt32.self, forKey: .sinceSecs))
            default:
                throw DecodingError.dataCorruptedError(
                    forKey: .type, in: c, debugDescription: "unknown subphase")
            }
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .trustPrompt(let r):
                try c.encode("trust_prompt", forKey: .type)
                try c.encode(r, forKey: .gateRepo)
            case .promptDelivery(let a):
                try c.encode("prompt_delivery", forKey: .type)
                try c.encode(a, forKey: .attempt)
            case .pluginInit(let n):
                try c.encode("plugin_init", forKey: .type)
                try c.encode(n, forKey: .pluginName)
            case .mcpHandshake(let s, let a):
                try c.encode("mcp_handshake", forKey: .type)
                try c.encode(s, forKey: .serverName)
                try c.encode(a, forKey: .attempt)
            case .branchFreshness(let b):
                try c.encode("branch_freshness", forKey: .type)
                try c.encode(b, forKey: .behindMain)
            case .testHang(let e, let name):
                try c.encode("test_hang", forKey: .type)
                try c.encode(e, forKey: .elapsedSecs)
                try c.encode(name, forKey: .testName)
            case .reportPending(let s):
                try c.encode("report_pending", forKey: .type)
                try c.encode(s, forKey: .sinceSecs)
            }
        }
    }

    public enum ShipMergeMethod: String, Sendable, Codable, Equatable {
        case directPush, fastForward, mergeCommit, squashMerge, rebaseMerge
    }

    // MARK: - Structs

    public struct SessionIdentity: Sendable, Equatable, Codable {
        public var title: String
        public var workspace: String
        public var purpose: String
        public var placeholderReason: String?

        public init(title: String, workspace: String, purpose: String, placeholderReason: String? = nil) {
            self.title = title
            self.workspace = workspace
            self.purpose = purpose
            self.placeholderReason = placeholderReason
        }
    }

    public struct LaneOwnership: Sendable, Equatable, Codable {
        public var owner: String
        public var workflowScope: String
        public var watcherAction: WatcherAction
    }

    public struct LaneEventMetadata: Sendable, Equatable, Codable {
        public var seq: UInt64
        public var provenance: EventProvenance
        public var sessionIdentity: SessionIdentity?
        public var ownership: LaneOwnership?
        public var nudgeId: String?
        public var eventFingerprint: String?
        public var timestampMs: UInt64

        public init(seq: UInt64, provenance: EventProvenance) {
            self.seq = seq
            self.provenance = provenance
            self.timestampMs = UInt64(Date().timeIntervalSince1970 * 1000)
        }
    }

    public struct LaneEventBlocker: Sendable, Equatable, Codable {
        public var failureClass: LaneFailureClass?
        public var detail: String?
        public var subphase: BlockedSubphase?
    }

    public struct LaneCommitProvenance: Sendable, Equatable, Codable {
        public var commit: String
        public var branch: String
        public var worktree: String?
        public var canonicalCommit: String?
        public var supersededBy: String?
        public var lineage: [String]
    }

    public struct ShipProvenance: Sendable, Equatable, Codable {
        public var sourceBranch: String
        public var baseCommit: String
        public var commitCount: UInt32
        public var commitRange: String
        public var mergeMethod: ShipMergeMethod
        public var actor: String?
        public var prNumber: UInt64?
    }

    public struct LaneEvent: Sendable, Equatable, Codable {
        public var event: LaneEventName
        public var status: LaneEventStatus
        public var emittedAt: UInt64
        public var failureClass: LaneFailureClass?
        public var detail: String?
        public var data: AnyCodable?
        public var metadata: LaneEventMetadata

        public init(
            event: LaneEventName, status: LaneEventStatus,
            emittedAt: UInt64 = UInt64(Date().timeIntervalSince1970 * 1000),
            failureClass: LaneFailureClass? = nil, detail: String? = nil,
            data: AnyCodable? = nil, metadata: LaneEventMetadata
        ) {
            self.event = event
            self.status = status
            self.emittedAt = emittedAt
            self.failureClass = failureClass
            self.detail = detail
            self.data = data
            self.metadata = metadata
        }
    }

    public static let terminalLaneEvents: Set<LaneEventName> = [
        .finished, .failed, .superseded, .closed, .merged,
    ]

    public static func isTerminalEvent(_ event: LaneEventName) -> Bool {
        terminalLaneEvents.contains(event)
    }

    public static func computeEventFingerprint(
        event: LaneEventName, status: LaneEventStatus, data: AnyCodable?
    ) -> String {
        var hash: UInt64 = 0
        hash = combine(hash, event.rawValue.utf8)
        hash = combine(hash, status.rawValue.utf8)
        if let d = data, let data = try? JSONEncoder().encode(d) {
            hash = combine(hash, Array(data))
        }
        return String(format: "%016x", hash)
    }

    private static func combine<S: Sequence>(_ initial: UInt64, _ bytes: S) -> UInt64
        where S.Element == UInt8 {
        var h = initial
        for b in bytes {
            h ^= UInt64(b)
            h = h &* 0x100000001b3
        }
        return h
    }
}
