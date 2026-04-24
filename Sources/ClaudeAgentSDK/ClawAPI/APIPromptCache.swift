import Foundation

extension ClawAPI {

    // MARK: - Config + paths

    public struct PromptCacheConfig: Sendable, Equatable {
        public var sessionId: String
        public var completionTtl: TimeInterval
        public var promptTtl: TimeInterval
        public var cacheBreakMinDrop: UInt32

        public static let defaultCompletionTtl: TimeInterval = 30
        public static let defaultPromptTtl: TimeInterval = 300
        public static let defaultCacheBreakMinDrop: UInt32 = 2000

        public init(
            sessionId: String,
            completionTtl: TimeInterval = PromptCacheConfig.defaultCompletionTtl,
            promptTtl: TimeInterval = PromptCacheConfig.defaultPromptTtl,
            cacheBreakMinDrop: UInt32 = PromptCacheConfig.defaultCacheBreakMinDrop
        ) {
            self.sessionId = sessionId
            self.completionTtl = completionTtl
            self.promptTtl = promptTtl
            self.cacheBreakMinDrop = cacheBreakMinDrop
        }

        public static func `default`() -> PromptCacheConfig {
            PromptCacheConfig(sessionId: "default")
        }
    }

    public struct PromptCachePaths: Sendable, Equatable, Codable {
        public let root: String
        public let sessionDir: String
        public let completionDir: String
        public let sessionStatePath: String
        public let statsPath: String

        public static func forSession(_ sessionId: String) -> PromptCachePaths {
            let root = baseCacheRoot()
            let safe = sanitizePathSegment(sessionId, maxLength: maxSanitizedLength)
            let sessionDir = (root as NSString).appendingPathComponent(safe)
            let completionDir = (sessionDir as NSString).appendingPathComponent("completions")
            let sessionStatePath = (sessionDir as NSString).appendingPathComponent("session-state.json")
            let statsPath = (sessionDir as NSString).appendingPathComponent("stats.json")
            return PromptCachePaths(
                root: root,
                sessionDir: sessionDir,
                completionDir: completionDir,
                sessionStatePath: sessionStatePath,
                statsPath: statsPath
            )
        }

        public func completionEntryPath(requestHash: String) -> String {
            (completionDir as NSString).appendingPathComponent("\(requestHash).json")
        }
    }

    // MARK: - Stats + cache-break event

    public struct PromptCacheStats: Sendable, Equatable, Codable {
        public var trackedRequests: UInt64 = 0
        public var completionCacheHits: UInt64 = 0
        public var completionCacheMisses: UInt64 = 0
        public var completionCacheWrites: UInt64 = 0
        public var expectedInvalidations: UInt64 = 0
        public var unexpectedCacheBreaks: UInt64 = 0
        public var totalCacheCreationInputTokens: UInt64 = 0
        public var totalCacheReadInputTokens: UInt64 = 0
        public var lastCacheCreationInputTokens: UInt32?
        public var lastCacheReadInputTokens: UInt32?
        public var lastRequestHash: String?
        public var lastCompletionCacheKey: String?
        public var lastBreakReason: String?
        public var lastCacheSource: String?

        public init() {}
    }

    public struct CacheBreakEvent: Sendable, Equatable, Codable {
        public let unexpected: Bool
        public let reason: String
        public let previousCacheReadInputTokens: UInt32
        public let currentCacheReadInputTokens: UInt32
        public let tokenDrop: UInt32
    }

    public struct PromptCacheRecord: Sendable {
        public let cacheBreak: CacheBreakEvent?
        public let stats: PromptCacheStats
    }

    // MARK: - PromptCache actor

