import Foundation

/// A control response to send back to the CLI process.
struct SDKControlResponse: Codable, Sendable {
    let type: String
    let response: ControlResponsePayload

    init(requestId: String, response: [String: AnyCodable]? = nil) {
        self.type = "control_response"
        self.response = ControlResponsePayload(
            subtype: "success",
            requestId: requestId,
            response: response,
            error: nil
        )
    }

    init(requestId: String, error: String) {
        self.type = "control_response"
        self.response = ControlResponsePayload(
            subtype: "error",
            requestId: requestId,
            response: nil,
            error: error
        )
    }
}

struct ControlResponsePayload: Codable, Sendable {
    let subtype: String
    let requestId: String
    let response: [String: AnyCodable]?
    let error: String?
}

/// A control request to send to the CLI (for interrupt, set_model, etc.)
struct SDKControlOutboundRequest: Codable, Sendable {
    let type: String
    let requestId: String
    let request: OutboundRequestPayload

    init(requestId: String, subtype: String, fields: [String: AnyCodable] = [:]) {
        self.type = "control_request"
        self.requestId = requestId
        self.request = OutboundRequestPayload(subtype: subtype, fields: fields)
    }
}

struct OutboundRequestPayload: Codable, Sendable {
    let subtype: String
    let fields: [String: AnyCodable]

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKeys.self)
        try container.encode(subtype, forKey: DynamicCodingKeys(stringValue: "subtype")!)
        for (key, value) in fields {
            try container.encode(value, forKey: DynamicCodingKeys(stringValue: key)!)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKeys.self)
        subtype = try container.decode(String.self, forKey: DynamicCodingKeys(stringValue: "subtype")!)
        var fields: [String: AnyCodable] = [:]
        for key in container.allKeys where key.stringValue != "subtype" {
            fields[key.stringValue] = try container.decode(AnyCodable.self, forKey: key)
        }
        self.fields = fields
    }

    init(subtype: String, fields: [String: AnyCodable]) {
        self.subtype = subtype
        self.fields = fields
    }
}

private struct DynamicCodingKeys: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}
