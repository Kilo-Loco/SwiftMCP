//
//  JSONRPCTypes.swift
//  SwiftMCP
//
//  JSON-RPC 2.0 Protocol Types
//

import Foundation

// MARK: - JSON-RPC Base Protocol

public struct JSONRPCRequest: Codable, Sendable {
    public let jsonrpc: String = "2.0"
    public let id: JSONRPCId
    public let method: String
    public let params: AnyCodable?
    
    public init(id: JSONRPCId, method: String, params: AnyCodable? = nil) {
        self.id = id
        self.method = method
        self.params = params
    }
}

public struct JSONRPCResponse: Codable, Sendable {
    public let jsonrpc: String = "2.0"
    public let id: JSONRPCId
    public let result: AnyCodable?
    public let error: JSONRPCError?
    
    public init(id: JSONRPCId, result: AnyCodable) {
        self.id = id
        self.result = result
        self.error = nil
    }
    
    public init(id: JSONRPCId, error: JSONRPCError) {
        self.id = id
        self.result = nil
        self.error = error
    }
}

public struct JSONRPCNotification: Codable, Sendable {
    public let jsonrpc: String = "2.0"
    public let method: String
    public let params: AnyCodable?
    
    public init(method: String, params: AnyCodable? = nil) {
        self.method = method
        self.params = params
    }
}

// MARK: - JSON-RPC Types

public enum JSONRPCId: Codable, Equatable, Sendable {
    case string(String)
    case number(Int)
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            self = .number(intValue)
        } else if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else {
            throw DecodingError.typeMismatch(
                JSONRPCId.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected String or Int"
                )
            )
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        }
    }
}

public struct JSONRPCError: Codable, Error, LocalizedError, Sendable {
    public let code: Int
    public let message: String
    public let data: AnyCodable?
    
    public init(code: Int, message: String, data: AnyCodable? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }
    
    public var errorDescription: String? {
        "JSON-RPC Error \(code): \(message)"
    }
    
    public static func parseError(data: AnyCodable? = nil) -> JSONRPCError {
        JSONRPCError(code: -32700, message: "Parse error", data: data)
    }
    
    public static func invalidRequest(data: AnyCodable? = nil) -> JSONRPCError {
        JSONRPCError(code: -32600, message: "Invalid request", data: data)
    }
    
    public static func methodNotFound(method: String, data: AnyCodable? = nil) -> JSONRPCError {
        JSONRPCError(code: -32601, message: "Method not found: \(method)", data: data)
    }
    
    public static func invalidParams(data: AnyCodable? = nil) -> JSONRPCError {
        JSONRPCError(code: -32602, message: "Invalid params", data: data)
    }
    
    public static func internalError(data: AnyCodable? = nil) -> JSONRPCError {
        JSONRPCError(code: -32603, message: "Internal error", data: data)
    }
}

// MARK: - AnyCodable for Dynamic JSON

public struct AnyCodable: Codable, @unchecked Sendable {
    public let value: Any
    
    public init(_ value: Any) {
        self.value = value
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if container.decodeNil() {
            self.value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            self.value = bool
        } else if let int = try? container.decode(Int.self) {
            self.value = int
        } else if let double = try? container.decode(Double.self) {
            self.value = double
        } else if let string = try? container.decode(String.self) {
            self.value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            self.value = array.map { $0.value }
        } else if let dictionary = try? container.decode([String: AnyCodable].self) {
            self.value = dictionary.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode value"
            )
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dictionary as [String: Any]:
            try container.encode(dictionary.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(
                    codingPath: encoder.codingPath,
                    debugDescription: "Cannot encode value"
                )
            )
        }
    }
}