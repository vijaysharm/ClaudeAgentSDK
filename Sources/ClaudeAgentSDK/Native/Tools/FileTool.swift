import Foundation

// MARK: - ReadFileTool

/// Reads a file with line numbers, supporting offset and limit.
public struct ReadFileTool: AgentTool {
    public let name = "read_file"
    public let description = "Read a file from the filesystem. Returns content with line numbers."

    public let inputSchema: AnyCodable = .object([
        "type": "object",
        "properties": .object([
            "path": .object(["type": "string", "description": "Absolute or relative file path"]),
            "offset": .object(["type": "integer", "description": "Line offset (1-based)"]),
            "limit": .object(["type": "integer", "description": "Max lines to return"])
        ]),
        "required": .array([.string("path")])
    ])

    public init() {}

    public func execute(input: [String: AnyCodable], context: ToolContext) async throws -> ToolOutput {
        guard let path = input.string("path") else { return .error("Missing: path") }
        let url = resolvedToolURL(path: path, cwd: context.workingDirectory)

        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return .error("Cannot read file: \(path)")
        }

        var lines = content.components(separatedBy: "\n")
        let offset = max(0, (input.int("offset") ?? 1) - 1)
        let limit = input.int("limit") ?? Int.max

        if offset < lines.count { lines = Array(lines.dropFirst(offset)) }
        if lines.count > limit { lines = Array(lines.prefix(limit)) }

        let numbered = lines.enumerated().map { idx, line in
            "\(offset + idx + 1)\t\(line)"
        }.joined(separator: "\n")

        return ToolOutput(content: numbered)
    }
}

// MARK: - WriteFileTool

/// Creates or overwrites a file, creating parent directories as needed.
public struct WriteFileTool: AgentTool {
    public let name = "write_file"
    public let description = "Write content to a file, creating parent directories if needed."

    public let inputSchema: AnyCodable = .object([
        "type": "object",
        "properties": .object([
            "path": .object(["type": "string", "description": "File path to write"]),
            "content": .object(["type": "string", "description": "Content to write"])
        ]),
        "required": .array([.string("path"), .string("content")])
    ])

    public init() {}

