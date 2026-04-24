import Foundation

extension ClawRuntime {

    // MARK: - MCP naming + fingerprinting

    public enum MCP {

        public static func normalizeName(_ name: String) -> String {
            var result = String(name.map { c -> Character in
                if c.isLetter || c.isNumber { return c }
                if c == "_" || c == "-" { return c }
                return "_"
            })
            if name.hasPrefix("claude.ai ") {
                // collapse underscores + trim
                var collapsed = ""
                var lastUnderscore = false
                for c in result {
                    if c == "_" {
                        if lastUnderscore { continue }
                        lastUnderscore = true
                    } else {
                        lastUnderscore = false
                    }
                    collapsed.append(c)
                }
                result = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
            }
            return result
        }

        public static func toolPrefix(serverName: String) -> String {
            "mcp__\(normalizeName(serverName))__"
        }

        public static func toolName(serverName: String, toolName: String) -> String {
            toolPrefix(serverName: serverName) + normalizeName(toolName)
        }

        /// Unwrap a `?mcp_url=...` wrapper from a Claude Code proxy URL.
        public static func unwrapCCRProxyURL(_ url: String) -> String {
            let markers = ["/v2/session_ingress/shttp/mcp/", "/v2/ccr-sessions/"]
            guard markers.contains(where: url.contains) else { return url }
            guard let qIdx = url.firstIndex(of: "?") else { return url }
            let query = url[url.index(after: qIdx)...]
            for pair in query.split(separator: "&") {
                let parts = pair.split(separator: "=", maxSplits: 1)
                guard parts.count == 2, parts[0] == "mcp_url" else { continue }
                return percentDecode(String(parts[1]))
            }
            return url
        }

        private static func percentDecode(_ s: String) -> String {
            s.replacingOccurrences(of: "+", with: " ")
                .removingPercentEncoding ?? s
        }

        /// 16-character hex signature of a scoped MCP config, ignoring scope.
        public static func scopedMcpConfigHash(signature: String) -> String {
            String(format: "%016x", ClawAPI.FNV1a64.hashString(signature))
        }
    }

    // MARK: - MCP lifecycle state machine

    public enum McpLifecyclePhase: String, Sendable, Codable, Equatable, CaseIterable {
        case configLoad = "config_load"
        case serverRegistration = "server_registration"
        case spawnConnect = "spawn_connect"
        case initializeHandshake = "initialize_handshake"
        case toolDiscovery = "tool_discovery"
        case resourceDiscovery = "resource_discovery"
        case ready
        case invocation
        case errorSurfacing = "error_surfacing"
        case shutdown
        case cleanup
    }

    public struct McpErrorSurface: Sendable, Equatable, Codable, Error {
        public var phase: McpLifecyclePhase
        public var serverName: String
        public var message: String
        public var context: [String: String]
        public var recoverable: Bool
        public var timestamp: UInt64
    }

    public enum McpPhaseResult: Sendable, Equatable {
        case success(phase: McpLifecyclePhase, duration: TimeInterval)
        case failure(phase: McpLifecyclePhase, error: McpErrorSurface)
        case timeout(phase: McpLifecyclePhase, waited: TimeInterval, error: McpErrorSurface)

        public var phase: McpLifecyclePhase {
            switch self {
            case .success(let p, _), .failure(let p, _), .timeout(let p, _, _): return p
            }
        }
    }

    public struct McpFailedServer: Sendable, Equatable, Codable {
        public let serverName: String
        public let phase: McpLifecyclePhase
        public let error: McpErrorSurface
    }

    public struct McpDegradedReport: Sendable, Equatable, Codable {
        public let workingServers: [String]
        public let failedServers: [McpFailedServer]
        public let availableTools: [String]
        public let missingTools: [String]

        public init(
            working: [String], failed: [McpFailedServer],
            available: [String], expected: [String]
        ) {
            self.workingServers = Array(Set(working)).sorted()
            self.failedServers = failed
            self.availableTools = Array(Set(available)).sorted()
            let expectedSet = Set(expected)
            let availSet = Set(available)
            self.missingTools = expectedSet.subtracting(availSet).sorted()
        }
    }

    public final class McpLifecycleValidator: @unchecked Sendable {
        private let lock = NSLock()
        public private(set) var state: McpLifecycleState

        public init() {
            self.state = McpLifecycleState()
        }

        public func runPhase(_ phase: McpLifecyclePhase, duration: TimeInterval = 0) -> Bool {
            lock.lock(); defer { lock.unlock() }
            guard McpLifecycleValidator.validateTransition(from: state.currentPhase, to: phase) else {
                return false
            }
            state.currentPhase = phase
            state.phaseResults.append(.success(phase: phase, duration: duration))
            state.phaseTimestamps[phase] = UInt64(Date().timeIntervalSince1970 * 1000)
            return true
        }

        public func recordFailure(_ error: McpErrorSurface) {
            lock.lock(); defer { lock.unlock() }
            state.phaseErrors[error.phase, default: []].append(error)
            state.phaseResults.append(.failure(phase: error.phase, error: error))
        }

        public func recordTimeout(
            phase: McpLifecyclePhase, waited: TimeInterval,
            server: String, context: [String: String] = [:]
        ) {
            let surface = McpErrorSurface(
                phase: phase, serverName: server,
                message: "timed out after \(waited)s",
                context: context, recoverable: true,
                timestamp: UInt64(Date().timeIntervalSince1970 * 1000)
            )
            lock.lock(); defer { lock.unlock() }
            state.phaseResults.append(.timeout(phase: phase, waited: waited, error: surface))
        }

        /// Transition matrix — verbatim port of the Rust implementation.
        public static func validateTransition(
            from a: McpLifecyclePhase?, to b: McpLifecyclePhase
        ) -> Bool {
            // allow initial transition only to configLoad
            guard let a else { return b == .configLoad }
            switch (a, b) {
            case (.configLoad, .serverRegistration),
                 (.serverRegistration, .spawnConnect),
                 (.spawnConnect, .initializeHandshake),
                 (.initializeHandshake, .toolDiscovery),
                 (.toolDiscovery, .resourceDiscovery),
                 (.toolDiscovery, .ready),
                 (.resourceDiscovery, .ready),
                 (.ready, .invocation),
                 (.invocation, .ready),
                 (.errorSurfacing, .ready),
                 (.errorSurfacing, .shutdown),
                 (.shutdown, .cleanup):
                return true
            default:
                // any (except Cleanup) → Shutdown
                if b == .shutdown && a != .cleanup { return true }
                // any (except Cleanup/Shutdown) → ErrorSurfacing
                if b == .errorSurfacing && a != .cleanup && a != .shutdown { return true }
                return false
            }
        }
    }

    public struct McpLifecycleState: Sendable {
        public var currentPhase: McpLifecyclePhase?
        public var phaseErrors: [McpLifecyclePhase: [McpErrorSurface]] = [:]
        public var phaseTimestamps: [McpLifecyclePhase: UInt64] = [:]
        public var phaseResults: [McpPhaseResult] = []
    }
}
