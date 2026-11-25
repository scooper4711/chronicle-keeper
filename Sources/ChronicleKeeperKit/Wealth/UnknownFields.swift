import Foundation

/// Any JSON value, kept as it was read.
public indirect enum JSONValue: Hashable, Codable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() {
            self = .null
        } else if let bool = try? value.decode(Bool.self) {
            self = .bool(bool)
        } else if let number = try? value.decode(Double.self) {
            self = .number(number)
        } else if let string = try? value.decode(String.self) {
            self = .string(string)
        } else if let array = try? value.decode([JSONValue].self) {
            self = .array(array)
        } else {
            self = .object(try value.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let bool): try container.encode(bool)
        case .number(let number): try container.encode(number)
        case .string(let string): try container.encode(string)
        case .array(let array): try container.encode(array)
        case .object(let object): try container.encode(object)
        }
    }
}

/// The fields of a saved object that this version doesn't know, kept so that saving it again doesn't erase what a
/// newer version added (design.md, "The ledger's storage"). The ledger syncs, so a field dropped here would be
/// dropped on every device.
public struct UnknownFields: Hashable, Sendable {
    public private(set) var values: [String: JSONValue] = [:]

    public init() {}

    /// Reads every field of the object whose name isn't in `known`.
    public init(from decoder: Decoder, known: Set<String>) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        for key in container.allKeys where !known.contains(key.stringValue) {
            values[key.stringValue] = try container.decode(JSONValue.self, forKey: key)
        }
    }

    /// Writes the kept fields back beside the known ones.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: AnyKey.self)
        for (name, value) in values {
            try container.encode(value, forKey: AnyKey(stringValue: name))
        }
    }

    private struct AnyKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }

        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }
}
