import Foundation

// MARK: - Session Management Types

/// Options for listing sessions.
public struct ListSessionsOptions: Sendable {
    /// Directory to list sessions for.
    public var dir: String?
    /// Maximum number of sessions to return.
    public var limit: Int?
    /// Number of sessions to skip.
    public var offset: Int?

    public init(dir: String? = nil, limit: Int? = nil, offset: Int? = nil) {
        self.dir = dir
        self.limit = limit
        self.offset = offset
    }
}

/// Result of a fork operation.
public struct ForkSessionResult: Codable, Sendable {
    /// New session UUID.
    public let sessionId: String
}

// MARK: - JSONL Entry Types (internal)

/// A raw entry from a session JSONL file.
struct SessionJSONLEntry: Codable, Sendable {
    let type: String
    let uuid: String?
    let parentUuid: String?
    let isSidechain: Bool?
    let timestamp: String?
    let message: AnyCodable?
    // custom-title entry
    let title: String?
    // summary entry
    let summary: String?
    // session metadata
    let sessionId: String?
    let cwd: String?
    let model: String?
    // tag entry
    let tag: String?
}

// MARK: - Session File Discovery

/// Resolves the Claude projects directory.
private func claudeProjectsDir() -> URL {
    let home = FileManager.default.homeDirectoryForCurrentUser
    return home.appendingPathComponent(".claude/projects")
}

/// Convert a directory path to the Claude project hash format.
/// Claude uses the path with `/` replaced by `-` and prefixed with `-`.
private func projectHash(for dir: String) -> String {
    let normalized = dir.hasPrefix("/") ? dir : "/\(dir)"
    return normalized.replacingOccurrences(of: "/", with: "-")
}

/// Find all session JSONL files, optionally filtered by project directory.
private func findSessionFiles(dir: String? = nil) throws -> [(url: URL, projectDir: String)] {
    let fm = FileManager.default
    let projectsDir = claudeProjectsDir()

    guard fm.fileExists(atPath: projectsDir.path) else { return [] }

    var results: [(URL, String)] = []

    if let dir {
        let hash = projectHash(for: dir)
        let projectDir = projectsDir.appendingPathComponent(hash)
        guard fm.fileExists(atPath: projectDir.path) else { return [] }

        let contents = try fm.contentsOfDirectory(at: projectDir, includingPropertiesForKeys: [.contentModificationDateKey])
        for url in contents where url.pathExtension == "jsonl" {
            results.append((url, dir))
        }
    } else {
        let projectDirs = try fm.contentsOfDirectory(at: projectsDir, includingPropertiesForKeys: nil)
        for projectDir in projectDirs {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: projectDir.path, isDirectory: &isDir), isDir.boolValue else { continue }

            let contents = try fm.contentsOfDirectory(at: projectDir, includingPropertiesForKeys: [.contentModificationDateKey])
            for url in contents where url.pathExtension == "jsonl" {
                let dirName = projectDir.lastPathComponent
                results.append((url, dirName))
            }
        }
    }

    return results
}

/// Parse metadata from a session JSONL file.
private func parseSessionMetadata(url: URL) throws -> SDKSessionInfo? {
    let fm = FileManager.default
    guard let attrs = try? fm.attributesOfItem(atPath: url.path) else { return nil }

    let fileSize = (attrs[.size] as? Int) ?? 0
    let modDate = (attrs[.modificationDate] as? Date) ?? Date()

    let sessionId = url.deletingPathExtension().lastPathComponent

    // Read the file to extract metadata
    guard let data = fm.contents(atPath: url.path),
          let content = String(data: data, encoding: .utf8) else { return nil }

    let lines = content.split(separator: "\n", omittingEmptySubsequences: true)
    guard !lines.isEmpty else { return nil }

    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase

    var firstPrompt: String?
    var customTitle: String?
    var tag: String?
    var cwd: String?
    var createdAt: Double?

    for line in lines {
        guard let entry = try? decoder.decode(SessionJSONLEntry.self, from: Data(line.utf8)) else { continue }

        // Extract creation time from first timestamped entry
        if createdAt == nil, let ts = entry.timestamp {
            if let date = ISO8601DateFormatter().date(from: ts) {
                createdAt = date.timeIntervalSince1970 * 1000
            }
        }

        switch entry.type {
        case "user":
            if firstPrompt == nil, entry.isSidechain != true {
                // Extract text from message content
                if let content = entry.message?["content"] {
                    if let text = content.stringValue, !text.isEmpty {
                        firstPrompt = text
                    } else if let arr = content.arrayValue {
                        for block in arr {
                            if let text = block["text"]?.stringValue, !text.isEmpty {
                                firstPrompt = text
                                break
                            }
                        }
                    }
                }
            }
        case "custom-title":
            customTitle = entry.title
        case "system":
            if cwd == nil {
                cwd = entry.cwd
            }
        default:
            break
        }

        // Check for tag in any entry type
        if let t = entry.tag {
            tag = t
        }
    }

    let summary = customTitle ?? firstPrompt ?? "Untitled session"

    return SDKSessionInfo(
        sessionId: sessionId,
        summary: summary,
        lastModified: modDate.timeIntervalSince1970 * 1000,
        fileSize: fileSize,
        customTitle: customTitle,
        firstPrompt: firstPrompt,
        gitBranch: nil,
        cwd: cwd,
        tag: tag,
        createdAt: createdAt
    )
}

