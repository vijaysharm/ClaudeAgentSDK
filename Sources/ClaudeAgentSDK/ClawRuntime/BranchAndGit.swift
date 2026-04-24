import Foundation

extension ClawRuntime {

    // MARK: - Green contract

    public enum GreenContractLevel: Int, Sendable, Codable, Equatable, Comparable {
        case targetedTests = 0
        case package
        case workspace
        case mergeReady

        public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

        public init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            switch try c.decode(String.self) {
            case "targeted_tests": self = .targetedTests
            case "package": self = .package
            case "workspace": self = .workspace
            case "merge_ready": self = .mergeReady
            default: throw DecodingError.dataCorruptedError(
                in: c, debugDescription: "unknown green level"
            )
            }
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.singleValueContainer()
            switch self {
            case .targetedTests: try c.encode("targeted_tests")
            case .package: try c.encode("package")
            case .workspace: try c.encode("workspace")
            case .mergeReady: try c.encode("merge_ready")
            }
        }
    }

    public struct GreenContract: Sendable, Equatable {
        public var requiredLevel: GreenContractLevel

        public init(requiredLevel: GreenContractLevel) {
            self.requiredLevel = requiredLevel
        }

        public func isSatisfied(by level: GreenContractLevel) -> Bool {
            level >= requiredLevel
        }

        public func evaluate(_ observed: GreenContractLevel?) -> GreenContractOutcome {
            if let o = observed, o >= requiredLevel {
                return .satisfied(required: requiredLevel, observed: o)
            }
            return .unsatisfied(required: requiredLevel, observed: observed)
        }
    }

    public enum GreenContractOutcome: Sendable, Equatable {
        case satisfied(required: GreenContractLevel, observed: GreenContractLevel)
        case unsatisfied(required: GreenContractLevel, observed: GreenContractLevel?)

        public var isSatisfied: Bool {
            if case .satisfied = self { return true }
            return false
        }
    }

    // MARK: - Branch lock

    public struct BranchLockIntent: Sendable, Equatable, Codable {
        public let laneId: String
        public let branch: String
        public let worktree: String?
        public let modules: [String]

        public init(laneId: String, branch: String, worktree: String? = nil, modules: [String]) {
            self.laneId = laneId
            self.branch = branch
            self.worktree = worktree
            self.modules = modules
        }

        private enum CodingKeys: String, CodingKey {
            case laneId = "laneId"
            case branch, worktree, modules
        }
    }

    public struct BranchLockCollision: Sendable, Equatable, Codable {
        public let branch: String
        public let module: String
        public let laneIds: [String]
    }

    public static func detectBranchLockCollisions(_ intents: [BranchLockIntent]) -> [BranchLockCollision] {
        var collisions: [BranchLockCollision] = []
        for i in 0..<intents.count {
            for j in (i + 1)..<intents.count {
                let left = intents[i], right = intents[j]
                guard left.branch == right.branch else { continue }
                var overlaps: Set<String> = []
                for lm in left.modules {
                    for rm in right.modules {
                        if lm == rm { overlaps.insert(lm) }
                        else if lm.hasPrefix(rm + "/") { overlaps.insert(rm) }
                        else if rm.hasPrefix(lm + "/") { overlaps.insert(lm) }
                    }
                }
                for module in overlaps {
                    collisions.append(BranchLockCollision(
                        branch: left.branch, module: module,
                        laneIds: [left.laneId, right.laneId]
                    ))
                }
            }
        }
        // sort and dedup by (branch, module, laneIds)
        let sorted = collisions.sorted {
            if $0.branch != $1.branch { return $0.branch < $1.branch }
            if $0.module != $1.module { return $0.module < $1.module }
            return $0.laneIds.joined(separator: "|") < $1.laneIds.joined(separator: "|")
        }
        var seen: Set<String> = []
        return sorted.filter {
            let key = "\($0.branch)|\($0.module)|\($0.laneIds.joined(separator: ","))"
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }
    }

    // MARK: - Git context

    public struct GitCommitEntry: Sendable, Equatable, Codable {
        public let hash: String
        public let subject: String
    }

    public struct GitContext: Sendable, Equatable, Codable {
        public let branch: String?
        public let recentCommits: [GitCommitEntry]
        public let stagedFiles: [String]

        public init(branch: String?, recentCommits: [GitCommitEntry], stagedFiles: [String]) {
            self.branch = branch
            self.recentCommits = recentCommits
            self.stagedFiles = stagedFiles
        }

        /// Collect a minimal git snapshot. Returns nil if `cwd` isn't in a repo
        /// or `git` isn't available.
        public static func detect(cwd: String) -> GitContext? {
            guard let inRepo = runGit(["rev-parse", "--is-inside-work-tree"], cwd: cwd),
                  inRepo.trimmingCharacters(in: .whitespacesAndNewlines) == "true" else {
                return nil
            }
            let branch = runGit(["rev-parse", "--abbrev-ref", "HEAD"], cwd: cwd)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            var commits: [GitCommitEntry] = []
            if let log = runGit(["--no-optional-locks", "log", "--oneline", "-n", "5", "--no-decorate"], cwd: cwd) {
                for line in log.split(separator: "\n", omittingEmptySubsequences: true).prefix(5) {
                    let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
                    guard parts.count == 2 else { continue }
                    commits.append(GitCommitEntry(hash: String(parts[0]), subject: String(parts[1])))
                }
            }
            var staged: [String] = []
            if let diff = runGit(["--no-optional-locks", "diff", "--cached", "--name-only"], cwd: cwd) {
                staged = diff.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            }
            return GitContext(branch: branch, recentCommits: commits, stagedFiles: staged)
        }

        public func render() -> String {
            var parts: [String] = []
            if let b = branch { parts.append("Git branch: \(b)") }
            if !recentCommits.isEmpty {
                var s = "Recent commits:"
                for c in recentCommits { s += "\n- \(c.hash) \(c.subject)" }
                parts.append(s)
            }
            if !stagedFiles.isEmpty {
                var s = "Staged files:"
                for f in stagedFiles { s += "\n- \(f)" }
                parts.append(s)
            }
            return parts.joined(separator: "\n\n")
        }
    }

    // MARK: - Stale base

    public enum BaseCommitState: Sendable, Equatable {
        case matches
        case diverged(expected: String, actual: String)
        case noExpectedBase
        case notAGitRepo
    }

    public enum BaseCommitSource: Sendable, Equatable {
        case flag(String)
        case file(String)
    }

    public static func readClawBaseFile(cwd: String) -> String? {
        let path = (cwd as NSString).appendingPathComponent(".claw-base")
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let s = String(data: data, encoding: .utf8) else { return nil }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public static func resolveExpectedBase(flag: String?, cwd: String) -> BaseCommitSource? {
        if let f = flag { return .flag(f) }
        if let file = readClawBaseFile(cwd: cwd) { return .file(file) }
        return nil
    }

    public static func checkBaseCommit(cwd: String, expected: BaseCommitSource?) -> BaseCommitState {
        guard let head = runGit(["rev-parse", "HEAD"], cwd: cwd)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return .notAGitRepo
        }
        guard let source = expected else { return .noExpectedBase }
        let expectedRef: String = {
            switch source {
            case .flag(let v), .file(let v): return v
            }
        }()
        if let resolved = runGit(["rev-parse", expectedRef], cwd: cwd)?
            .trimmingCharacters(in: .whitespacesAndNewlines) {
            return head == resolved ? .matches : .diverged(expected: resolved, actual: head)
        }
        return head.hasPrefix(expectedRef) || expectedRef.hasPrefix(head)
            ? .matches
            : .diverged(expected: expectedRef, actual: head)
    }

    public static func formatStaleBaseWarning(_ state: BaseCommitState) -> String? {
        switch state {
        case .matches, .noExpectedBase: return nil
        case .notAGitRepo: return "working directory is not a git repository"
        case .diverged(let expected, let actual):
            return "HEAD (\(actual)) diverged from expected base (\(expected))"
        }
    }

    // MARK: - Stale branch

    public enum BranchFreshness: Sendable, Equatable {
        case fresh
        case stale(commitsBehind: UInt32, missingFixes: [String])
        case diverged(ahead: UInt32, behind: UInt32, missingFixes: [String])
    }

    public enum StaleBranchPolicy: String, Sendable, Codable, Equatable {
        case autoRebase
        case autoMergeForward
        case warnOnly
        case block
    }

    public enum StaleBranchAction: Sendable, Equatable {
        case noop
        case warn(message: String)
        case block(message: String)
        case rebase
        case mergeForward
    }

    public static func checkBranchFreshness(
        branch: String, mainRef: String, cwd: String = "."
    ) -> BranchFreshness {
        let behindStr = runGit(["rev-list", "--count", "\(branch)..\(mainRef)"], cwd: cwd)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "0"
        let aheadStr = runGit(["rev-list", "--count", "\(mainRef)..\(branch)"], cwd: cwd)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "0"
        let behind = UInt32(behindStr) ?? 0
        let ahead = UInt32(aheadStr) ?? 0

        var missing: [String] = []
        if let log = runGit(["log", "--format=%s", "\(mainRef)..\(branch)"], cwd: cwd) {
            missing = log.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        }

        if behind == 0 { return .fresh }
        if ahead > 0 && behind > 0 {
            return .diverged(ahead: ahead, behind: behind, missingFixes: missing)
        }
        return .stale(commitsBehind: behind, missingFixes: missing)
    }

    public static func applyStaleBranchPolicy(
        _ freshness: BranchFreshness, policy: StaleBranchPolicy
    ) -> StaleBranchAction {
        if case .fresh = freshness { return .noop }
        switch policy {
        case .autoRebase: return .rebase
        case .autoMergeForward: return .mergeForward
        case .warnOnly: return .warn(message: "branch is stale against main")
        case .block: return .block(message: "branch is stale against main")
        }
    }

    // MARK: - git helper

    static func runGit(_ args: [String], cwd: String) -> String? {
        #if os(macOS) || os(Linux)
        let task = Process()
        task.launchPath = "/usr/bin/env"
        task.arguments = ["git"] + args
        task.currentDirectoryURL = URL(fileURLWithPath: cwd)
        let out = Pipe()
        task.standardOutput = out
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            if task.terminationStatus != 0 { return nil }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch { return nil }
        #else
        _ = args; _ = cwd
        return nil
        #endif
    }
}
