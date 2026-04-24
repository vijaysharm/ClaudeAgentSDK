import Foundation

/// Telemetry types and sinks ported from the Rust `telemetry` crate.
///
/// ``ClawTelemetry`` is the namespace for ``ClientIdentity``, request
/// profiles, analytics events, session tracers, and sinks that ship events
/// to JSONL files or in-memory buffers.
public enum ClawTelemetry {

    public static let defaultAnthropicVersion = "2023-06-01"
    public static let defaultAppName = "claude-code"
    public static let defaultRuntime = "swift"
    public static let defaultAgenticBeta = "claude-code-20250219"
    public static let defaultPromptCachingScopeBeta = "prompt-caching-scope-2026-01-05"

    // MARK: - Client identity

    public struct ClientIdentity: Codable, Sendable, Equatable {
        public var appName: String
        public var appVersion: String
        public var runtime: String

        public init(appName: String, appVersion: String, runtime: String = defaultRuntime) {
            self.appName = appName
            self.appVersion = appVersion
            self.runtime = runtime
        }

        public func withRuntime(_ runtime: String) -> ClientIdentity {
            var copy = self
            copy.runtime = runtime
            return copy
        }

        public func userAgent() -> String { "\(appName)/\(appVersion)" }

        public static let `default` = ClientIdentity(
            appName: defaultAppName,
            appVersion: "1.0.0",
            runtime: defaultRuntime
        )

        private enum CodingKeys: String, CodingKey {
            case appName = "app_name"
            case appVersion = "app_version"
            case runtime
        }
    }

    // MARK: - Request profile

    public struct AnthropicRequestProfile: Sendable, Equatable {
        public var anthropicVersion: String
        public var clientIdentity: ClientIdentity
        public var betas: [String]
        public var extraBody: [String: AnyCodable]

        public init(
            anthropicVersion: String = defaultAnthropicVersion,
            clientIdentity: ClientIdentity = .default,
            betas: [String] = [defaultAgenticBeta, defaultPromptCachingScopeBeta],
            extraBody: [String: AnyCodable] = [:]
        ) {
            self.anthropicVersion = anthropicVersion
            self.clientIdentity = clientIdentity
            self.betas = betas
            self.extraBody = extraBody
        }

        public func withBeta(_ beta: String) -> AnthropicRequestProfile {
            var copy = self
            if !copy.betas.contains(beta) { copy.betas.append(beta) }
            return copy
        }

        public func withExtraBody(_ key: String, _ value: AnyCodable) -> AnthropicRequestProfile {
            var copy = self
            copy.extraBody[key] = value
            return copy
        }

        /// Header pairs: `anthropic-version`, `user-agent`, and optional
        /// `anthropic-beta` (comma-joined when non-empty).
        public func headerPairs() -> [(String, String)] {
            var pairs: [(String, String)] = [
                ("anthropic-version", anthropicVersion),
                ("user-agent", clientIdentity.userAgent()),
            ]
            if !betas.isEmpty {
                pairs.append(("anthropic-beta", betas.joined(separator: ",")))
            }
            return pairs
        }

