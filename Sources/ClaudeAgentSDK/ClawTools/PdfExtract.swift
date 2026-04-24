import Foundation
#if canImport(Compression)
import Compression
#endif

/// Lightweight PDF text extractor ported from the Rust `tools::pdf_extract` module.
///
/// This is intentionally minimal — it handles text inside `BT`/`ET` markers in
/// (optionally FlateDecode-compressed) PDF content streams, and understands the
/// common `Tj`, `TJ`, `'`, and `"` text-showing operators.
public enum ClawToolsPdfExtract {

    /// Extract all text from a PDF file.
    public static func extractText(path: String) throws -> String {
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)
        return extractText(from: data)
    }

    /// Extract text from in-memory PDF bytes.
    public static func extractText(from data: Data) -> String {
        var result = ""
        let bytes = Array(data)
        var cursor = 0
        let streamOpen = Array("stream".utf8)
        let streamClose = Array("endstream".utf8)

        while cursor < bytes.count {
            guard let openStart = findSubsequence(bytes, streamOpen, from: cursor) else { break }
            let afterOpen = skipStreamEOL(bytes, start: openStart + streamOpen.count)
            guard let closeStart = findSubsequence(bytes, streamClose, from: afterOpen) else { break }

            let backStart = max(0, openStart - 512)
            let backWindow = Array(bytes[backStart..<openStart])
            let streamBytes = Array(bytes[afterOpen..<closeStart])
            let decoded: [UInt8]
            if containsSubsequence(backWindow, Array("FlateDecode".utf8)),
               let inflated = inflate(streamBytes) {
                decoded = inflated
            } else {
                decoded = streamBytes
            }
            result += extractBTETText(decoded)
            cursor = closeStart + streamClose.count
        }
        return result
    }

    public static func looksLikePDFPath(_ text: String) -> String? {
        for raw in text.split(separator: " ", omittingEmptySubsequences: true) {
            var token = String(raw)
            // strip quote marks
            for q: Character in ["\"", "'"] {
                if token.first == q { token.removeFirst() }
                if token.last == q { token.removeLast() }
            }
            if token.lowercased().hasSuffix(".pdf") { return token }
        }
        return nil
    }

    public static func maybeExtractPdfFromPrompt(_ prompt: String) -> (path: String, text: String)? {
        guard let path = looksLikePDFPath(prompt) else { return nil }
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        guard let text = try? extractText(path: path), !text.isEmpty else { return nil }
        return (path, text)
    }

    // MARK: - Inner primitives

    static func extractBTETText(_ bytes: [UInt8]) -> String {
        let bt = Array("BT".utf8), et = Array("ET".utf8)
        var result = ""
        var cursor = 0
        while cursor < bytes.count {
            guard let bStart = findSubsequence(bytes, bt, from: cursor) else { break }
            guard let eStart = findSubsequence(bytes, et, from: bStart + bt.count) else { break }
            let scope = Array(bytes[(bStart + bt.count)..<eStart])
            result += parseTextOperators(scope) + "\n"
            cursor = eStart + et.count
        }
        return result
    }

    static func parseTextOperators(_ bytes: [UInt8]) -> String {
        var result = ""
        var cursor = 0
        while cursor < bytes.count {
            let c = bytes[cursor]
            if c == UInt8(ascii: "(") {
                if let (text, next) = extractParenthesizedString(bytes, from: cursor) {
                    result += text
                    cursor = next
                    continue
                }
            }
            if c == UInt8(ascii: "[") {
                if let (text, next) = extractTJArray(bytes, from: cursor) {
                    result += text
                    cursor = next
                    continue
                }
            }
            cursor += 1
        }
        return result
    }

    static func extractParenthesizedString(_ bytes: [UInt8], from: Int) -> (String, Int)? {
        guard from < bytes.count, bytes[from] == UInt8(ascii: "(") else { return nil }
        var depth = 1
        var buf: [UInt8] = []
        var i = from + 1
        while i < bytes.count {
            let c = bytes[i]
            if c == UInt8(ascii: "\\") {
                i += 1
                if i < bytes.count {
                    let esc = bytes[i]
                    switch esc {
                    case UInt8(ascii: "n"): buf.append(0x0A)
                    case UInt8(ascii: "r"): buf.append(0x0D)
                    case UInt8(ascii: "t"): buf.append(0x09)
                    case UInt8(ascii: "\\"): buf.append(0x5C)
                    case UInt8(ascii: "("): buf.append(0x28)
                    case UInt8(ascii: ")"): buf.append(0x29)
                    default:
                        // 3-digit octal?
                        if esc >= UInt8(ascii: "0") && esc <= UInt8(ascii: "7"),
                           i + 2 < bytes.count {
                            let s = String(bytes: [esc, bytes[i+1], bytes[i+2]], encoding: .ascii) ?? ""
                            if let v = UInt8(s, radix: 8) {
                                buf.append(v)
                                i += 2
                            }
                        } else {
                            buf.append(esc)
                        }
                    }
                    i += 1
                    continue
                }
            } else if c == UInt8(ascii: "(") {
                depth += 1; buf.append(c)
            } else if c == UInt8(ascii: ")") {
                depth -= 1
                if depth == 0 {
                    return (String(bytes: buf, encoding: .utf8)
                        ?? String(bytes: buf, encoding: .isoLatin1) ?? "", i + 1)
                }
                buf.append(c)
            } else {
                buf.append(c)
            }
            i += 1
        }
        return nil
    }

    static func extractTJArray(_ bytes: [UInt8], from: Int) -> (String, Int)? {
        guard from < bytes.count, bytes[from] == UInt8(ascii: "[") else { return nil }
        var i = from + 1
        var buf = ""
        while i < bytes.count {
            let c = bytes[i]
            if c == UInt8(ascii: "]") { return (buf, i + 1) }
            if c == UInt8(ascii: "(") {
                if let (t, next) = extractParenthesizedString(bytes, from: i) {
                    buf += t
                    i = next
                    continue
                }
            }
            i += 1
        }
        return nil
    }

    static func skipStreamEOL(_ bytes: [UInt8], start: Int) -> Int {
        var i = start
        if i < bytes.count, bytes[i] == 0x0D { i += 1 }
        if i < bytes.count, bytes[i] == 0x0A { i += 1 }
        return i
    }

    static func findSubsequence(_ haystack: [UInt8], _ needle: [UInt8], from: Int = 0) -> Int? {
        guard !needle.isEmpty, haystack.count >= needle.count else { return nil }
        var i = from
        while i + needle.count <= haystack.count {
            if Array(haystack[i..<(i + needle.count)]) == needle { return i }
            i += 1
        }
        return nil
    }

    static func containsSubsequence(_ haystack: [UInt8], _ needle: [UInt8]) -> Bool {
        findSubsequence(haystack, needle) != nil
    }

    static func inflate(_ data: [UInt8]) -> [UInt8]? {
        #if canImport(Compression)
        guard data.count >= 6 else { return nil }
        let trimmed = Array(data.dropFirst(2)) // strip zlib header
        var result = [UInt8](repeating: 0, count: max(1, data.count * 8))
        let written = trimmed.withUnsafeBufferPointer { src -> Int in
            result.withUnsafeMutableBufferPointer { dest -> Int in
                compression_decode_buffer(
                    dest.baseAddress!, dest.count,
                    src.baseAddress!, src.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        if written == 0 { return nil }
        return Array(result.prefix(written))
        #else
        return nil
        #endif
    }
}
