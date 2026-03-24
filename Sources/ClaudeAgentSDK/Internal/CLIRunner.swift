import Foundation

#if os(macOS)

/// Internal helper for running one-shot CLI commands.
enum CLIRunner {
    /// Run a command and return stdout as Data.
    static func run(
        executable: String,
        arguments: [String],
        cwd: String? = nil
    ) async throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        if let cwd {
            process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice

        try process.run()

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { _ in
                let data = stdout.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: data)
            }
        }
    }
}

#endif