// MARK: - Public API

extension ClaudeAgentSDK {

    /// List sessions with metadata.
    ///
    /// - Parameter options: Filtering and pagination options.
    /// - Returns: Array of session metadata, sorted by last modified (newest first).
    public static func listSessions(
        options: ListSessionsOptions = ListSessionsOptions()
    ) async throws -> [SDKSessionInfo] {
        #if os(macOS)
        let files = try findSessionFiles(dir: options.dir)

        var sessions: [SDKSessionInfo] = []
        for (url, _) in files {
            if let info = try? parseSessionMetadata(url: url) {
                sessions.append(info)
            }
        }

        // Sort by lastModified descending
        sessions.sort { $0.lastModified > $1.lastModified }

        // Apply pagination
        let offset = options.offset ?? 0
        let limit = options.limit ?? sessions.count

        let start = min(offset, sessions.count)
        let end = min(start + limit, sessions.count)

        return Array(sessions[start..<end])
        #else
        throw ClaudeAgentSDKError.unsupportedPlatform
        #endif
    }

    /// Get metadata for a single session.
    ///
    /// - Parameters:
    ///   - sessionId: UUID of the session.
    ///   - dir: Optional project directory to search in.
    /// - Returns: Session metadata, or nil if not found.
    public static func getSessionInfo(
        _ sessionId: String,
        dir: String? = nil
    ) async throws -> SDKSessionInfo? {
        #if os(macOS)
        let files = try findSessionFiles(dir: dir)
        for (url, _) in files {
            let fileSessionId = url.deletingPathExtension().lastPathComponent
            if fileSessionId == sessionId {
                return try parseSessionMetadata(url: url)
            }
        }
        return nil
        #else
        throw ClaudeAgentSDKError.unsupportedPlatform
        #endif
    }

    /// Read conversation messages from a session.
    ///
    /// - Parameters:
    ///   - sessionId: UUID of the session.
    ///   - dir: Optional project directory.
    ///   - limit: Maximum messages to return.
    ///   - offset: Messages to skip from the start.
    /// - Returns: Array of user/assistant messages.
    public static func getSessionMessages(
        _ sessionId: String,
        dir: String? = nil,
        limit: Int? = nil,
        offset: Int? = nil
    ) async throws -> [SessionMessage] {
        #if os(macOS)
        let files = try findSessionFiles(dir: dir)

        for (url, _) in files {
            let fileSessionId = url.deletingPathExtension().lastPathComponent
            guard fileSessionId == sessionId else { continue }

            guard let data = FileManager.default.contents(atPath: url.path),
                  let content = String(data: data, encoding: .utf8) else { return [] }

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase

            var messages: [SessionMessage] = []
            for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
                guard let entry = try? decoder.decode(SessionJSONLEntry.self, from: Data(line.utf8)) else { continue }
                guard entry.type == "user" || entry.type == "assistant" else { continue }
                guard entry.isSidechain != true else { continue }
                guard let uuid = entry.uuid else { continue }

                messages.append(SessionMessage(
                    type: entry.type,
                    uuid: uuid,
                    sessionId: sessionId,
                    message: entry.message ?? .null,
                    parentToolUseId: nil
                ))
            }

            // Apply pagination
            let off = offset ?? 0
            let lim = limit ?? messages.count
            let start = min(off, messages.count)
            let end = min(start + lim, messages.count)

            return Array(messages[start..<end])
        }