    public func execute(input: [String: AnyCodable], context: ToolContext) async throws -> ToolOutput {
        guard let path = input.string("path"), let content = input.string("content") else {
            return .error("Missing required parameters: path and content")
        }

        if context.permissionMode == .readOnly {
            return .error("write_file is disabled in read-only mode")
        }

        let url = resolvedToolURL(path: path, cwd: context.workingDirectory)
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try content.write(to: url, atomically: true, encoding: .utf8)
            return ToolOutput(content: "Written \(content.utf8.count) bytes to \(path)")
        } catch {
            return .error("Write failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - EditFileTool

/// Performs an exact string replacement in a file.
public struct EditFileTool: AgentTool {
    public let name = "edit_file"
    public let description = "Replace an exact string in a file. Fails if old_string is not found or is ambiguous."

    public let inputSchema: AnyCodable = .object([
        "type": "object",
        "properties": .object([
            "path": .object(["type": "string"]),
            "old_string": .object(["type": "string", "description": "Exact text to find"]),
            "new_string": .object(["type": "string", "description": "Replacement text"])
        ]),
        "required": .array([.string("path"), .string("old_string"), .string("new_string")])
    ])

    public init() {}

    public func execute(input: [String: AnyCodable], context: ToolContext) async throws -> ToolOutput {
        guard let path = input.string("path"),
              let oldStr = input.string("old_string"),
              let newStr = input.string("new_string") else {
            return .error("Missing required parameters")
        }

        if context.permissionMode == .readOnly {
            return .error("edit_file is disabled in read-only mode")
        }

        let url = resolvedToolURL(path: path, cwd: context.workingDirectory)
        guard var content = try? String(contentsOf: url, encoding: .utf8) else {
            return .error("Cannot read file: \(path)")
        }

        let count = content.components(separatedBy: oldStr).count - 1
        if count == 0 { return .error("old_string not found in \(path)") }
        if count > 1 { return .error("old_string is ambiguous (\(count) occurrences) — provide more context") }

        content = content.replacingOccurrences(of: oldStr, with: newStr)
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            return ToolOutput(content: "Edited \(path)")
        } catch {
            return .error("Write failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - GlobTool

/// Finds files matching a glob pattern using recursive directory enumeration.
public struct GlobTool: AgentTool {
    public let name = "glob"
    public let description = "Find files matching a glob pattern (e.g. **/*.swift, src/**/*.ts)."

    public let inputSchema: AnyCodable = .object([
        "type": "object",
        "properties": .object([
            "pattern": .object(["type": "string", "description": "Glob pattern"]),
            "path": .object(["type": "string", "description": "Root directory (default: cwd)"])
        ]),
        "required": .array([.string("pattern")])
    ])

    public init() {}

    public func execute(input: [String: AnyCodable], context: ToolContext) async throws -> ToolOutput {
        guard let pattern = input.string("pattern") else { return .error("Missing: pattern") }
        let root = input.string("path")
            .map { resolvedToolURL(path: $0, cwd: context.workingDirectory) }
            ?? URL(fileURLWithPath: context.workingDirectory)

        let regex = globToRegex(pattern)
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return .error("Cannot enumerate directory: \(root.path)")
        }

        var matches: [String] = []
        for case let url as URL in enumerator {
            let rel = url.path.replacingOccurrences(of: root.path + "/", with: "")
            if rel.range(of: regex, options: .regularExpression) != nil {
                matches.append(rel)
            }
        }
        matches.sort()

        if matches.isEmpty { return ToolOutput(content: "(no matches)") }
        return ToolOutput(content: matches.joined(separator: "\n"))
    }

    private func globToRegex(_ glob: String) -> String {
        var result = "^"
        var i = glob.startIndex
        while i < glob.endIndex {
            let c = glob[i]
            if c == "*" {
                let next = glob.index(after: i)
                if next < glob.endIndex, glob[next] == "*" {
                    result += ".*"
                    i = glob.index(after: next)
                    if i < glob.endIndex, glob[i] == "/" { i = glob.index(after: i) }
                    continue
                } else {
                    result += "[^/]*"
                }
            } else if c == "?" {
                result += "[^/]"
            } else if ".()+|^$".contains(c) {
                result += "\\\(c)"
            } else {
                result += String(c)
            }
            i = glob.index(after: i)
        }
        result += "$"
        return result
    }
}

// MARK: - GrepTool

/// Searches file content using a regular expression.
public struct GrepTool: AgentTool {
    public let name = "grep"
    public let description = "Search for a regex pattern across files. Returns file:line:content matches."

    public let inputSchema: AnyCodable = .object([
        "type": "object",
        "properties": .object([
            "pattern": .object(["type": "string", "description": "Regular expression pattern"]),
            "path": .object(["type": "string", "description": "File or directory to search"]),
            "glob": .object(["type": "string", "description": "File glob filter (e.g. *.swift)"]),
            "case_insensitive": .object(["type": "boolean"])
        ]),
        "required": .array([.string("pattern")])
    ])

    public init() {}

    public func execute(input: [String: AnyCodable], context: ToolContext) async throws -> ToolOutput {
        guard let pattern = input.string("pattern") else { return .error("Missing: pattern") }
        let searchPath = input.string("path") ?? context.workingDirectory
        let url = resolvedToolURL(path: searchPath, cwd: context.workingDirectory)
        let caseInsensitive = input.bool("case_insensitive") ?? false
        let globFilter = input.string("glob")

        var regexOptions: NSRegularExpression.Options = []
        if caseInsensitive { regexOptions.insert(.caseInsensitive) }

        guard let regex = try? NSRegularExpression(pattern: pattern, options: regexOptions) else {
            return .error("Invalid regex: \(pattern)")
        }

        let fm = FileManager.default
        var isDir: ObjCBool = false
        fm.fileExists(atPath: url.path, isDirectory: &isDir)

        var files: [URL] = []
        if isDir.boolValue {
            if let enumerator = fm.enumerator(
                at: url,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) {
                for case let fileURL as URL in enumerator {
                    if let glob = globFilter {
                        let name = fileURL.lastPathComponent
                        if name.range(of: simpleGlobRegex(glob), options: .regularExpression) == nil { continue }
                    }
                    files.append(fileURL)
                }
            }
        } else {
            files = [url]
        }

        var results: [String] = []
        for fileURL in files.prefix(200) {
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            let lines = content.components(separatedBy: "\n")
            for (lineNum, line) in lines.enumerated() {
                let range = NSRange(line.startIndex..., in: line)
                if regex.firstMatch(in: line, range: range) != nil {
                    let rel = fileURL.path.replacingOccurrences(of: context.workingDirectory + "/", with: "")
                    results.append("\(rel):\(lineNum + 1):\(line)")
                }
            }
        }

        if results.isEmpty { return ToolOutput(content: "(no matches)") }
        let output = results.prefix(500).joined(separator: "\n")
        let suffix = results.count > 500 ? "\n... (\(results.count - 500) more matches)" : ""
        return ToolOutput(content: output + suffix)
    }

    private func simpleGlobRegex(_ glob: String) -> String {
        var result = "^"
        for c in glob {
            if c == "*" { result += ".*" }
            else if c == "?" { result += "." }
            else if ".()+|^$".contains(c) { result += "\\\(c)" }
            else { result += String(c) }
        }
        return result + "$"
    }
}

// MARK: - Shared helper

func resolvedToolURL(path: String, cwd: String) -> URL {
    if path.hasPrefix("/") { return URL(fileURLWithPath: path) }
    return URL(fileURLWithPath: cwd).appendingPathComponent(path)
}
