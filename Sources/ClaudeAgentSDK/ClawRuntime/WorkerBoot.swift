import Foundation

extension ClawRuntime {

    // MARK: - Worker enums (snake_case over the wire)

    public enum WorkerStatus: String, Sendable, Codable, Equatable {
        case spawning
        case trustRequired = "trust_required"
        case readyForPrompt = "ready_for_prompt"
        case running, finished, failed
    }

    public enum WorkerEventKind: String, Sendable, Codable, Equatable {
        case spawning
        case trustRequired = "trust_required"
        case trustResolved = "trust_resolved"
        case readyForPrompt = "ready_for_prompt"
        case promptMisdelivery = "prompt_misdelivery"
        case promptReplayArmed = "prompt_replay_armed"
        case running, restarted, finished, failed
        case startupNoEvidence = "startup_no_evidence"
    }

    public enum WorkerTrustResolution: String, Sendable, Codable, Equatable {
        case autoAllowlisted = "auto_allowlisted"
        case manualApproval = "manual_approval"
    }

    public enum WorkerPromptTarget: String, Sendable, Codable, Equatable {
        case shell
        case wrongTarget = "wrong_target"
        case wrongTask = "wrong_task"
        case unknown
    }

    public enum StartupFailureClassification: String, Sendable, Codable, Equatable {
        case trustRequired = "trust_required"
        case promptMisdelivery = "prompt_misdelivery"
        case promptAcceptanceTimeout = "prompt_acceptance_timeout"
        case transportDead = "transport_dead"
        case workerCrashed = "worker_crashed"
        case unknown
    }

    // MARK: - Event payload + receipt

    public struct StartupEvidenceBundle: Sendable, Equatable, Codable {
        public var lastLifecycleState: String?
        public var paneCommand: String?
        public var promptSentAt: UInt64?
        public var promptAcceptanceState: String?
        public var trustPromptDetected: Bool
        public var transportHealthy: Bool
        public var mcpHealthy: Bool
        public var elapsedSeconds: UInt64
    }

    public struct WorkerTaskReceipt: Sendable, Equatable, Codable {
        public var repo: String
        public var taskKind: String
        public var sourceSurface: String
        public var expectedArtifacts: [String]
        public var objectivePreview: String
    }

    public enum WorkerEventPayload: Sendable, Equatable {
        case trustPrompt(cwd: String, resolution: WorkerTrustResolution)
        case promptDelivery(
            promptPreview: String,
            observedTarget: WorkerPromptTarget,
            observedCwd: String?,
            observedPromptPreview: String?,
            taskReceipt: WorkerTaskReceipt?,
            recoveryArmed: Bool
        )
        case startupNoEvidence(
            evidence: StartupEvidenceBundle,
            classification: StartupFailureClassification
        )
    }

    public struct WorkerEvent: Sendable, Equatable {
        public var seq: UInt64
        public var kind: WorkerEventKind
        public var status: WorkerStatus
        public var detail: String?
        public var payload: WorkerEventPayload?
        public var timestamp: UInt64
    }

    public struct WorkerFailure: Sendable, Equatable, Codable {
        public let kind: WorkerFailureKind
        public let message: String
        public let createdAt: UInt64
    }

    public struct Worker: Sendable, Equatable {
        public let workerId: String
        public let cwd: String
        public var status: WorkerStatus
        public var trustAutoResolve: Bool
        public var trustGateCleared: Bool
        public var autoRecoverPromptMisdelivery: Bool
        public var promptDeliveryAttempts: UInt32
        public var promptInFlight: Bool
        public var lastPrompt: String?
        public var expectedReceipt: WorkerTaskReceipt?
        public var replayPrompt: String?
        public var lastError: WorkerFailure?
        public let createdAt: UInt64
        public var updatedAt: UInt64
        public var events: [WorkerEvent]
    }

    public struct WorkerReadySnapshot: Sendable, Equatable {
        public var workerId: String
        public var status: WorkerStatus
        public var ready: Bool
        public var blocked: Bool
        public var replayPromptReady: Bool
        public var lastError: WorkerFailure?
    }

    // MARK: - Registry

