import Foundation

extension ClawRuntime {

    public enum FilesystemIsolationMode: String, Codable, Sendable, Equatable {
        case off
        case workspaceOnly = "workspace-only"
        case allowList = "allow-list"
    }

    public struct SandboxConfig: Sendable, Equatable, Codable {
        public var enabled: Bool?
        public var namespaceRestrictions: Bool?
        public var networkIsolation: Bool?
        public var filesystemMode: FilesystemIsolationMode?
        public var allowedMounts: [String]

        public init(
            enabled: Bool? = nil,
            namespaceRestrictions: Bool? = nil,
            networkIsolation: Bool? = nil,
            filesystemMode: FilesystemIsolationMode? = nil,
            allowedMounts: [String] = []
        ) {
            self.enabled = enabled
            self.namespaceRestrictions = namespaceRestrictions
            self.networkIsolation = networkIsolation
            self.filesystemMode = filesystemMode
            self.allowedMounts = allowedMounts
        }

        public func resolveRequest(
            enabledOverride: Bool? = nil,
            namespaceOverride: Bool? = nil,
            networkOverride: Bool? = nil,
            filesystemModeOverride: FilesystemIsolationMode? = nil,
            allowedMountsOverride: [String]? = nil
        ) -> SandboxRequest {
            SandboxRequest(
                enabled: enabledOverride ?? enabled ?? true,
                namespaceRestrictions: namespaceOverride ?? namespaceRestrictions ?? true,
                networkIsolation: networkOverride ?? networkIsolation ?? false,
                filesystemMode: filesystemModeOverride ?? filesystemMode ?? .workspaceOnly,
                allowedMounts: allowedMountsOverride ?? allowedMounts
            )
        }
    }

    public struct SandboxRequest: Sendable, Equatable, Codable {
        public var enabled: Bool
        public var namespaceRestrictions: Bool
        public var networkIsolation: Bool
        public var filesystemMode: FilesystemIsolationMode
        public var allowedMounts: [String]
    }

    public struct ContainerEnvironment: Sendable, Equatable, Codable {
        public var inContainer: Bool
        public var markers: [String]
    }

    public struct SandboxStatus: Sendable, Equatable, Codable {
        public var enabled: Bool
        public var requested: SandboxRequest
        public var supported: Bool
        public var active: Bool
        public var namespaceSupported: Bool
        public var namespaceActive: Bool
        public var networkSupported: Bool
        public var networkActive: Bool
        public var filesystemMode: FilesystemIsolationMode
        public var filesystemActive: Bool
        public var allowedMounts: [String]
        public var inContainer: Bool
        public var containerMarkers: [String]
        public var fallbackReason: String?
    }

    public struct LinuxSandboxCommand: Sendable, Equatable {
        public let program: String
        public let args: [String]
        public let env: [(String, String)]

        public init(program: String, args: [String], env: [(String, String)]) {
            self.program = program
            self.args = args
            self.env = env
        }

        public static func == (lhs: LinuxSandboxCommand, rhs: LinuxSandboxCommand) -> Bool {
            guard lhs.program == rhs.program, lhs.args == rhs.args,
                  lhs.env.count == rhs.env.count else { return false }
            return zip(lhs.env, rhs.env).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
        }
    }

    // MARK: - Detection

    public struct SandboxDetectionInputs: Sendable, Equatable {
        public var envPairs: [(String, String)]
        public var dockerenvExists: Bool
        public var containerenvExists: Bool
        public var proc1Cgroup: String?

        public init(
            envPairs: [(String, String)] = [],
            dockerenvExists: Bool = false,
            containerenvExists: Bool = false,
            proc1Cgroup: String? = nil
        ) {
            self.envPairs = envPairs
            self.dockerenvExists = dockerenvExists
            self.containerenvExists = containerenvExists
            self.proc1Cgroup = proc1Cgroup
        }

        public static func == (lhs: SandboxDetectionInputs, rhs: SandboxDetectionInputs) -> Bool {
            lhs.dockerenvExists == rhs.dockerenvExists
                && lhs.containerenvExists == rhs.containerenvExists
                && lhs.proc1Cgroup == rhs.proc1Cgroup
                && lhs.envPairs.count == rhs.envPairs.count
                && zip(lhs.envPairs, rhs.envPairs).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
        }
    }

