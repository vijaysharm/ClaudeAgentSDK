import Testing
import Foundation
@testable import ClaudeAgentSDK

@Suite("AnyCodable")
struct AnyCodableTests {

    @Test("Decode JSON with mixed types")
    func decodeMixed() throws {
        let json = """
        {"string":"hello","int":42,"double":3.14,"bool":true,"null":null,"array":[1,2,3],"nested":{"key":"value"}}
        """
        let decoded = try JSONDecoder().decode([String: AnyCodable].self, from: Data(json.utf8))

        #expect(decoded["string"]?.stringValue == "hello")
        #expect(decoded["int"]?.intValue == 42)
        #expect(decoded["double"]?.doubleValue == 3.14)
        #expect(decoded["bool"]?.boolValue == true)
        #expect(decoded["null"]?.isNull == true)
        #expect(decoded["array"]?.arrayValue?.count == 3)
        #expect(decoded["nested"]?["key"]?.stringValue == "value")
    }

    @Test("Encode and decode roundtrip")
    func roundtrip() throws {
        let original: [String: AnyCodable] = [
            "name": "test",
            "count": 42,
            "enabled": true,
            "tags": ["a", "b"],
            "meta": ["x": 1],
        ]

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode([String: AnyCodable].self, from: data)

        #expect(decoded["name"]?.stringValue == "test")
        #expect(decoded["count"]?.intValue == 42)
        #expect(decoded["enabled"]?.boolValue == true)
        #expect(decoded["tags"]?.arrayValue?.count == 2)
        #expect(decoded["meta"]?["x"]?.intValue == 1)
    }

    @Test("Literal initializers")
    func literals() {
        let null: AnyCodable = nil
        let bool: AnyCodable = true
        let int: AnyCodable = 42
        let double: AnyCodable = 3.14
        let string: AnyCodable = "hello"
        let array: AnyCodable = [1, 2, 3]
        let dict: AnyCodable = ["key": "value"]

        #expect(null.isNull)
        #expect(bool.boolValue == true)
        #expect(int.intValue == 42)
        #expect(double.doubleValue == 3.14)
        #expect(string.stringValue == "hello")
        #expect(array.arrayValue?.count == 3)
        #expect(dict["key"]?.stringValue == "value")
    }

    @Test("Subscript access")
    func subscriptAccess() {
        let obj: AnyCodable = ["items": [1, 2, 3]]
        #expect(obj["items"]?[1]?.intValue == 2)
        #expect(obj["missing"] == nil)

        let arr: AnyCodable = [10, 20, 30]
        #expect(arr[0]?.intValue == 10)
        #expect(arr[5] == nil)
    }

    @Test("Equatable")
    func equatable() {
        #expect(AnyCodable.string("hello") == AnyCodable.string("hello"))
        #expect(AnyCodable.int(42) != AnyCodable.int(43))
        #expect(AnyCodable.null == AnyCodable.null)
    }
}