    /// Thread-safe actor wrapper around the on-disk completion cache.
    ///
    /// ```swift
    /// let cache = PromptCache(config: .default())
    /// if let cached = try await cache.lookupCompletion(request) { … }
    /// let record = try await cache.recordResponse(request, response: msg)
    /// ```
    public actor PromptCache {
        public nonisolated let paths: PromptCachePaths
        private var config: PromptCacheConfig
        private var stats: PromptCacheStats
        private var previous: TrackedPromptState?

        public init(config: PromptCacheConfig = .default()) {
            self.config = config
            self.paths = PromptCachePaths.forSession(config.sessionId)
            self.stats = Self.readJSON(
                PromptCachePaths.forSession(config.sessionId).statsPath,
                as: PromptCacheStats.self
            ) ?? PromptCacheStats()
            self.previous = Self.readJSON(
                PromptCachePaths.forSession(config.sessionId).sessionStatePath,
                as: TrackedPromptState.self
            )
        }

        public func currentStats() -> PromptCacheStats { stats }

        /// Lookup a cached completion for the given request. Returns nil on miss.
        public func lookupCompletion(_ request: MessageRequest) -> MessageResponse? {
            let hash = Self.requestHashHex(request)
            let entryPath = paths.completionEntryPath(requestHash: hash)
            guard let entry = Self.readJSON(entryPath, as: CompletionCacheEntry.self) else {
                stats.completionCacheMisses &+= 1
                stats.lastCompletionCacheKey = hash
                persist()
                return nil
            }
            if entry.fingerprintVersion != Self.currentFingerprintVersion {
                try? FileManager.default.removeItem(atPath: entryPath)
                stats.completionCacheMisses &+= 1
                stats.lastCompletionCacheKey = hash
                persist()
                return nil
            }
            let now = UInt64(Date().timeIntervalSince1970)
            if now >= entry.cachedAtUnixSecs &+ UInt64(config.completionTtl) {
                try? FileManager.default.removeItem(atPath: entryPath)
                stats.completionCacheMisses &+= 1
                stats.lastCompletionCacheKey = hash
                persist()
                return nil
            }

            stats.completionCacheHits &+= 1
            applyUsageToStats(entry.response.usage, hash: hash, source: "completion-cache")
            previous = TrackedPromptState.fromUsage(request, usage: entry.response.usage)
            persist()
            return entry.response
        }

        @discardableResult
        public func recordResponse(
            _ request: MessageRequest, response: MessageResponse
        ) -> PromptCacheRecord {
            let rec = updateFromUsage(request, usage: response.usage)
            if let json = try? Self.encoder().encode(
                CompletionCacheEntry(
                    cachedAtUnixSecs: UInt64(Date().timeIntervalSince1970),
                    fingerprintVersion: Self.currentFingerprintVersion,
                    response: response
                )
            ) {
                Self.ensureDirs(paths)
                let path = paths.completionEntryPath(requestHash: rec.requestHash)
                try? json.write(to: URL(fileURLWithPath: path))
                stats.completionCacheWrites &+= 1
                persist()
            }
            return PromptCacheRecord(cacheBreak: rec.cacheBreak, stats: stats)
        }

        @discardableResult
        public func recordUsage(
            _ request: MessageRequest, usage: Usage
        ) -> PromptCacheRecord {
            let rec = updateFromUsage(request, usage: usage)
            persist()
            return PromptCacheRecord(cacheBreak: rec.cacheBreak, stats: stats)
        }

        // MARK: - Private

        private struct UpdateResult {
            let cacheBreak: CacheBreakEvent?
            let requestHash: String
        }

        private func updateFromUsage(
            _ request: MessageRequest, usage: Usage
        ) -> UpdateResult {
            let hash = Self.requestHashHex(request)
            let current = TrackedPromptState.fromUsage(request, usage: usage)
            let cacheBreak = Self.detectCacheBreak(
                config: config, previous: previous, current: current
            )
            stats.trackedRequests &+= 1
            applyUsageToStats(usage, hash: hash, source: "api-response")
            if let br = cacheBreak {
                if br.unexpected {
                    stats.unexpectedCacheBreaks &+= 1
                } else {
                    stats.expectedInvalidations &+= 1
                }
                stats.lastBreakReason = br.reason
            }
            previous = current
            return UpdateResult(cacheBreak: cacheBreak, requestHash: hash)
        }

        private func applyUsageToStats(_ usage: Usage, hash: String, source: String) {
            stats.totalCacheCreationInputTokens &+= UInt64(usage.cacheCreationInputTokens)
            stats.totalCacheReadInputTokens &+= UInt64(usage.cacheReadInputTokens)
            stats.lastCacheCreationInputTokens = usage.cacheCreationInputTokens
            stats.lastCacheReadInputTokens = usage.cacheReadInputTokens
            stats.lastRequestHash = hash
            stats.lastCompletionCacheKey = hash
            stats.lastCacheSource = source
        }

        private func persist() {
            Self.ensureDirs(paths)
            let enc = Self.encoder()
            if let data = try? enc.encode(stats) {
                try? data.write(to: URL(fileURLWithPath: paths.statsPath))
            }
            if let prev = previous, let data = try? enc.encode(prev) {
                try? data.write(to: URL(fileURLWithPath: paths.sessionStatePath))
            }
        }

        // MARK: - Static helpers (thread-safe because they touch no actor state)

        static func encoder() -> JSONEncoder {
            let e = JSONEncoder()
            e.outputFormatting = [.prettyPrinted, .sortedKeys]
            return e
        }

        static func readJSON<T: Decodable>(_ path: String, as: T.Type) -> T? {
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
            return try? JSONDecoder().decode(T.self, from: data)
        }

        static func ensureDirs(_ paths: PromptCachePaths) {
            try? FileManager.default.createDirectory(
                atPath: paths.completionDir,
                withIntermediateDirectories: true
            )
        }

        static let currentFingerprintVersion: UInt32 = 1
        static let maxSanitizedLength = 80

        static func requestHashHex(_ request: MessageRequest) -> String {
            let bytes = (try? JSONEncoder().encode(request)) ?? Data()
            let h = FNV1a64.hash(Array(bytes))
            return "v1-" + String(format: "%016x", h)
        }

        static func detectCacheBreak(
            config: PromptCacheConfig,
            previous: TrackedPromptState?,
            current: TrackedPromptState
        ) -> CacheBreakEvent? {
            guard let prev = previous else { return nil }
            if prev.fingerprintVersion != current.fingerprintVersion {
                return CacheBreakEvent(
                    unexpected: false,
                    reason: "fingerprint version changed (v\(prev.fingerprintVersion) -> v\(current.fingerprintVersion))",
                    previousCacheReadInputTokens: prev.cacheReadInputTokens,
                    currentCacheReadInputTokens: current.cacheReadInputTokens,
                    tokenDrop: 0
                )
            }
            let drop = prev.cacheReadInputTokens >= current.cacheReadInputTokens
                ? prev.cacheReadInputTokens - current.cacheReadInputTokens
                : 0
            guard drop >= config.cacheBreakMinDrop else { return nil }

            var reasons: [String] = []
            if prev.modelHash != current.modelHash { reasons.append("model changed") }
            if prev.systemHash != current.systemHash { reasons.append("system changed") }
            if prev.toolsHash != current.toolsHash { reasons.append("tools changed") }
            if prev.messagesHash != current.messagesHash { reasons.append("messages changed") }

            if reasons.isEmpty {
                let elapsed = current.observedAtUnixSecs >= prev.observedAtUnixSecs
                    ? current.observedAtUnixSecs - prev.observedAtUnixSecs
                    : 0
                if elapsed > UInt64(config.promptTtl) {
                    return CacheBreakEvent(
                        unexpected: false,
                        reason: "possible prompt cache TTL expiry after \(elapsed)s",
                        previousCacheReadInputTokens: prev.cacheReadInputTokens,
                        currentCacheReadInputTokens: current.cacheReadInputTokens,
                        tokenDrop: drop
                    )
                }
                return CacheBreakEvent(
                    unexpected: true,
                    reason: "cache read tokens dropped while prompt fingerprint remained stable",
                    previousCacheReadInputTokens: prev.cacheReadInputTokens,
                    currentCacheReadInputTokens: current.cacheReadInputTokens,
                    tokenDrop: drop
                )
            }
            return CacheBreakEvent(
                unexpected: false,
                reason: reasons.joined(separator: ", "),
                previousCacheReadInputTokens: prev.cacheReadInputTokens,
                currentCacheReadInputTokens: current.cacheReadInputTokens,
                tokenDrop: drop
            )
        }
    }

