import Testing
import Foundation
@testable import ClaudeAgentSDK

@Suite("Settings")
struct SettingsTests {
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    @Test("Settings encodes and decodes basic fields")
    func basicRoundtrip() throws {
        let settings = Settings(
            permissions: PermissionSettings(allow: ["Read", "Glob"], deny: ["Bash"]),
            model: "claude-sonnet-4-6",
            disableAllHooks: true
        )

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(settings)
        let decoded = try decoder.decode(Settings.self, from: data)

        #expect(decoded.model == "claude-sonnet-4-6")
        #expect(decoded.permissions?.allow == ["Read", "Glob"])
        #expect(decoded.permissions?.deny == ["Bash"])
        #expect(decoded.disableAllHooks == true)
    }

    @Test("Settings preserves additional settings")
    func additionalSettings() throws {
        let settings = Settings(
            model: "opus",
            additionalSettings: [
                "customField": .string("customValue"),
                "nestedObj": .object(["key": .int(42)])
            ]
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(settings)
        let decoded = try decoder.decode(Settings.self, from: data)

        #expect(decoded.model == "opus")
        #expect(decoded.additionalSettings?["customField"]?.stringValue == "customValue")
        #expect(decoded.additionalSettings?["nestedObj"]?["key"]?.intValue == 42)
    }

    @Test("Settings decodes unknown keys into additionalSettings")
    func unknownKeysPreserved() throws {
        let json = """
        {"model":"test","unknownPlugin":{"enabled":true},"anotherField":123}
        """
        let decoded = try decoder.decode(Settings.self, from: Data(json.utf8))

        #expect(decoded.model == "test")
        #expect(decoded.additionalSettings?["unknownPlugin"]?["enabled"]?.boolValue == true)
        #expect(decoded.additionalSettings?["anotherField"]?.intValue == 123)
    }

    @Test("PermissionSettings roundtrip")
    func permissionSettings() throws {
        let perms = PermissionSettings(
            allow: ["Read(*)", "Glob(*)"],
            deny: ["Bash(rm*)"],
            defaultMode: .acceptEdits,
            additionalDirectories: ["/tmp"]
        )

        let data = try JSONEncoder().encode(perms)
        let decoded = try decoder.decode(PermissionSettings.self, from: data)

        #expect(decoded.allow == ["Read(*)", "Glob(*)"])
        #expect(decoded.deny == ["Bash(rm*)"])
        #expect(decoded.defaultMode == .acceptEdits)
        #expect(decoded.additionalDirectories == ["/tmp"])
    }

    @Test("AttributionSettings roundtrip")
    func attributionSettings() throws {
        let attr = AttributionSettings(commit: "AI-generated", pr: "Created by Claude")
        let data = try JSONEncoder().encode(attr)
        let decoded = try decoder.decode(AttributionSettings.self, from: data)

        #expect(decoded.commit == "AI-generated")
        #expect(decoded.pr == "Created by Claude")
    }

    @Test("Settings serialized in CLI args")
    func settingsInCLIArgs() {
        let options = Options(
            settings: Settings(model: "test-model", disableAllHooks: true)
        )
        let args = CLIArgumentBuilder.buildArguments(options: options, prompt: "hi", isStreaming: false)
        #expect(args.contains("--settings"))
    }
}
