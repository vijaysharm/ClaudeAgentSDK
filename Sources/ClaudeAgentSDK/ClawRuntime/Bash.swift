import Foundation

extension ClawRuntime {

    public struct BashCommandInput: Sendable, Equatable, Codable {
        public var command: String
        public var timeout: UInt64?
        public var description: String?
        public var runInBackground: Bool?
        public var dangerouslyDisableSandbox: Bool?
        public var namespaceRestrictions: Bool?
        public var isolateNetwork: Bool?
        public var filesystemMode: FilesystemIsolationMode?
        public var allowedMounts: [String]?

        public init(
            command: String, timeout: UInt64? = nil, description: String? = nil,
            runInBackground: Bool? = nil, dangerouslyDisableSandbox: Bool? = nil,
            namespaceRestrictions: Bool? = nil, isolateNetwork: Bool? = nil,
            filesystemMode: FilesystemIsolationMode? = nil,
            allowedMounts: [String]? = nil
        ) {
            self.command = command
            self.timeout = timeout
            self.description = description
            self.runInBackground = runInBackground
            self.dangerouslyDisableSandbox = dangerouslyDisableSandbox
            self.namespaceRestrictions = namespaceRestrictions
            self.isolateNetwork = isolateNetwork
            self.filesystemMode = filesystemMode
            self.allowedMounts = allowedMounts
        }
    }

    public struct BashCommandOutput: Sendable, Equatable, Codable {
        public var stdout: String
        public var stderr: String
        public var rawOutputPath: String?
        public var interrupted: Bool
        public var isImage: Bool?
        public var backgroundTaskId: String?
        public var backgroundedByUser: Bool?
        public var assistantAutoBackgrounded: Bool?
        public var dangerouslyDisableSandbox: Bool?
        public var returnCodeInterpretation: String?
        public var noOutputExpected: Bool?

        public init(
            stdout: String = "", stderr: String = "",
            rawOutputPath: String? = nil, interrupted: Bool = false,
            isImage: Bool? = nil, backgroundTaskId: String? = nil,
            backgroundedByUser: Bool? = nil, assistantAutoBackgrounded: Bool? = nil,
            dangerouslyDisableSandbox: Bool? = nil,
            returnCodeInterpretation: String? = nil,
            noOutputExpected: Bool? = nil
        ) {
            self.stdout = stdout
            self.stderr = stderr
            self.rawOutputPath = rawOutputPath
            self.interrupted = interrupted
            self.isImage = isImage
            self.backgroundTaskId = backgroundTaskId
            self.backgroundedByUser = backgroundedByUser
            self.assistantAutoBackgrounded = assistantAutoBackgrounded
            self.dangerouslyDisableSandbox = dangerouslyDisableSandbox
            self.returnCodeInterpretation = returnCodeInterpretation
            self.noOutputExpected = noOutputExpected
        }
    }

    public static let maxBashOutputBytes = 16_384

    /// Execute a bash command with best-effort semantics. On non-POSIX
    /// platforms (iOS) this throws.
    public static func executeBash(
        _ input: BashCommandInput, cwd: String = FileManager.default.currentDirectoryPath
    ) async throws -> BashCommandOutput {
        #if os(macOS) || os(Linux)
        let command = input.command
        let timeout = input.timeout
        return try await Swift.Task.detached(priority: .userInitiated) {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/sh")
            task.arguments = ["-lc", command]
            task.currentDirectoryURL = URL(fileURLWithPath: cwd)
            let stdout = Pipe(), stderr = Pipe()
            task.standardOutput = stdout
            task.standardError = stderr
            try task.run()

            // Timeout watchdog: terminate if we exceed the deadline.
            let watchdog: Swift.Task<Bool, Never>? = timeout.map { ms in
                Swift.Task.detached {
                    try? await Swift.Task.sleep(nanoseconds: UInt64(ms) * 1_000_000)
                    if task.isRunning { task.terminate(); return true }
                    return false
                }
            }

            task.waitUntilExit()
            let interrupted = await (watchdog?.value ?? false)
            let outData = (try? stdout.fileHandleForReading.readToEnd()) ?? nil
            let errData = (try? stderr.fileHandleForReading.readToEnd()) ?? nil
            let outStr = outData.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let errStr = errData.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            return BashCommandOutput(
                stdout: ClawRuntime.truncateOutput(outStr),
                stderr: ClawRuntime.truncateOutput(errStr),
                interrupted: interrupted,
                returnCodeInterpretation: interrupted ? "timeout" : nil
            )
        }.value
        #else
        throw FileOpsError.io("bash execution not supported on this platform")
        #endif
    }

    static func truncateOutput(_ s: String) -> String {
        let data = Data(s.utf8)
        guard data.count > maxBashOutputBytes else { return s }
        let prefix = data.prefix(maxBashOutputBytes)
        var str = String(decoding: prefix, as: UTF8.self)
        str += "\n\n[output truncated — exceeded \(maxBashOutputBytes) bytes]"
        return str
    }
}