    // MARK: - Supporting types

    struct TrackedPromptState: Codable, Equatable, Sendable {
        var observedAtUnixSecs: UInt64
        var fingerprintVersion: UInt32
        var modelHash: UInt64
        var systemHash: UInt64
        var toolsHash: UInt64
        var messagesHash: UInt64
        var cacheReadInputTokens: UInt32

        static func fromUsage(_ request: MessageRequest, usage: Usage) -> TrackedPromptState {
            TrackedPromptState(
                observedAtUnixSecs: UInt64(Date().timeIntervalSince1970),
                fingerprintVersion: PromptCache.currentFingerprintVersion,
                modelHash: hashEncodable(request.model),
                systemHash: hashEncodable(request.system),
                toolsHash: hashEncodable(request.tools),
                messagesHash: hashEncodable(request.messages),
                cacheReadInputTokens: usage.cacheReadInputTokens
            )
        }

        private static func hashEncodable<T: Encodable>(_ value: T) -> UInt64 {
            let bytes = (try? JSONEncoder().encode(value)) ?? Data()
            return FNV1a64.hash(Array(bytes))
        }
    }

    struct CompletionCacheEntry: Codable, Sendable {
        let cachedAtUnixSecs: UInt64
        let fingerprintVersion: UInt32
        let response: MessageResponse
    }

