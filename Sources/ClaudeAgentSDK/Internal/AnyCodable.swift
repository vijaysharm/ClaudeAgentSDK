import Foundation

/// A type-erased JSON value that is both `Codable` and `Sendable`.
///
/// Uses a recursive enum internally instead of `Any` to satisfy strict concurrency.
/// Represents any valid JSON value: null, bool, int, double, string, array, or object.
public enum AnyCodable: Sendable, Equatable, Hashable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([AnyCodable])
    case object([String: AnyCodable])
}

// MARK: - Codable

extension AnyCodable: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([AnyCodable].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: AnyCodable].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unable to decode AnyCodable value"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }
}

// MARK: - Convenience Initializers

extension AnyCodable: ExpressibleByNilLiteral {
    public init(nilLiteral: ()) { self = .null }
}

extension AnyCodable: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) { self = .bool(value) }
}

extension AnyCodable: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) { self = .int(value) }
}

extension AnyCodable: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) { self = .double(value) }
}

extension AnyCodable: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
}

extension AnyCodable: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: AnyCodable...) { self = .array(elements) }
}

extension AnyCodable: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, AnyCodable)...) {
        self = .object(Dictionary(uniqueKeysWithValues: elements))
    }
}

// MARK: - Accessors

extension AnyCodable {
    /// Returns the bool value if this is `.bool`, nil otherwise.
    public var boolValue: Bool? {
        guard case .bool(let v) = self else { return nil }
        return v
    }

    /// Returns the int value if this is `.int`, nil otherwise.
    public var intValue: Int? {
        guard case .int(let v) = self else { return nil }
        return v
    }

    /// Returns the double value if this is `.double` or `.int`, nil otherwise.
    public var doubleValue: Double? {
        switch self {
        case .double(let v): return v
        case .int(let v): return Double(v)
        default: return nil
        }
    }

    /// Returns the string value if this is `.string`, nil otherwise.
    public var stringValue: String? {
        guard case .string(let v) = self else { return nil }
        return v
    }

    /// Returns the array value if this is `.array`, nil otherwise.
    public var arrayValue: [AnyCodable]? {
        guard case .array(let v) = self else { return nil }
        return v
    }

    /// Returns the object value if this is `.object`, nil otherwise.
    public var objectValue: [String: AnyCodable]? {
        guard case .object(let v) = self else { return nil }
        return v
    }

    /// Returns true if this is `.null`.
    public var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    /// Subscript for object access.
    public subscript(key: String) -> AnyCodable? {
        guard case .object(let dict) = self else { return nil }
        return dict[key]
    }

    /// Subscript for array access.
    public subscript(index: Int) -> AnyCodable? {
        guard case .array(let arr) = self, arr.indices.contains(index) else { return nil }
        return arr[index]
    }
}
