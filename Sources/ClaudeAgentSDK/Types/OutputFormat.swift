import Foundation

/// Output format configuration for structured responses.
public struct OutputFormat: Codable, Sendable {
    public let type: String
    public let schema: [String: AnyCodable]

    /// Creates a JSON schema output format.
    public static func jsonSchema(_ schema: [String: AnyCodable]) -> OutputFormat {
        OutputFormat(type: "json_schema", schema: schema)
    }
}