    // MARK: - FNV-1a 64-bit

    /// FNV-1a 64-bit stable hash. Identical to the Rust implementation used by
    /// the prompt cache and the MCP server-signature hash.
    public enum FNV1a64 {
        public static let offsetBasis: UInt64 = 0xcbf29ce484222325
        public static let prime: UInt64 = 0x100000001b3

        public static func hash(_ bytes: [UInt8]) -> UInt64 {
            var h = offsetBasis
            for b in bytes {
                h ^= UInt64(b)
                h = h &* prime
            }
            return h
        }

        public static func hashString(_ s: String) -> UInt64 {
            hash(Array(s.utf8))
        }

        public static func hashHex(_ s: String) -> String {
            String(format: "%016x", hashString(s))
        }
    }

    // MARK: - Utilities

    static let promptCacheDefaultRoot = ".claude/cache/prompt-cache"

    static func baseCacheRoot() -> String {
        let env = ProcessInfo.processInfo.environment
        if let home = env["CLAUDE_CONFIG_HOME"], !home.isEmpty {
            return (home as NSString).appendingPathComponent("cache/prompt-cache")
        }
        if let home = env["HOME"], !home.isEmpty {
            return (home as NSString).appendingPathComponent(promptCacheDefaultRoot)
        }
        return (NSTemporaryDirectory() as NSString).appendingPathComponent("claude-prompt-cache")
    }

    static func sanitizePathSegment(_ value: String, maxLength: Int) -> String {
        let sanitized = String(value.unicodeScalars.map { scalar -> Character in
            let c = Character(scalar)
            if c.isASCII, c.isLetter || c.isNumber { return c }
            return "-"
        })
        if sanitized.count <= maxLength { return sanitized }
        let hash = String(format: "%016x", FNV1a64.hashString(value))
        // reserve dash + hash
        let keep = max(0, maxLength - hash.count - 1)
        let prefix = String(sanitized.prefix(keep))
        return "\(prefix)-\(hash)"
    }
}

private extension URLSessionConfiguration {
    // placeholder so the file compiles standalone if needed
}
