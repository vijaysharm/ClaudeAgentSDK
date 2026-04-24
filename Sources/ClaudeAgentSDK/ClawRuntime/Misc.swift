import Foundation

extension ClawRuntime {

    // MARK: - SSE (generic, field-level)

    /// Incremental parser for generic Server-Sent Events (field-level, not
    /// Anthropic-specific). Use `ClawAPI/SseParser` for Anthropic payloads.
    public final class IncrementalSseParser: @unchecked Sendable {
        private let lock = NSLock()
        private var buffer: String = ""
        private var pendingEvent: String?
        private var pendingData: [String] = []
        private var pendingId: String?
        private var pendingRetry: UInt64?

        public struct SseEvent: Sendable, Equatable {
            public var event: String?
            public var data: String
            public var id: String?
            public var retry: UInt64?
        }

        public init() {}

        public func pushChunk(_ chunk: String) -> [SseEvent] {
            lock.lock(); defer { lock.unlock() }
            buffer.append(chunk)
            var events: [SseEvent] = []
            while let lf = buffer.firstIndex(of: "\n") {
                var line = String(buffer[..<lf])
                buffer.removeSubrange(...lf)
                if line.hasSuffix("\r") { line.removeLast() }
                if line.isEmpty {
                    if let ev = drainPending() { events.append(ev) }
                } else if line.hasPrefix(":") {
                    continue
                } else {
                    apply(line: line)
                }
            }
            return events
        }

        public func finish() -> [SseEvent] {
            lock.lock(); defer { lock.unlock() }
            if !buffer.isEmpty {
                let line = buffer.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
                buffer.removeAll()
                if !line.isEmpty, !line.hasPrefix(":") {
                    apply(line: line)
                }
            }
            if let ev = drainPending() { return [ev] }
            return []
        }

        private func apply(line: String) {
            guard let colon = line.firstIndex(of: ":") else {
                // treat whole line as field, empty value
                return
            }
            let field = String(line[..<colon])
            var valueStart = line.index(after: colon)
            if valueStart < line.endIndex, line[valueStart] == " " {
                valueStart = line.index(after: valueStart)
            }
            let value = String(line[valueStart...])
            switch field {
            case "event": pendingEvent = value
            case "data": pendingData.append(value)
            case "id": pendingId = value
            case "retry": pendingRetry = UInt64(value)
            default: break
            }
        }

        private func drainPending() -> SseEvent? {
            defer { pendingEvent = nil; pendingData = []; pendingId = nil; pendingRetry = nil }
            guard !pendingData.isEmpty || pendingEvent != nil || pendingId != nil || pendingRetry != nil else {
                return nil
            }
            return SseEvent(
                event: pendingEvent,
                data: pendingData.joined(separator: "\n"),
                id: pendingId,
                retry: pendingRetry
            )
        }
    }

    // MARK: - Remote bootstrap

    public static let defaultRemoteBaseURL = "https://api.anthropic.com"
    public static let defaultSessionTokenPath = "/run/ccr/session_token"
    public static let defaultSystemCaBundle = "/etc/ssl/certs/ca-certificates.crt"

    public static let upstreamProxyEnvKeys = [
        "HTTPS_PROXY", "https_proxy", "NO_PROXY", "no_proxy",
        "SSL_CERT_FILE", "NODE_EXTRA_CA_CERTS", "REQUESTS_CA_BUNDLE", "CURL_CA_BUNDLE",
    ]

    public static let noProxyHosts = [
        "localhost", "127.0.0.1", "::1", "0.0.0.0",
        "*.local", "*.internal", "*.corp",
        "registry-1.docker.io", "github.com", "gitlab.com", "bitbucket.org",
        "npm.community", "pypi.org", "files.pythonhosted.org",
        "proxy.golang.org", "raw.githubusercontent.com", "codeload.github.com",
        "objects.githubusercontent.com", "launchpad.net",
    ]

    public struct RemoteSessionContext: Sendable, Equatable, Codable {
        public var enabled: Bool
        public var sessionId: String?
        public var baseUrl: String

        public init(enabled: Bool, sessionId: String? = nil, baseUrl: String = ClawRuntime.defaultRemoteBaseURL) {
            self.enabled = enabled
            self.sessionId = sessionId
            self.baseUrl = baseUrl
        }

        public static func fromEnvMap(_ env: [String: String]) -> RemoteSessionContext {
            let enabled = envTruthy(env["CLAUDE_CODE_REMOTE"])
            return RemoteSessionContext(
                enabled: enabled,
                sessionId: (env["CLAUDE_CODE_REMOTE_SESSION_ID"].flatMap { $0.isEmpty ? nil : $0 }),
                baseUrl: (env["ANTHROPIC_BASE_URL"] ?? "").isEmpty
                    ? defaultRemoteBaseURL
                    : env["ANTHROPIC_BASE_URL"]!
            )
        }

        public static func fromEnv() -> RemoteSessionContext {
            fromEnvMap(ProcessInfo.processInfo.environment)
        }

        public func wsURL() -> String {
            upstreamProxyWsURL(baseUrl)
        }
    }

    public struct UpstreamProxyBootstrap: Sendable, Equatable {
        public var remote: RemoteSessionContext
        public var upstreamProxyEnabled: Bool
        public var tokenPath: String
        public var caBundlePath: String?
        public var systemCaPath: String
        public var token: String?

