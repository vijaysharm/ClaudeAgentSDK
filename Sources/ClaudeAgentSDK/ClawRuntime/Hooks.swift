import Foundation

extension ClawRuntime {

    // MARK: - Hook event + runner (distinct from plugin hooks)

    public enum HookEvent: String, Sendable, Codable, Equatable {
        case preToolUse = "PreToolUse"
        case postToolUse = "PostToolUse"
        case postToolUseFailure = "PostToolUseFailure"
    }

    public enum HookProgressEvent: Sendable, Equatable {
        case started(event: HookEvent, toolName: String, command: String)
        case completed(event: HookEvent, toolName: String, command: String)
        case cancelled(event: HookEvent, toolName: String, command: String)
    }

    public protocol HookProgressReporter: AnyObject {
        func onEvent(_ event: HookProgressEvent)
    }

    /// Cooperative abort signal used by the runtime hook runner.
    public final class HookAbortSignal: @unchecked Sendable {
        private let lock = NSLock()
        private var _aborted: Bool = false

        public init() {}

        public func abort() { lock.lock(); _aborted = true; lock.unlock() }
        public var isAborted: Bool {
            lock.lock(); defer { lock.unlock() }
            return _aborted
        }
    }

    public struct HookRunResult: Sendable, Equatable {
        public var denied: Bool
        public var failed: Bool
        public var cancelled: Bool
        public var messages: [String]
        public var permissionOverride: PermissionOverride?
        public var permissionReason: String?
        public var updatedInput: String?

        public init(
            denied: Bool = false, failed: Bool = false, cancelled: Bool = false,
            messages: [String] = [], permissionOverride: PermissionOverride? = nil,
            permissionReason: String? = nil, updatedInput: String? = nil
        ) {
            self.denied = denied
            self.failed = failed
            self.cancelled = cancelled
            self.messages = messages
            self.permissionOverride = permissionOverride
            self.permissionReason = permissionReason
            self.updatedInput = updatedInput
        }

        public static func allow(_ messages: [String] = []) -> HookRunResult {
            HookRunResult(messages: messages)
        }

        public var permissionDecision: PermissionOverride? { permissionOverride }

        public func updatedInputJson() -> AnyCodable? {
            guard let s = updatedInput,
                  let data = s.data(using: .utf8),
                  let v = try? JSONDecoder().decode(AnyCodable.self, from: data) else {
                return nil
            }
            return v
        }
    }

    public struct HookRunner: Sendable, Equatable {
        public var config: RuntimeHookConfig

        public init(config: RuntimeHookConfig) {
            self.config = config
        }

        public static func fromFeatureConfig(_ f: RuntimeFeatureConfig) -> HookRunner {
            HookRunner(config: f.hooks)
        }

        public func runPreToolUse(toolName: String, toolInput: String) -> HookRunResult {
            runCommands(.preToolUse, commands: config.preToolUse,
                        toolName: toolName, toolInput: toolInput,
                        toolResult: nil, isError: false)
        }

        public func runPostToolUse(toolName: String, toolInput: String, toolOutput: String, isError: Bool) -> HookRunResult {
            runCommands(.postToolUse, commands: config.postToolUse,
                        toolName: toolName, toolInput: toolInput,
                        toolResult: toolOutput, isError: isError)
        }

        public func runPostToolUseFailure(toolName: String, toolInput: String, toolError: String) -> HookRunResult {
            runCommands(.postToolUseFailure, commands: config.postToolUseFailure,
                        toolName: toolName, toolInput: toolInput,
                        toolResult: toolError, isError: true)
        }

        // MARK: - Core dispatch

        private func runCommands(
            _ event: HookEvent, commands: [String],
            toolName: String, toolInput: String,
            toolResult: String?, isError: Bool
        ) -> HookRunResult {
            guard !commands.isEmpty else { return .allow() }
            var result = HookRunResult()
            for command in commands {
                let outcome = runCommand(
                    event, command: command,
                    toolName: toolName, toolInput: toolInput,
                    toolResult: toolResult, isError: isError
                )
                switch outcome {
                case .allow(let parsed):
                    mergeOutput(&result, parsed: parsed)
                case .deny(let parsed):
                    mergeOutput(&result, parsed: parsed)
                    result.denied = true
                    return result
                case .failed(let msg):
                    result.failed = true
                    result.messages.append(msg)
                    return result
                case .cancelled(let msg):
                    result.cancelled = true
                    result.messages.append(msg)
                    return result
                }
            }
            return result
        }

        private enum HookCommandOutcome {
            case allow(ParsedHookOutput)
            case deny(ParsedHookOutput)
            case failed(String)
            case cancelled(String)
        }

        private struct ParsedHookOutput {
            var messages: [String] = []
            var permissionOverride: PermissionOverride?
            var permissionReason: String?
            var updatedInput: String?
        }

