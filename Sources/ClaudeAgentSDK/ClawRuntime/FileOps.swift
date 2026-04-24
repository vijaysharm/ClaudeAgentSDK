import Foundation

extension ClawRuntime {

    public static let maxFileReadSize: UInt64 = 10 * 1024 * 1024
    public static let maxFileWriteSize: Int = 10 * 1024 * 1024

    // MARK: - DTOs

    public struct TextFilePayload: Sendable, Equatable, Codable {
        public var filePath: String
        public var content: String
        public var numLines: Int
        public var startLine: Int
        public var totalLines: Int
    }

    public struct ReadFileOutput: Sendable, Equatable, Codable {
        public var kind: String  // "text"
        public var file: TextFilePayload
    }

    public struct StructuredPatchHunk: Sendable, Equatable, Codable {
        public var oldStart: Int
        public var oldLines: Int
        public var newStart: Int
        public var newLines: Int
        public var lines: [String]
    }

    public struct WriteFileOutput: Sendable, Equatable, Codable {
        public var kind: String  // "create" | "update"
        public var filePath: String
        public var content: String
        public var structuredPatch: [StructuredPatchHunk]
        public var originalFile: String?
    }

    public struct EditFileOutput: Sendable, Equatable, Codable {
        public var filePath: String
        public var oldString: String
        public var newString: String
        public var originalFile: String
        public var structuredPatch: [StructuredPatchHunk]
        public var userModified: Bool
        public var replaceAll: Bool
    }

    public struct GlobSearchOutput: Sendable, Equatable, Codable {
        public var durationMs: Int
        public var numFiles: Int
        public var filenames: [String]
        public var truncated: Bool
    }

    // MARK: - Read / Write / Edit

    public enum FileOpsError: Error, LocalizedError {
        case fileTooLarge(String, UInt64)
        case notFound(String)
        case io(String)

        public var errorDescription: String? {
            switch self {
            case .fileTooLarge(let path, let size): return "file too large (\(size) bytes): \(path)"
            case .notFound(let path): return "file not found: \(path)"
            case .io(let m): return m
            }
        }
    }