        public static func fromEnvMap(_ env: [String: String]) -> UpstreamProxyBootstrap {
            let remote = RemoteSessionContext.fromEnvMap(env)
            let tokenPath = env["CCR_SESSION_TOKEN_PATH"] ?? defaultSessionTokenPath
            let systemCa = env["CCR_SYSTEM_CA_BUNDLE"] ?? defaultSystemCaBundle
            let caBundle = (env["CCR_CA_BUNDLE_PATH"]).flatMap { $0.isEmpty ? nil : $0 }
            let token = readToken(path: tokenPath)
            return UpstreamProxyBootstrap(
                remote: remote,
                upstreamProxyEnabled: envTruthy(env["CCR_UPSTREAM_PROXY_ENABLED"]),
                tokenPath: tokenPath,
                caBundlePath: caBundle,
                systemCaPath: systemCa,
                token: token
            )
        }

        public static func fromEnv() -> UpstreamProxyBootstrap {
            fromEnvMap(ProcessInfo.processInfo.environment)
        }

        public func shouldEnable() -> Bool {
            remote.enabled && upstreamProxyEnabled
                && remote.sessionId != nil && token != nil
        }

        public func wsURL() -> String { remote.wsURL() }
    }

    public struct UpstreamProxyState: Sendable, Equatable {
        public var enabled: Bool
        public var proxyUrl: String?
        public var caBundlePath: String?
        public var noProxy: String

        public static func disabled() -> UpstreamProxyState {
            UpstreamProxyState(enabled: false, proxyUrl: nil, caBundlePath: nil, noProxy: noProxyList())
        }

        public func subprocessEnv() -> [String: String] {
            guard enabled, let proxy = proxyUrl else { return [:] }
            var env: [String: String] = [:]
            env["HTTPS_PROXY"] = proxy
            env["https_proxy"] = proxy
            env["NO_PROXY"] = noProxy
            env["no_proxy"] = noProxy
            if let ca = caBundlePath {
                env["SSL_CERT_FILE"] = ca
                env["NODE_EXTRA_CA_CERTS"] = ca
                env["REQUESTS_CA_BUNDLE"] = ca
                env["CURL_CA_BUNDLE"] = ca
            }
            return env
        }
    }

    public static func upstreamProxyWsURL(_ base: String) -> String {
        var url = base
        if url.hasPrefix("https://") {
            url.replaceSubrange(url.startIndex..<url.index(url.startIndex, offsetBy: "https".count), with: "wss")
        } else if url.hasPrefix("http://") {
            url.replaceSubrange(url.startIndex..<url.index(url.startIndex, offsetBy: "http".count), with: "ws")
        }
        if url.hasSuffix("/") { url.removeLast() }
        return url + "/v1/code/upstreamproxy/ws"
    }

    public static func readToken(path: String) -> String? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let s = String(data: data, encoding: .utf8) else { return nil }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public static func noProxyList() -> String { noProxyHosts.joined(separator: ",") }

    static func envTruthy(_ value: String?) -> Bool {
        guard let v = value?.lowercased() else { return false }
        return ["1", "true", "yes", "on"].contains(v)
    }

    // MARK: - LSP client registry (in-memory)

    public enum LspAction: String, Sendable, Codable, Equatable {
        case diagnostics, hover, definition, references, completion, symbols, format

        public static func fromString(_ s: String) -> LspAction? {
            switch s.lowercased() {
            case "diagnostics": return .diagnostics
            case "hover": return .hover
            case "definition", "goto_definition": return .definition
            case "references", "find_references": return .references
            case "completion", "completions": return .completion
            case "symbols", "document_symbols": return .symbols
            case "format", "formatting": return .format
            default: return nil
            }
        }
    }

    public struct LspDiagnostic: Sendable, Equatable, Codable {
        public let path: String
        public let line: UInt32
        public let character: UInt32
        public let severity: String
        public let message: String
        public let source: String?
    }

    public enum LspServerStatus: String, Sendable, Codable, Equatable {
        case connected, disconnected, starting, error
    }

    public struct LspServerState: Sendable, Equatable, Codable {
        public var language: String
        public var status: LspServerStatus
        public var rootPath: String
        public var capabilities: [String]
        public var diagnostics: [LspDiagnostic]
    }

    public actor LspRegistry {
        private var servers: [String: LspServerState] = [:]

        public init() {}

        public func register(key: String, state: LspServerState) { servers[key] = state }
        public func get(_ key: String) -> LspServerState? { servers[key] }
        public func list() -> [LspServerState] { Array(servers.values) }
        public func disconnect(_ key: String) { servers[key]?.status = .disconnected }
        public func addDiagnostics(_ key: String, _ diag: [LspDiagnostic]) {
            servers[key]?.diagnostics.append(contentsOf: diag)
        }
        public func getDiagnostics(path: String) -> [LspDiagnostic] {
            servers.values.flatMap { $0.diagnostics.filter { $0.path == path } }
        }
        public func clearDiagnostics(_ key: String) { servers[key]?.diagnostics.removeAll() }

        public static func languageForFile(_ path: String) -> String? {
            let ext = (path as NSString).pathExtension.lowercased()
            switch ext {
            case "rs": return "rust"
            case "swift": return "swift"
            case "ts", "tsx": return "typescript"
            case "js", "jsx": return "javascript"
            case "py": return "python"
            case "go": return "go"
            case "java": return "java"
            case "c", "h": return "c"
            case "cpp", "hpp", "cc": return "cpp"
            case "rb": return "ruby"
            case "lua": return "lua"
            default: return nil
            }
        }
    }
}