        /// Serialize a request and merge `extra_body` + `betas` into the JSON.
        public func renderJSONBody<T: Encodable>(_ value: T) throws -> [String: AnyCodable] {
            let data = try JSONEncoder().encode(value)
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw EncodingError.invalidValue(value, .init(
                    codingPath: [],
                    debugDescription: "request body did not serialize to an object"
                ))
            }
            var body: [String: AnyCodable] = [:]
            for (k, v) in obj { body[k] = AnyCodable.convert(v) }
            for (k, v) in extraBody { body[k] = v }
            body["betas"] = .array(betas.map { .string($0) })
            return body
        }
    }

    // MARK: - Analytics + events

    public struct AnalyticsEvent: Codable, Sendable, Equatable {
        public var namespace: String
        public var action: String
        public var properties: [String: AnyCodable]

        public init(namespace: String, action: String, properties: [String: AnyCodable] = [:]) {
            self.namespace = namespace
            self.action = action
            self.properties = properties
        }

        public func withProperty(_ key: String, _ value: AnyCodable) -> AnalyticsEvent {
            var copy = self
            copy.properties[key] = value
            return copy
        }
    }

    public struct SessionTraceRecord: Codable, Sendable, Equatable {
        public var sessionId: String
        public var sequence: UInt64
        public var name: String
        public var timestampMs: UInt64
        public var attributes: [String: AnyCodable]

        private enum CodingKeys: String, CodingKey {
            case sessionId = "session_id"
            case sequence, name
            case timestampMs = "timestamp_ms"
            case attributes
        }
    }

    public enum TelemetryEvent: Sendable, Equatable {
        case httpRequestStarted(sessionId: String, attempt: UInt32, method: String, path: String, attributes: [String: AnyCodable])
        case httpRequestSucceeded(sessionId: String, attempt: UInt32, method: String, path: String, status: UInt16, requestId: String?, attributes: [String: AnyCodable])
        case httpRequestFailed(sessionId: String, attempt: UInt32, method: String, path: String, error: String, retryable: Bool, attributes: [String: AnyCodable])
        case analytics(AnalyticsEvent)
        case sessionTrace(SessionTraceRecord)
    }

    // MARK: - Sinks

    public protocol TelemetrySink: Sendable {
        func record(_ event: TelemetryEvent)
    }

    /// In-memory sink that captures every recorded event.
    public final class MemoryTelemetrySink: TelemetrySink, @unchecked Sendable {
        private let lock = NSLock()
        private var _events: [TelemetryEvent] = []

        public init() {}

        public func record(_ event: TelemetryEvent) {
            lock.lock(); defer { lock.unlock() }
            _events.append(event)
        }

        public func events() -> [TelemetryEvent] {
            lock.lock(); defer { lock.unlock() }
            return _events
        }
    }

    /// Append-only JSONL sink.
    public final class JsonlTelemetrySink: TelemetrySink, @unchecked Sendable {
        public let path: String
        private let lock = NSLock()
        private let fileHandle: FileHandle

        public init(path: String) throws {
            self.path = path
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if !FileManager.default.fileExists(atPath: path) {
                FileManager.default.createFile(atPath: path, contents: nil)
            }
            self.fileHandle = try FileHandle(forWritingTo: url)
            self.fileHandle.seekToEndOfFile()
        }

        public func record(_ event: TelemetryEvent) {
            lock.lock(); defer { lock.unlock() }
            do {
                let data = try JSONEncoder.telemetryEncoder().encode(event)
                fileHandle.write(data)
                fileHandle.write(Data("\n".utf8))
            } catch {
                // Swallow per Rust parity.
            }
        }
    }

    // MARK: - SessionTracer

    public final class SessionTracer: @unchecked Sendable {
        public let sessionId: String
        private let lock = NSLock()
        private var sequence: UInt64 = 0
        public let sink: any TelemetrySink

        public init(sessionId: String, sink: any TelemetrySink) {
            self.sessionId = sessionId
            self.sink = sink
        }

        public func record(_ name: String, attributes: [String: AnyCodable] = [:]) {
            let seq: UInt64 = {
                lock.lock(); defer { lock.unlock() }
                sequence &+= 1
                return sequence
            }()
            let record = SessionTraceRecord(
                sessionId: sessionId,
                sequence: seq,
                name: name,
                timestampMs: ClawTelemetry.currentTimestampMs(),
                attributes: attributes
            )
            sink.record(.sessionTrace(record))
        }

        public func recordHTTPRequestStarted(
            attempt: UInt32, method: String, path: String,
            attributes: [String: AnyCodable] = [:]
        ) {
            sink.record(.httpRequestStarted(
                sessionId: sessionId, attempt: attempt,
                method: method, path: path, attributes: attributes
            ))
            var attrs = attributes
            attrs["method"] = .string(method)
            attrs["path"] = .string(path)
            attrs["attempt"] = .int(Int(attempt))
            record("http.request.started", attributes: attrs)
        }

        public func recordHTTPRequestSucceeded(
            attempt: UInt32, method: String, path: String,
            status: UInt16, requestId: String?,
            attributes: [String: AnyCodable] = [:]
        ) {
            sink.record(.httpRequestSucceeded(
                sessionId: sessionId, attempt: attempt,
                method: method, path: path, status: status,
                requestId: requestId, attributes: attributes
            ))
            var attrs = attributes
            attrs["method"] = .string(method)
            attrs["path"] = .string(path)
            attrs["attempt"] = .int(Int(attempt))
            attrs["status"] = .int(Int(status))
            if let rid = requestId { attrs["request_id"] = .string(rid) }
            record("http.request.succeeded", attributes: attrs)
        }

        public func recordHTTPRequestFailed(
            attempt: UInt32, method: String, path: String,
            error: String, retryable: Bool,
            attributes: [String: AnyCodable] = [:]
        ) {
            sink.record(.httpRequestFailed(
                sessionId: sessionId, attempt: attempt,
                method: method, path: path, error: error,
                retryable: retryable, attributes: attributes
            ))
            var attrs = attributes
            attrs["method"] = .string(method)
            attrs["path"] = .string(path)
            attrs["attempt"] = .int(Int(attempt))
            attrs["error"] = .string(error)
            attrs["retryable"] = .bool(retryable)
            record("http.request.failed", attributes: attrs)
        }

        public func recordAnalytics(_ event: AnalyticsEvent) {
            sink.record(.analytics(event))
            var attrs = event.properties
            attrs["namespace"] = .string(event.namespace)
            attrs["action"] = .string(event.action)
            record("analytics", attributes: attrs)
        }
    }

    static func currentTimestampMs() -> UInt64 {
        UInt64(Date().timeIntervalSince1970 * 1000)
    }
}

