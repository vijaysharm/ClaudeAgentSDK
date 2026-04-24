import Foundation

extension ClawRuntime {

    public enum TrustPolicy: String, Sendable, Codable, Equatable {
        case autoTrust
        case requireApproval
        case deny
    }

    public enum TrustEvent: Sendable, Equatable {
        case trustRequired(cwd: String)
        case trustResolved(cwd: String, policy: TrustPolicy)
        case trustDenied(cwd: String, reason: String)
    }

    public struct TrustConfig: Sendable, Equatable, Codable {
        public var allowlisted: [String]
        public var denied: [String]

        public init(allowlisted: [String] = [], denied: [String] = []) {
            self.allowlisted = allowlisted
            self.denied = denied
        }
    }

    public enum TrustDecision: Sendable, Equatable {
        case notRequired
        case required(policy: TrustPolicy, events: [TrustEvent])

        public var policy: TrustPolicy? {
            if case .required(let p, _) = self { return p }
            return nil
        }

        public var events: [TrustEvent] {
            if case .required(_, let e) = self { return e }
            return []
        }
    }

    public static let trustPromptCues = [
        "do you trust the files in this folder",
        "trust the files in this folder",
        "trust this folder",
        "allow and continue",
        "yes, proceed",
    ]

    public static func detectTrustPrompt(_ screenText: String) -> Bool {
        let lower = screenText.lowercased()
        return trustPromptCues.contains(where: lower.contains)
    }

    public static func pathMatchesTrustedRoot(cwd: String, trustedRoot: String) -> Bool {
        let fm = FileManager.default
        let aResolved = (try? URL(fileURLWithPath: cwd).resolvingSymlinksInPath().path) ?? cwd
        let bResolved = (try? URL(fileURLWithPath: trustedRoot).resolvingSymlinksInPath().path) ?? trustedRoot
        _ = fm
        if aResolved == bResolved { return true }
        let rootSlash = bResolved.hasSuffix("/") ? bResolved : bResolved + "/"
        return aResolved.hasPrefix(rootSlash)
    }

    public struct TrustResolver: Sendable, Equatable {
        public var config: TrustConfig

        public init(config: TrustConfig) { self.config = config }

        public func resolve(cwd: String, screenText: String) -> TrustDecision {
            guard detectTrustPrompt(screenText) else { return .notRequired }
            var events: [TrustEvent] = [.trustRequired(cwd: cwd)]

            for root in config.denied where pathMatchesTrustedRoot(cwd: cwd, trustedRoot: root) {
                let reason = "path matched denied trust root: \(root)"
                events.append(.trustDenied(cwd: cwd, reason: reason))
                return .required(policy: .deny, events: events)
            }
            for root in config.allowlisted where pathMatchesTrustedRoot(cwd: cwd, trustedRoot: root) {
                events.append(.trustResolved(cwd: cwd, policy: .autoTrust))
                return .required(policy: .autoTrust, events: events)
            }
            return .required(policy: .requireApproval, events: events)
        }

        public func trusts(cwd: String) -> Bool {
            if config.denied.contains(where: { pathMatchesTrustedRoot(cwd: cwd, trustedRoot: $0) }) {
                return false
            }
            return config.allowlisted.contains(where: { pathMatchesTrustedRoot(cwd: cwd, trustedRoot: $0) })
        }
    }
}
