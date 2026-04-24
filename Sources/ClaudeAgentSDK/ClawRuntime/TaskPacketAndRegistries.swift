import Foundation

extension ClawRuntime {

    // MARK: - Task packet

    public enum TaskScope: String, Sendable, Codable, Equatable {
        case workspace
        case module
        case singleFile = "single-file"
        case custom
    }

    public struct TaskPacket: Sendable, Equatable, Codable {
        public var objective: String
        public var scope: TaskScope
        public var scopePath: String?
        public var repo: String
        public var worktree: String?
        public var branchPolicy: String
        public var acceptanceTests: [String]
        public var commitPolicy: String
        public var reportingContract: String
        public var escalationPolicy: String

        public init(
            objective: String, scope: TaskScope, scopePath: String? = nil,
            repo: String, worktree: String? = nil, branchPolicy: String,
            acceptanceTests: [String] = [], commitPolicy: String,
            reportingContract: String, escalationPolicy: String
        ) {
            self.objective = objective
            self.scope = scope
            self.scopePath = scopePath
            self.repo = repo
            self.worktree = worktree
            self.branchPolicy = branchPolicy
            self.acceptanceTests = acceptanceTests
            self.commitPolicy = commitPolicy
            self.reportingContract = reportingContract
            self.escalationPolicy = escalationPolicy
        }
    }

    public struct TaskPacketValidationError: Error, Sendable, Equatable {
        public let errors: [String]
        public var localizedDescription: String { errors.joined(separator: "; ") }
    }

    public struct ValidatedPacket: Sendable, Equatable {
        public let packet: TaskPacket
        public var intoInner: TaskPacket { packet }
    }

    public static func validatePacket(
        _ p: TaskPacket
    ) -> Result<ValidatedPacket, TaskPacketValidationError> {
        var errors: [String] = []
        if p.objective.isEmpty { errors.append("objective required") }
        if p.repo.isEmpty { errors.append("repo required") }
        if p.branchPolicy.isEmpty { errors.append("branch policy required") }
        if p.commitPolicy.isEmpty { errors.append("commit policy required") }
        if p.reportingContract.isEmpty { errors.append("reporting contract required") }
        if p.escalationPolicy.isEmpty { errors.append("escalation policy required") }
        if [.module, .singleFile, .custom].contains(p.scope), p.scopePath?.isEmpty ?? true {
            errors.append("scope path required for scope=\(p.scope.rawValue)")
        }
        if p.acceptanceTests.contains(where: { $0.isEmpty }) {
            errors.append("acceptance tests must not be empty")
        }
        if errors.isEmpty { return .success(ValidatedPacket(packet: p)) }
        return .failure(TaskPacketValidationError(errors: errors))
    }

    // MARK: - Task registry

    public enum TaskStatus: String, Sendable, Codable, Equatable {
        case created, running, completed, failed, stopped
    }

    public struct TaskMessage: Sendable, Equatable, Codable {
        public let role: String
        public let content: String
        public let timestamp: UInt64
    }

    public struct Task: Sendable, Equatable, Codable {
        public let taskId: String
        public let prompt: String
        public let description: String?
        public var taskPacket: TaskPacket?
        public var status: TaskStatus
        public let createdAt: UInt64
        public var updatedAt: UInt64
        public var messages: [TaskMessage]
        public var output: String
        public var teamId: String?
    }

