import Foundation

// MARK: - JSON-RPC 2.0 Protocol Types

/// A JSON-RPC 2.0 request identifier — may be a string or integer per spec.
enum JsonRpcId: Sendable, Hashable {
    case string(String)
    case int(Int)
}

extension JsonRpcId: Codable {
    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intVal = try? container.decode(Int.self) {
            self = .int(intVal)
        } else {
            self = .string(try container.decode(String.self))
        }
    }

    nonisolated func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .int(let i): try container.encode(i)
        }
    }
}

/// Type-erased JSON value for dynamic params/result fields.
enum AnyCodable: Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([AnyCodable])
    case object([String: AnyCodable])
}

extension AnyCodable: Codable {
    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let i = try? container.decode(Int.self) {
            self = .int(i)
        } else if let d = try? container.decode(Double.self) {
            self = .double(d)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let arr = try? container.decode([AnyCodable].self) {
            self = .array(arr)
        } else if let obj = try? container.decode([String: AnyCodable].self) {
            self = .object(obj)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    nonisolated func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let b): try container.encode(b)
        case .int(let i): try container.encode(i)
        case .double(let d): try container.encode(d)
        case .string(let s): try container.encode(s)
        case .array(let a): try container.encode(a)
        case .object(let o): try container.encode(o)
        }
    }
}

extension AnyCodable {
    var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }
    var intValue: Int? {
        if case .int(let i) = self { return i }
        return nil
    }
    var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }
    var arrayValue: [AnyCodable]? {
        if case .array(let a) = self { return a }
        return nil
    }
    var objectValue: [String: AnyCodable]? {
        if case .object(let o) = self { return o }
        return nil
    }
}

// MARK: - Messages

struct JsonRpcRequest: Codable, Sendable {
    let jsonrpc: String
    let id: JsonRpcId
    let method: String
    let params: [String: AnyCodable]?

    init(id: JsonRpcId, method: String, params: [String: AnyCodable]? = nil) {
        self.jsonrpc = "2.0"
        self.id = id
        self.method = method
        self.params = params
    }
}

struct JsonRpcResponse: Codable, Sendable {
    let jsonrpc: String
    let id: JsonRpcId?
    let result: AnyCodable?
    let error: JsonRpcError?

    static func success(id: JsonRpcId, result: AnyCodable) -> JsonRpcResponse {
        JsonRpcResponse(jsonrpc: "2.0", id: id, result: result, error: nil)
    }

    static func error(id: JsonRpcId?, error: JsonRpcError) -> JsonRpcResponse {
        JsonRpcResponse(jsonrpc: "2.0", id: id, result: nil, error: error)
    }
}

struct JsonRpcNotification: Codable, Sendable {
    let jsonrpc: String
    let method: String
    let params: [String: AnyCodable]?

    init(method: String, params: [String: AnyCodable]? = nil) {
        self.jsonrpc = "2.0"
        self.method = method
        self.params = params
    }
}

struct JsonRpcError: Codable, Sendable {
    let code: Int
    let message: String
    let data: AnyCodable?

    init(code: Int, message: String, data: AnyCodable? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }
}

// MARK: - Standard Error Codes

enum JsonRpcErrorCode {
    static let parseError = -32700
    static let invalidRequest = -32600
    static let methodNotFound = -32601
    static let invalidParams = -32602
    static let internalError = -32603
    static let permissionDenied = -32000
    static let rateLimited = -32001
    static let sandboxError = -32002
}

// MARK: - Decoded Message Envelope

enum JsonRpcMessage: Sendable {
    case request(JsonRpcRequest)
    case response(JsonRpcResponse)
    case notification(JsonRpcNotification)
}

// MARK: - Codec

enum JsonRpcCodec {
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }()
    private static let decoder = JSONDecoder()

    /// Encode any JSON-RPC message to a single line of JSON (no trailing newline).
    nonisolated static func encode(_ message: JsonRpcMessage) throws -> Data {
        switch message {
        case .request(let r): return try encoder.encode(r)
        case .response(let r): return try encoder.encode(r)
        case .notification(let n): return try encoder.encode(n)
        }
    }

    nonisolated static func encodeRequest(_ request: JsonRpcRequest) throws -> Data {
        try encoder.encode(request)
    }

    nonisolated static func encodeResponse(_ response: JsonRpcResponse) throws -> Data {
        try encoder.encode(response)
    }

    nonisolated static func encodeNotification(_ notification: JsonRpcNotification) throws -> Data {
        try encoder.encode(notification)
    }

    /// Decode a line of JSON into a `JsonRpcMessage`.
    nonisolated static func decode(_ data: Data) throws -> JsonRpcMessage {
        // Peek at the JSON to determine message type
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw JsonRpcDecodeError.invalidJson
        }

        if obj["method"] != nil {
            // Has "method" — either request or notification
            if obj["id"] != nil {
                return .request(try decoder.decode(JsonRpcRequest.self, from: data))
            } else {
                return .notification(try decoder.decode(JsonRpcNotification.self, from: data))
            }
        } else {
            // No "method" — must be a response
            return .response(try decoder.decode(JsonRpcResponse.self, from: data))
        }
    }
}

enum JsonRpcDecodeError: Error, Sendable {
    case invalidJson
    case unknownMessageType
}