// MARK: - TelemetryEvent encoding

extension ClawTelemetry.TelemetryEvent: Codable {
    private enum CodingKeys: String, CodingKey { case type }
    private enum Keys: String, CodingKey {
        case type
        case sessionId = "session_id"
        case attempt, method, path, status
        case requestId = "request_id"
        case attributes, error, retryable, namespace, action, properties
        case name
        case timestampMs = "timestamp_ms"
        case sequence
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "http_request_started":
            self = .httpRequestStarted(
                sessionId: try c.decode(String.self, forKey: .sessionId),
                attempt: try c.decode(UInt32.self, forKey: .attempt),
                method: try c.decode(String.self, forKey: .method),
                path: try c.decode(String.self, forKey: .path),
                attributes: try c.decodeIfPresent([String: AnyCodable].self, forKey: .attributes) ?? [:]
            )
        case "http_request_succeeded":
            self = .httpRequestSucceeded(
                sessionId: try c.decode(String.self, forKey: .sessionId),
                attempt: try c.decode(UInt32.self, forKey: .attempt),
                method: try c.decode(String.self, forKey: .method),
                path: try c.decode(String.self, forKey: .path),
                status: try c.decode(UInt16.self, forKey: .status),
                requestId: try c.decodeIfPresent(String.self, forKey: .requestId),
                attributes: try c.decodeIfPresent([String: AnyCodable].self, forKey: .attributes) ?? [:]
            )
        case "http_request_failed":
            self = .httpRequestFailed(
                sessionId: try c.decode(String.self, forKey: .sessionId),
                attempt: try c.decode(UInt32.self, forKey: .attempt),
                method: try c.decode(String.self, forKey: .method),
                path: try c.decode(String.self, forKey: .path),
                error: try c.decode(String.self, forKey: .error),
                retryable: try c.decode(Bool.self, forKey: .retryable),
                attributes: try c.decodeIfPresent([String: AnyCodable].self, forKey: .attributes) ?? [:]
            )
        case "analytics":
            self = .analytics(try ClawTelemetry.AnalyticsEvent(from: decoder))
        case "session_trace":
            self = .sessionTrace(try ClawTelemetry.SessionTraceRecord(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: c,
                debugDescription: "Unknown telemetry event type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        switch self {
        case .httpRequestStarted(let sid, let attempt, let method, let path, let attrs):
            try c.encode("http_request_started", forKey: .type)
            try c.encode(sid, forKey: .sessionId)
            try c.encode(attempt, forKey: .attempt)
            try c.encode(method, forKey: .method)
            try c.encode(path, forKey: .path)
            try c.encode(attrs, forKey: .attributes)
        case .httpRequestSucceeded(let sid, let attempt, let method, let path, let status, let rid, let attrs):
            try c.encode("http_request_succeeded", forKey: .type)
            try c.encode(sid, forKey: .sessionId)
            try c.encode(attempt, forKey: .attempt)
            try c.encode(method, forKey: .method)
            try c.encode(path, forKey: .path)
            try c.encode(status, forKey: .status)
            try c.encodeIfPresent(rid, forKey: .requestId)
            try c.encode(attrs, forKey: .attributes)
        case .httpRequestFailed(let sid, let attempt, let method, let path, let err, let retryable, let attrs):
            try c.encode("http_request_failed", forKey: .type)
            try c.encode(sid, forKey: .sessionId)
            try c.encode(attempt, forKey: .attempt)
            try c.encode(method, forKey: .method)
            try c.encode(path, forKey: .path)
            try c.encode(err, forKey: .error)
            try c.encode(retryable, forKey: .retryable)
            try c.encode(attrs, forKey: .attributes)
        case .analytics(let event):
            try c.encode("analytics", forKey: .type)
            try event.encode(to: encoder)
        case .sessionTrace(let rec):
            try c.encode("session_trace", forKey: .type)
            try rec.encode(to: encoder)
        }
    }
}

// MARK: - Internal helpers

extension JSONEncoder {
    static func telemetryEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }
}

extension AnyCodable {
    static func convert(_ value: Any) -> AnyCodable {
        if value is NSNull { return .null }
        if let b = value as? Bool { return .bool(b) }
        if let i = value as? Int { return .int(i) }
        if let d = value as? Double { return .double(d) }
        if let s = value as? String { return .string(s) }
        if let a = value as? [Any] { return .array(a.map(convert)) }
        if let o = value as? [String: Any] {
            var dict: [String: AnyCodable] = [:]
            for (k, v) in o { dict[k] = convert(v) }
            return .object(dict)
        }
        return .null
    }
}
