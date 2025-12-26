//
//  ACPMessageTypes.swift
//  aizen
//
//  Agent Client Protocol - JSON-RPC Message Types
//

import Foundation

// MARK: - JSON-RPC Message Types

enum ACPMessage: Codable {
    case request(JSONRPCRequest)
    case response(JSONRPCResponse)
    case notification(JSONRPCNotification)

    enum CodingKeys: String, CodingKey {
        case jsonrpc, method, id
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let hasMethod = container.contains(.method)
        let hasId = container.contains(.id)

        if hasMethod && hasId {
            self = .request(try JSONRPCRequest(from: decoder))
        } else if hasMethod {
            self = .notification(try JSONRPCNotification(from: decoder))
        } else {
            self = .response(try JSONRPCResponse(from: decoder))
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .request(let req):
            try req.encode(to: encoder)
        case .response(let res):
            try res.encode(to: encoder)
        case .notification(let notif):
            try notif.encode(to: encoder)
        }
    }
}

struct JSONRPCRequest: Codable {
    let jsonrpc: String = "2.0"
    let id: RequestId
    let method: String
    let params: AnyCodable?

    enum CodingKeys: String, CodingKey {
        case jsonrpc, id, method, params
    }
}

struct JSONRPCResponse: Codable {
    let jsonrpc: String = "2.0"
    let id: RequestId
    let result: AnyCodable?
    let error: JSONRPCError?

    enum CodingKeys: String, CodingKey {
        case jsonrpc, id, result, error
    }
}

struct JSONRPCNotification: Codable {
    let jsonrpc: String = "2.0"
    let method: String
    let params: AnyCodable?

    enum CodingKeys: String, CodingKey {
        case jsonrpc, method, params
    }
}

struct JSONRPCError: Codable {
    let code: Int
    let message: String
    let data: AnyCodable?
}

enum RequestId: Codable, Hashable, CustomStringConvertible {
    case string(String)
    case number(Int)

    var description: String {
        switch self {
        case .string(let str): return str
        case .number(let num): return String(num)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) {
            self = .string(str)
        } else if let num = try? container.decode(Int.self) {
            self = .number(num)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid RequestId")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let str):
            try container.encode(str)
        case .number(let num):
            try container.encode(num)
        }
    }
}

// MARK: - AnyCodable Helper

struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
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
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        case is NSNull:
            try container.encodeNil()
        default:
            try container.encodeNil()
        }
    }
}
