import Foundation

/// Fetches a URL and returns truncated text content.
public struct WebFetchTool: AgentTool {
    public let name = "web_fetch"
    public let description = "Fetch a URL and return its text content (up to 50,000 characters)."

    public let inputSchema: AnyCodable = .object([
        "type": "object",
        "properties": .object([
            "url": .object(["type": "string", "description": "The URL to fetch"]),
            "max_chars": .object(["type": "integer", "description": "Maximum characters to return (default 50000)"])
        ]),
        "required": .array([.string("url")])
    ])

    public init() {}

    public func execute(input: [String: AnyCodable], context: ToolContext) async throws -> ToolOutput {
        guard let urlString = input.string("url"),
              let url = URL(string: urlString) else {
            return .error("Invalid or missing URL")
        }

        let maxChars = input.int("max_chars") ?? 50_000

        do {
            var request = URLRequest(url: url, timeoutInterval: 30)
            request.setValue(
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) ClaudeAgentSDK/1.0",
                forHTTPHeaderField: "User-Agent"
            )
            let (data, response) = try await URLSession.shared.data(for: request)

            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                return .error("HTTP \(http.statusCode) for \(urlString)")
            }

            let raw = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1)
                ?? "(binary content)"

            let stripped = stripHTML(raw)
            let truncated = stripped.count > maxChars
                ? String(stripped.prefix(maxChars)) + "\n\n[truncated — \(stripped.count - maxChars) chars omitted]"
                : stripped

            return ToolOutput(content: truncated)
        } catch {
            return .error("Fetch failed: \(error.localizedDescription)")
        }
    }

    private func stripHTML(_ html: String) -> String {
        // Remove script/style blocks
        var text = html
        for tag in ["script", "style"] {
            while let open = text.range(of: "<\(tag)", options: .caseInsensitive),
                  let close = text.range(of: "</\(tag)>", options: .caseInsensitive, range: open.lowerBound..<text.endIndex) {
                text.removeSubrange(open.lowerBound...close.upperBound)
            }
        }
        // Remove all HTML tags
        if let regex = try? NSRegularExpression(pattern: "<[^>]+>") {
            let range = NSRange(text.startIndex..., in: text)
            text = regex.stringByReplacingMatches(in: text, range: range, withTemplate: " ")
        }
        // Decode common HTML entities
        text = text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
        // Collapse whitespace
        if let ws = try? NSRegularExpression(pattern: "[ \\t]+") {
            text = ws.stringByReplacingMatches(
                in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " "
            )
        }
        if let nl = try? NSRegularExpression(pattern: "\\n{3,}") {
            text = nl.stringByReplacingMatches(
                in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "\n\n"
            )
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