    public actor TaskRegistry {
        private var tasks: [String: Task] = [:]
        private var counter: UInt64 = 0

        public init() {}

        public func create(prompt: String, description: String? = nil) -> Task {
            counter &+= 1
            let id = Self.makeId(prefix: "task", counter: counter)
            let now = UInt64(Date().timeIntervalSince1970 * 1000)
            let task = Task(
                taskId: id, prompt: prompt, description: description,
                taskPacket: nil, status: .created, createdAt: now,
                updatedAt: now, messages: [], output: "", teamId: nil
            )
            tasks[id] = task
            return task
        }

        public func createFromPacket(
            _ packet: TaskPacket
        ) -> Result<Task, TaskPacketValidationError> {
            switch ClawRuntime.validatePacket(packet) {
            case .failure(let e): return .failure(e)
            case .success:
                counter &+= 1
                let id = Self.makeId(prefix: "task", counter: counter)
                let now = UInt64(Date().timeIntervalSince1970 * 1000)
                let task = Task(
                    taskId: id, prompt: packet.objective,
                    description: nil, taskPacket: packet, status: .created,
                    createdAt: now, updatedAt: now, messages: [],
                    output: "", teamId: nil
                )
                tasks[id] = task
                return .success(task)
            }
        }

        public func get(_ id: String) -> Task? { tasks[id] }
        public func list(status: TaskStatus? = nil) -> [Task] {
            let all = Array(tasks.values)
            return status.map { s in all.filter { $0.status == s } } ?? all
        }

        public func stop(_ id: String) -> Task? {
            guard var t = tasks[id],
                  ![.completed, .failed, .stopped].contains(t.status) else { return nil }
            t.status = .stopped
            t.updatedAt = UInt64(Date().timeIntervalSince1970 * 1000)
            tasks[id] = t
            return t
        }

        public func update(_ id: String, message: String) -> Task? {
            guard var t = tasks[id] else { return nil }
            t.messages.append(TaskMessage(
                role: "user", content: message,
                timestamp: UInt64(Date().timeIntervalSince1970 * 1000)
            ))
            t.updatedAt = UInt64(Date().timeIntervalSince1970 * 1000)
            tasks[id] = t
            return t
        }

        public func output(_ id: String) -> String? { tasks[id]?.output }

        public func appendOutput(_ id: String, _ chunk: String) {
            guard var t = tasks[id] else { return }
            t.output.append(chunk)
            t.updatedAt = UInt64(Date().timeIntervalSince1970 * 1000)
            tasks[id] = t
        }

        public func setStatus(_ id: String, _ status: TaskStatus) {
            guard var t = tasks[id] else { return }
            t.status = status
            t.updatedAt = UInt64(Date().timeIntervalSince1970 * 1000)
            tasks[id] = t
        }

        public func assignTeam(_ id: String, teamId: String) {
            guard var t = tasks[id] else { return }
            t.teamId = teamId
            tasks[id] = t
        }

        public func remove(_ id: String) { tasks.removeValue(forKey: id) }

        public var count: Int { tasks.count }
        public var isEmpty: Bool { tasks.isEmpty }

        static func makeId(prefix: String, counter: UInt64) -> String {
            let ts = UInt64(Date().timeIntervalSince1970)
            return String(format: "%@_%08x_%llu", prefix, UInt32(ts & 0xffff_ffff), counter)
        }
    }

    // MARK: - Team registry

    public enum TeamStatus: String, Sendable, Codable, Equatable {
        case created, running, completed, deleted
    }

    public struct Team: Sendable, Equatable, Codable {
        public let teamId: String
        public let name: String
        public var taskIds: [String]
        public var status: TeamStatus
        public let createdAt: UInt64
        public var updatedAt: UInt64
    }

    public actor TeamRegistry {
        private var teams: [String: Team] = [:]
        private var counter: UInt64 = 0

        public init() {}

        public func create(name: String, taskIds: [String] = []) -> Team {
            counter &+= 1
            let now = UInt64(Date().timeIntervalSince1970 * 1000)
            let team = Team(
                teamId: TaskRegistry.makeId(prefix: "team", counter: counter),
                name: name, taskIds: taskIds, status: .created,
                createdAt: now, updatedAt: now
            )
            teams[team.teamId] = team
            return team
        }

        public func get(_ id: String) -> Team? { teams[id] }
        public func list() -> [Team] { Array(teams.values) }
        public func delete(_ id: String) {
            guard var t = teams[id] else { return }
            t.status = .deleted
            t.updatedAt = UInt64(Date().timeIntervalSince1970 * 1000)
            teams[id] = t
        }
        public func remove(_ id: String) { teams.removeValue(forKey: id) }
        public var count: Int { teams.count }
    }

    // MARK: - Cron registry

    public struct CronEntry: Sendable, Equatable, Codable {
        public let cronId: String
        public let schedule: String
        public let prompt: String
        public let description: String?
        public var enabled: Bool
        public let createdAt: UInt64
        public var updatedAt: UInt64
        public var lastRunAt: UInt64?
        public var runCount: UInt64
    }

    public actor CronRegistry {
        private var crons: [String: CronEntry] = [:]
        private var counter: UInt64 = 0

        public init() {}

        public func create(
            schedule: String, prompt: String, description: String? = nil
        ) -> CronEntry {
            counter &+= 1
            let now = UInt64(Date().timeIntervalSince1970 * 1000)
            let entry = CronEntry(
                cronId: TaskRegistry.makeId(prefix: "cron", counter: counter),
                schedule: schedule, prompt: prompt, description: description,
                enabled: true, createdAt: now, updatedAt: now,
                lastRunAt: nil, runCount: 0
            )
            crons[entry.cronId] = entry
            return entry
        }

        public func get(_ id: String) -> CronEntry? { crons[id] }
        public func list(enabledOnly: Bool = false) -> [CronEntry] {
            enabledOnly ? crons.values.filter { $0.enabled } : Array(crons.values)
        }
        public func delete(_ id: String) { crons.removeValue(forKey: id) }
        public func disable(_ id: String) {
            guard var e = crons[id] else { return }
            e.enabled = false
            e.updatedAt = UInt64(Date().timeIntervalSince1970 * 1000)
            crons[id] = e
        }
        public func recordRun(_ id: String) {
            guard var e = crons[id] else { return }
            e.runCount &+= 1
            e.lastRunAt = UInt64(Date().timeIntervalSince1970 * 1000)
            e.updatedAt = e.lastRunAt!
            crons[id] = e
        }
        public var count: Int { crons.count }
    }
}