    public actor WorkerRegistry {
        private var workers: [String: Worker] = [:]
        private var counter: UInt64 = 0

        public init() {}

        public func create(
            cwd: String, trustedRoots: [String],
            autoRecoverPromptMisdelivery: Bool = false
        ) -> Worker {
            counter &+= 1
            let now = UInt64(Date().timeIntervalSince1970 * 1000)
            let id = TaskRegistry.makeId(prefix: "worker", counter: counter)
            let autoTrust = trustedRoots.contains(where: {
                ClawRuntime.pathMatchesTrustedRoot(cwd: cwd, trustedRoot: $0)
            })
            let status: WorkerStatus = autoTrust ? .readyForPrompt : .trustRequired
            let event = WorkerEvent(
                seq: 1, kind: .spawning, status: .spawning,
                detail: nil, payload: nil,
                timestamp: now
            )
            let worker = Worker(
                workerId: id, cwd: cwd, status: status,
                trustAutoResolve: autoTrust, trustGateCleared: autoTrust,
                autoRecoverPromptMisdelivery: autoRecoverPromptMisdelivery,
                promptDeliveryAttempts: 0, promptInFlight: false,
                lastPrompt: nil, expectedReceipt: nil, replayPrompt: nil,
                lastError: nil, createdAt: now, updatedAt: now, events: [event]
            )
            workers[id] = worker
            return worker
        }

        public func get(_ id: String) -> Worker? { workers[id] }
        public func list() -> [Worker] { Array(workers.values) }

        public func terminate(_ id: String) {
            workers.removeValue(forKey: id)
        }

        public func setStatus(_ id: String, _ status: WorkerStatus) {
            guard var w = workers[id] else { return }
            w.status = status
            w.updatedAt = UInt64(Date().timeIntervalSince1970 * 1000)
            workers[id] = w
        }

        public func resolveTrust(_ id: String) -> Bool {
            guard var w = workers[id], w.status == .trustRequired else { return false }
            w.trustGateCleared = true
            w.status = .readyForPrompt
            w.updatedAt = UInt64(Date().timeIntervalSince1970 * 1000)
            workers[id] = w
            return true
        }

        public func sendPrompt(_ id: String, prompt: String?, receipt: WorkerTaskReceipt?) -> Bool {
            guard var w = workers[id], w.status == .readyForPrompt else { return false }
            let effective = prompt ?? w.replayPrompt ?? ""
            w.lastPrompt = effective
            w.expectedReceipt = receipt
            w.promptInFlight = true
            w.promptDeliveryAttempts &+= 1
            w.status = .running
            w.updatedAt = UInt64(Date().timeIntervalSince1970 * 1000)
            workers[id] = w
            return true
        }

        public func observeCompletion(
            _ id: String, finishReason: String, tokensOutput: UInt32
        ) {
            guard var w = workers[id] else { return }
            let isFailure = (finishReason == "unknown" && tokensOutput == 0)
                || finishReason == "error"
            w.status = isFailure ? .failed : .finished
            if isFailure {
                w.lastError = WorkerFailure(
                    kind: .provider, message: "provider returned \(finishReason)",
                    createdAt: UInt64(Date().timeIntervalSince1970 * 1000)
                )
            }
            w.updatedAt = UInt64(Date().timeIntervalSince1970 * 1000)
            workers[id] = w
        }

        public func awaitReady(_ id: String) -> WorkerReadySnapshot? {
            guard let w = workers[id] else { return nil }
            return WorkerReadySnapshot(
                workerId: id, status: w.status,
                ready: w.status == .readyForPrompt,
                blocked: w.status == .trustRequired,
                replayPromptReady: w.replayPrompt != nil,
                lastError: w.lastError
            )
        }

        public func observeStartupTimeout(
            _ id: String, paneCommand: String?,
            transportHealthy: Bool, mcpHealthy: Bool, elapsedSeconds: UInt64
        ) {
            guard var w = workers[id] else { return }
            let classification = ClawRuntime.classifyStartupFailure(
                transportHealthy: transportHealthy,
                trustPromptDetected: w.status == .trustRequired,
                promptInFlight: w.promptInFlight,
                running: w.status == .running,
                elapsedSeconds: elapsedSeconds,
                mcpHealthy: mcpHealthy
            )
            let evidence = StartupEvidenceBundle(
                lastLifecycleState: String(describing: w.status),
                paneCommand: paneCommand,
                promptSentAt: nil,
                promptAcceptanceState: nil,
                trustPromptDetected: w.status == .trustRequired,
                transportHealthy: transportHealthy,
                mcpHealthy: mcpHealthy,
                elapsedSeconds: elapsedSeconds
            )
            let seq = UInt64(w.events.count + 1)
            let event = WorkerEvent(
                seq: seq, kind: .startupNoEvidence, status: w.status,
                detail: "startup timeout",
                payload: .startupNoEvidence(evidence: evidence, classification: classification),
                timestamp: UInt64(Date().timeIntervalSince1970 * 1000)
            )
            w.events.append(event)
            w.updatedAt = event.timestamp
            workers[id] = w
        }
    }

    public static func classifyStartupFailure(
        transportHealthy: Bool,
        trustPromptDetected: Bool,
        promptInFlight: Bool,
        running: Bool,
        elapsedSeconds: UInt64,
        mcpHealthy: Bool
    ) -> StartupFailureClassification {
        if !transportHealthy { return .transportDead }
        if trustPromptDetected { return .trustRequired }
        if promptInFlight && running { return .promptAcceptanceTimeout }
        if promptInFlight && !running && elapsedSeconds > 30 { return .promptMisdelivery }
        if !mcpHealthy && transportHealthy { return .workerCrashed }
        return .unknown
    }
}