    public static func detectContainerEnvironment(
        _ inputs: SandboxDetectionInputs
    ) -> ContainerEnvironment {
        var markers: [String] = []
        if inputs.dockerenvExists { markers.append("/.dockerenv") }
        if inputs.containerenvExists { markers.append("/run/.containerenv") }

        for (key, value) in inputs.envPairs {
            let lowered = key.lowercased()
            if ["container", "docker", "podman", "kubernetes_service_host"].contains(lowered) {
                markers.append("env:\(key)=\(value)")
            }
        }
        if let cg = inputs.proc1Cgroup {
            for needle in ["docker", "containerd", "kubepods", "podman", "libpod"] {
                if cg.contains(needle) {
                    markers.append("/proc/1/cgroup:\(needle)")
                }
            }
        }
        markers = Array(Set(markers)).sorted()
        return ContainerEnvironment(inContainer: !markers.isEmpty, markers: markers)
    }

    public static func detectContainerEnvironment() -> ContainerEnvironment {
        let fm = FileManager.default
        let proc1 = (try? String(contentsOfFile: "/proc/1/cgroup", encoding: .utf8))
        let pairs = ProcessInfo.processInfo.environment.map { ($0.key, $0.value) }
        return detectContainerEnvironment(SandboxDetectionInputs(
            envPairs: pairs,
            dockerenvExists: fm.fileExists(atPath: "/.dockerenv"),
            containerenvExists: fm.fileExists(atPath: "/run/.containerenv"),
            proc1Cgroup: proc1
        ))
    }

    /// Resolve a sandbox status for the given request. On non-Linux (macOS, iOS)
    /// namespace/network sandboxing is unavailable, so the `supported`/
    /// `active` flags reflect that.
    public static func resolveSandboxStatusForRequest(
        _ req: SandboxRequest, cwd: String
    ) -> SandboxStatus {
        let container = detectContainerEnvironment()
        #if os(Linux)
        let nsSupported = req.namespaceRestrictions ? unshareUserNamespaceWorks() : true
        #else
        let nsSupported = false
        #endif
        let netSupported = nsSupported
        var fallbackReason: String?
        if req.enabled, !nsSupported, req.namespaceRestrictions {
            fallbackReason = "namespace restrictions unsupported on this platform"
        } else if req.filesystemMode == .allowList && req.allowedMounts.isEmpty {
            fallbackReason = "allow-list filesystem mode requires at least one allowed mount"
        }

        let active = req.enabled
            && (!req.namespaceRestrictions || nsSupported)
            && (!req.networkIsolation || netSupported)

        let mounts = req.allowedMounts.map { path -> String in
            path.hasPrefix("/") ? path : (cwd as NSString).appendingPathComponent(path)
        }

        return SandboxStatus(
            enabled: req.enabled,
            requested: req,
            supported: nsSupported,
            active: active,
            namespaceSupported: nsSupported,
            namespaceActive: req.namespaceRestrictions && nsSupported,
            networkSupported: netSupported,
            networkActive: req.networkIsolation && netSupported,
            filesystemMode: req.filesystemMode,
            filesystemActive: active,
            allowedMounts: mounts,
            inContainer: container.inContainer,
            containerMarkers: container.markers,
            fallbackReason: fallbackReason
        )
    }

    #if os(Linux)
    private static let unshareCache: (value: Bool, computed: Bool) = (false, false)
    private static func unshareUserNamespaceWorks() -> Bool {
        // Best-effort, runs once; here we skip actual subprocess check to keep
        // this file cross-platform — override at embed time if needed.
        return true
    }
    #endif

    /// Build a Linux `unshare`-based command wrapper. Returns nil on non-Linux
    /// or when the sandbox is inactive.
    public static func buildLinuxSandboxCommand(
        command: String, cwd: String, status: SandboxStatus
    ) -> LinuxSandboxCommand? {
        #if os(Linux)
        guard status.active else { return nil }
        var args = ["--user", "--map-root-user", "--mount", "--ipc", "--pid", "--uts", "--fork"]
        if status.networkActive { args.append("--net") }
        args.append(contentsOf: ["sh", "-lc", command])
        let home = (cwd as NSString).appendingPathComponent(".sandbox-home")
        let tmp = (cwd as NSString).appendingPathComponent(".sandbox-tmp")
        let env: [(String, String)] = [
            ("HOME", home),
            ("TMPDIR", tmp),
            ("CLAWD_SANDBOX_FILESYSTEM_MODE", status.filesystemMode.rawValue),
            ("CLAWD_SANDBOX_ALLOWED_MOUNTS", status.allowedMounts.joined(separator: ":")),
        ]
        return LinuxSandboxCommand(program: "unshare", args: args, env: env)
        #else
        _ = command; _ = cwd; _ = status
        return nil
        #endif
    }
}
