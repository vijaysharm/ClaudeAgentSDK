import Foundation

extension ClawRuntime {

    public struct SummaryCompressionBudget: Sendable, Equatable {
        public var maxChars: Int
        public var maxLines: Int
        public var maxLineChars: Int

        public init(maxChars: Int = 1200, maxLines: Int = 24, maxLineChars: Int = 160) {
            self.maxChars = maxChars
            self.maxLines = maxLines
            self.maxLineChars = maxLineChars
        }

        public static let `default` = SummaryCompressionBudget()
    }

    public struct SummaryCompressionResult: Sendable, Equatable, Codable {
        public var summary: String
        public var originalChars: Int
        public var originalLines: Int
        public var compressedChars: Int
        public var compressedLines: Int
        public var removedDuplicateLines: Int
        public var omittedLines: Int
        public var truncated: Bool
    }

    /// Lightweight summary compressor suitable for prompt-space-constrained
    /// contexts. Matches `runtime::summary_compression::compress_summary`.
    public static func compressSummary(
        _ summary: String, budget: SummaryCompressionBudget = .default
    ) -> SummaryCompressionResult {
        let originalLines = summary.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let originalLineCount = originalLines.count
        let originalChars = summary.count

        // normalize: collapse inline whitespace, drop empty, truncate per-line, dedup
        var seenLower: Set<String> = []
        var normalized: [String] = []
        var removedDuplicates = 0
        for line in originalLines {
            let collapsed = line
                .replacingOccurrences(of: "\t", with: " ")
                .trimmingCharacters(in: .whitespaces)
            if collapsed.isEmpty { continue }
            let truncated = collapsed.count > budget.maxLineChars
                ? String(collapsed.prefix(budget.maxLineChars - 1)) + "…"
                : collapsed
            let lower = truncated.lowercased()
            if seenLower.contains(lower) {
                removedDuplicates += 1
                continue
            }
            seenLower.insert(lower)
            normalized.append(truncated)
        }

        func priority(_ line: String) -> Int {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let priorityPrefixes = [
                "- Scope:", "- Current work:", "- Pending work:",
                "- Key files referenced:", "- Tools mentioned:",
                "- Recent user requests:", "- Previously compacted context:",
                "- Newly compacted context:",
            ]
            if trimmed == "Summary:" || trimmed == "Conversation summary:" { return 0 }
            if priorityPrefixes.contains(where: trimmed.hasPrefix) { return 0 }
            if trimmed.hasSuffix(":") { return 1 }
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("  - ") { return 2 }
            return 3
        }

        let ranked = normalized.enumerated()
            .sorted(by: { a, b in
                if priority(a.element) != priority(b.element) {
                    return priority(a.element) < priority(b.element)
                }
                return a.offset < b.offset
            })

        var chosen: [String] = []
        var chosenIndexSet: Set<Int> = []
        var chars = 0
        for (idx, line) in ranked {
            if chosen.count >= budget.maxLines { break }
            let added = chars == 0 ? line.count : chars + 1 + line.count
            if added > budget.maxChars { break }
            chosen.append(line)
            chosenIndexSet.insert(idx)
            chars = added
        }
        // preserve original order
        chosen = normalized.enumerated().compactMap {
            chosenIndexSet.contains($0.offset) ? $0.element : nil
        }

        let omitted = normalized.count - chosen.count
        var truncatedFlag = false
        if omitted > 0 {
            let notice = "- … \(omitted) additional line(s) omitted."
            if chars + 1 + notice.count <= budget.maxChars,
               chosen.count < budget.maxLines {
                chosen.append(notice)
                truncatedFlag = true
            }
        }

        let compressed = chosen.joined(separator: "\n")
        return SummaryCompressionResult(
            summary: compressed,
            originalChars: originalChars,
            originalLines: originalLineCount,
            compressedChars: compressed.count,
            compressedLines: chosen.count,
            removedDuplicateLines: removedDuplicates,
            omittedLines: max(0, omitted),
            truncated: truncatedFlag
        )
    }

    public static func compressSummaryText(_ summary: String) -> String {
        compressSummary(summary).summary
    }
}