    public static func readFile(_ path: String, offset: Int = 0, limit: Int? = nil) throws -> ReadFileOutput {
        let url = URL(fileURLWithPath: path)
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs[.size] as? Int) ?? 0
        if UInt64(size) > maxFileReadSize {
            throw FileOpsError.fileTooLarge(path, UInt64(size))
        }
        let data = try Data(contentsOf: url)
        if isBinary(data) {
            throw FileOpsError.io("refusing to read binary file: \(path)")
        }
        let str = String(data: data, encoding: .utf8) ?? ""
        let allLines = str.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let total = allLines.count
        let start = max(0, min(offset, total))
        let end = limit.map { min(start + $0, total) } ?? total
        let slice = Array(allLines[start..<end])
        return ReadFileOutput(
            kind: "text",
            file: TextFilePayload(
                filePath: url.path,
                content: slice.joined(separator: "\n"),
                numLines: slice.count,
                startLine: start + 1,
                totalLines: total
            )
        )
    }

    public static func writeFile(_ path: String, content: String) throws -> WriteFileOutput {
        let data = Data(content.utf8)
        guard data.count <= maxFileWriteSize else {
            throw FileOpsError.fileTooLarge(path, UInt64(data.count))
        }
        let url = URL(fileURLWithPath: path)
        let wasExisting = FileManager.default.fileExists(atPath: url.path)
        var original: String?
        if wasExisting {
            original = try? String(contentsOf: url, encoding: .utf8)
        }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url)
        return WriteFileOutput(
            kind: wasExisting ? "update" : "create",
            filePath: url.path,
            content: content,
            structuredPatch: makePatch(original: original ?? "", updated: content),
            originalFile: original
        )
    }

    public static func editFile(
        _ path: String, oldString: String, newString: String, replaceAll: Bool
    ) throws -> EditFileOutput {
        if oldString == newString {
            throw FileOpsError.io("old_string and new_string must differ")
        }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw FileOpsError.notFound(path)
        }
        let original = try String(contentsOf: url, encoding: .utf8)
        let updated: String
        if replaceAll {
            updated = original.replacingOccurrences(of: oldString, with: newString)
        } else if let range = original.range(of: oldString) {
            updated = original.replacingCharacters(in: range, with: newString)
        } else {
            throw FileOpsError.io("old_string not found in file")
        }
        try Data(updated.utf8).write(to: url)
        return EditFileOutput(
            filePath: url.path,
            oldString: oldString,
            newString: newString,
            originalFile: original,
            structuredPatch: makePatch(original: original, updated: updated),
            userModified: false,
            replaceAll: replaceAll
        )
    }

    // MARK: - Glob search

    public static func globSearch(pattern: String, path: String? = nil) throws -> GlobSearchOutput {
        let start = Date()
        let baseDir = path ?? FileManager.default.currentDirectoryPath
        let expanded = expandBraces(pattern)
        var matches: Set<String> = []
        for pat in expanded {
            let fullPattern = pat.hasPrefix("/") ? pat : (baseDir as NSString).appendingPathComponent(pat)
            for m in globMatch(pattern: fullPattern) {
                matches.insert(m)
            }
        }
        // sort by modified time desc
        var filesWithDates: [(String, Date)] = []
        for f in matches {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: f),
               let date = attrs[.modificationDate] as? Date {
                filesWithDates.append((f, date))
            } else {
                filesWithDates.append((f, Date(timeIntervalSince1970: 0)))
            }
        }
        filesWithDates.sort { $0.1 > $1.1 }
        let names = filesWithDates.map { $0.0 }
        let truncated = names.count > 100
        let limited = truncated ? Array(names.prefix(100)) : names
        let dur = Int(Date().timeIntervalSince(start) * 1000)
        return GlobSearchOutput(
            durationMs: dur, numFiles: limited.count,
            filenames: limited, truncated: truncated
        )
    }

    // MARK: - Helpers

    static func isBinary(_ data: Data) -> Bool {
        let prefix = data.prefix(8192)
        return prefix.contains(0)
    }

    static func makePatch(original: String, updated: String) -> [StructuredPatchHunk] {
        let oldLines = original.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let newLines = updated.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if oldLines == newLines { return [] }
        var lines: [String] = []
        for l in oldLines { lines.append("-\(l)") }
        for l in newLines { lines.append("+\(l)") }
        return [StructuredPatchHunk(
            oldStart: 1, oldLines: oldLines.count,
            newStart: 1, newLines: newLines.count,
            lines: lines
        )]
    }

    /// Minimal one-level brace expansion: `a/{b,c}` → [`a/b`, `a/c`].
    public static func expandBraces(_ pattern: String) -> [String] {
        guard let open = pattern.firstIndex(of: "{"),
              let close = pattern[open...].firstIndex(of: "}") else {
            return [pattern]
        }
        let prefix = String(pattern[..<open])
        let suffix = String(pattern[pattern.index(after: close)...])
        let parts = pattern[pattern.index(after: open)..<close]
            .split(separator: ",").map(String.init)
        var results: [String] = []
        for p in parts {
            results.append(contentsOf: expandBraces(prefix + p + suffix))
        }
        return results
    }

    /// Very light glob matcher sufficient for `**/*.swift`-style patterns.
    static func globMatch(pattern: String) -> [String] {
        let fm = FileManager.default
        let base = (pattern as NSString).deletingLastPathComponent
        let leaf = (pattern as NSString).lastPathComponent
        var results: [String] = []
        guard let iter = fm.enumerator(atPath: base) else { return [] }
        let regex = globToRegex(leaf)
        for case let rel as String in iter {
            let full = (base as NSString).appendingPathComponent(rel)
            let tail = (full as NSString).lastPathComponent
            if regex.firstMatch(in: tail, options: [], range: NSRange(location: 0, length: tail.utf16.count)) != nil {
                results.append(full)
            }
        }
        return results
    }

    static func globToRegex(_ g: String) -> NSRegularExpression {
        var r = "^"
        for c in g {
            switch c {
            case "*": r += ".*"
            case "?": r += "."
            case ".": r += "\\."
            default: r += NSRegularExpression.escapedPattern(for: String(c))
            }
        }
        r += "$"
        return (try? NSRegularExpression(pattern: r)) ?? (try! NSRegularExpression(pattern: "^$"))
    }
}