        private func runCommand(
            _ event: HookEvent, command: String,
            toolName: String, toolInput: String,
            toolResult: String?, isError: Bool
        ) -> HookCommandOutcome {
            #if os(macOS) || os(Linux)
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/sh")
            task.arguments = ["-lc", command]
            var env = ProcessInfo.processInfo.environment
            env["HOOK_EVENT"] = event.rawValue
            env["HOOK_TOOL_NAME"] = toolName
            env["HOOK_TOOL_INPUT"] = toolInput
            env["HOOK_TOOL_IS_ERROR"] = isError ? "1" : "0"
            if let r = toolResult { env["HOOK_TOOL_OUTPUT"] = r }
            task.environment = env

            let payload = buildPayload(event: event, toolName: toolName, toolInput: toolInput,
                                       toolResult: toolResult, isError: isError)
            let stdinPipe = Pipe(), stdoutPipe = Pipe(), stderrPipe = Pipe()
            task.standardInput = stdinPipe
            task.standardOutput = stdoutPipe
            task.standardError = stderrPipe
            do {
                try task.run()
                if let data = payload.data(using: .utf8) {
                    try? stdinPipe.fileHandleForWriting.write(contentsOf: data)
                }
                try? stdinPipe.fileHandleForWriting.close()
                task.waitUntilExit()
                let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let stdout = String(data: outData, encoding: .utf8) ?? ""
                let stderr = String(data: errData, encoding: .utf8) ?? ""
                let parsed = parseHookOutput(stdout: stdout, stderr: stderr, command: command, event: event, toolName: toolName)
                switch task.terminationStatus {
                case 0: return .allow(parsed)
                case 2: return .deny(parsed)
                default: return .failed(formatHookWarning(stdout: stdout, stderr: stderr))
                }
            } catch {
                return .failed("hook exec error: \(error.localizedDescription)")
            }
            #else
            return .failed("hooks are not supported on this platform")
            #endif
        }

        private func buildPayload(
            event: HookEvent, toolName: String, toolInput: String,
            toolResult: String?, isError: Bool
        ) -> String {
            var dict: [String: Any] = [
                "hook_event_name": event.rawValue,
                "tool_name": toolName,
                "tool_input_json": toolInput,
            ]
            if let data = toolInput.data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(with: data) {
                dict["tool_input"] = parsed
            } else {
                dict["tool_input"] = ["raw": toolInput]
            }
            if let r = toolResult {
                dict[event == .postToolUseFailure ? "tool_error" : "tool_output"] = r
            }
            dict["tool_result_is_error"] = isError
            if let data = try? JSONSerialization.data(withJSONObject: dict),
               let s = String(data: data, encoding: .utf8) {
                return s
            }
            return ""
        }

        private func parseHookOutput(stdout: String, stderr: String, command: String, event: HookEvent, toolName: String) -> ParsedHookOutput {
            var p = ParsedHookOutput()
            let trimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return p }
            guard let data = trimmed.data(using: .utf8) else { return p }
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let sys = obj["systemMessage"] as? String { p.messages.append(sys) }
                if let reason = obj["reason"] as? String { p.messages.append(reason) }
                if let c = obj["continue"] as? Bool, !c { /* deny handled by caller */ }
                if (obj["decision"] as? String)?.lowercased() == "block" { /* deny */ }
                if let hso = obj["hookSpecificOutput"] as? [String: Any] {
                    if let s = hso["additionalContext"] as? String { p.messages.append(s) }
                    if let decision = hso["permissionDecision"] as? String {
                        switch decision {
                        case "allow": p.permissionOverride = .allow
                        case "deny": p.permissionOverride = .deny
                        case "ask": p.permissionOverride = .ask
                        default: break
                        }
                    }
                    p.permissionReason = hso["permissionDecisionReason"] as? String
                    if let updated = hso["updatedInput"] {
                        p.updatedInput = (try? JSONSerialization.data(withJSONObject: updated))
                            .flatMap { String(data: $0, encoding: .utf8) }
                    }
                }
                if p.messages.isEmpty { p.messages.append(trimmed) }
            } else if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
                p.messages.append("hook_invalid_json: phase=\(event.rawValue) tool=\(toolName) command=\(command) stdout_preview=\(boundedPreview(stdout)) stderr_preview=\(boundedPreview(stderr))")
            } else {
                p.messages.append(trimmed)
            }
            return p
        }

        private func mergeOutput(_ result: inout HookRunResult, parsed: ParsedHookOutput) {
            result.messages.append(contentsOf: parsed.messages)
            if let o = parsed.permissionOverride { result.permissionOverride = o }
            if let r = parsed.permissionReason { result.permissionReason = r }
            if let u = parsed.updatedInput { result.updatedInput = u }
        }

        private func formatHookWarning(stdout: String, stderr: String) -> String {
            "hook failed — stdout=\(boundedPreview(stdout)) stderr=\(boundedPreview(stderr))"
        }

        private func boundedPreview(_ s: String) -> String {
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count <= 160 { return trimmed }
            return String(trimmed.prefix(159)) + "…"
        }
    }
}