        return []
        #else
        throw ClaudeAgentSDKError.unsupportedPlatform
        #endif
    }

    /// Rename a session by appending a custom-title entry to its JSONL file.
    ///
    /// - Parameters:
    ///   - sessionId: UUID of the session.
    ///   - title: New title for the session.
    ///   - dir: Optional project directory.
    public static func renameSession(
        _ sessionId: String,
        title: String,
        dir: String? = nil
    ) async throws {
        #if os(macOS)
        let url = try findSessionFile(sessionId: sessionId, dir: dir)
        let entry: [String: AnyCodable] = [
            "type": .string("custom-title"),
            "title": .string(title),
        ]
        try appendJSONLEntry(entry, to: url)
        #else
        throw ClaudeAgentSDKError.unsupportedPlatform
        #endif
    }

    /// Tag a session. Pass nil to clear the tag.
    ///
    /// - Parameters:
    ///   - sessionId: UUID of the session.
    ///   - tag: Tag string, or nil to clear.
    ///   - dir: Optional project directory.
    public static func tagSession(
        _ sessionId: String,
        tag: String?,
        dir: String? = nil
    ) async throws {
        #if os(macOS)
        let url = try findSessionFile(sessionId: sessionId, dir: dir)
        let entry: [String: AnyCodable] = [
            "type": .string("tag"),
            "tag": tag.map { .string($0) } ?? .null,
        ]
        try appendJSONLEntry(entry, to: url)
        #else
        throw ClaudeAgentSDKError.unsupportedPlatform
        #endif
    }

    /// Fork a session into a new session.
    ///
    /// - Parameters:
    ///   - sessionId: UUID of the source session.
    ///   - upToMessageId: Optional message UUID to fork up to (inclusive).
    ///   - title: Optional title for the fork.
    ///   - dir: Optional project directory.
    /// - Returns: The new session's ID.
    public static func forkSession(
        _ sessionId: String,
        upToMessageId: String? = nil,
        title: String? = nil,
        dir: String? = nil
    ) async throws -> ForkSessionResult {
        #if os(macOS)
        let sourceURL = try findSessionFile(sessionId: sessionId, dir: dir)

        guard let data = FileManager.default.contents(atPath: sourceURL.path),
              let content = String(data: data, encoding: .utf8) else {
            throw ClaudeAgentSDKError.sessionError("Cannot read session file")
        }

        let newSessionId = UUID().uuidString.lowercased()
        let newURL = sourceURL.deletingLastPathComponent()
            .appendingPathComponent("\(newSessionId).jsonl")

        var lines = content.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)

        // If upToMessageId is specified, truncate at that message
        if let upTo = upToMessageId {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            var truncatedLines: [String] = []
            for line in lines {
                truncatedLines.append(line)
                if let entry = try? decoder.decode(SessionJSONLEntry.self, from: Data(line.utf8)),
                   entry.uuid == upTo {
                    break
                }
            }
            lines = truncatedLines
        }

        // Write to new file
        var output = lines.joined(separator: "\n")
        if !output.isEmpty { output += "\n" }

        // Add custom title if provided
        if let title {
            let titleEntry = "{\"type\":\"custom-title\",\"title\":\"\(title)\"}"
            output += titleEntry + "\n"
        }

        try output.write(to: newURL, atomically: true, encoding: .utf8)

        return ForkSessionResult(sessionId: newSessionId)
        #else
        throw ClaudeAgentSDKError.unsupportedPlatform
        #endif
    }

    // MARK: - Internal Helpers

    #if os(macOS)
    private static func findSessionFile(sessionId: String, dir: String?) throws -> URL {
        let files = try findSessionFiles(dir: dir)
        for (url, _) in files {
            if url.deletingPathExtension().lastPathComponent == sessionId {
                return url
            }
        }
        throw ClaudeAgentSDKError.sessionError("Session not found: \(sessionId)")
    }

    private static func appendJSONLEntry(_ entry: [String: AnyCodable], to url: URL) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(entry)
        guard var json = String(data: data, encoding: .utf8) else {
            throw ClaudeAgentSDKError.encodingError
        }
        json += "\n"

        let handle = try FileHandle(forWritingTo: url)
        handle.seekToEndOfFile()
        handle.write(Data(json.utf8))
        handle.closeFile()
    }
    #endif
}
