//
//  ACPTerminalTypes.swift
//  aizen
//
//  Agent Client Protocol - Terminal Types
//

import Foundation

// MARK: - Terminal Types

nonisolated struct TerminalId: Codable, Hashable {
    let value: String

    init(_ value: String) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        value = try container.decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

// MARK: - Environment Variable

nonisolated struct EnvVariable: Codable {
    let name: String
    let value: String
    let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case name, value, _meta
    }
}

// MARK: - Terminal Exit Status

nonisolated struct TerminalExitStatus: Codable {
    let exitCode: Int?
    let signal: String?
    let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case exitCode
        case signal
        case _meta
    }
}

// MARK: - Create Terminal

nonisolated struct CreateTerminalRequest: Codable {
    let command: String
    let args: [String]?
    let cwd: String?
    let env: [EnvVariable]?
    let outputByteLimit: Int?
    let sessionId: String
    let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case command, args, cwd, env, sessionId
        case outputByteLimit = "outputByteLimit"
        case _meta
    }
}

nonisolated struct CreateTerminalResponse: Codable {
    let terminalId: TerminalId
    let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case terminalId
        case _meta
    }
}

// MARK: - Terminal Output

nonisolated struct TerminalOutputRequest: Codable {
    let terminalId: TerminalId
    let sessionId: String
    let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case terminalId
        case sessionId
        case _meta
    }
}

nonisolated struct TerminalOutputResponse: Codable {
    let output: String
    let exitStatus: TerminalExitStatus?
    let truncated: Bool
    let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case output, truncated, exitStatus
        case _meta
    }
}

// MARK: - Wait for Exit

nonisolated struct WaitForExitRequest: Codable {
    let terminalId: TerminalId
    let sessionId: String
    let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case terminalId
        case sessionId
        case _meta
    }
}

nonisolated struct WaitForExitResponse: Codable {
    let exitCode: Int?
    let signal: String?
    let _meta: [String: AnyCodable]?
}

// MARK: - Kill Terminal

nonisolated struct KillTerminalRequest: Codable {
    let terminalId: TerminalId
    let sessionId: String
    let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case terminalId
        case sessionId
        case _meta
    }
}

nonisolated struct KillTerminalResponse: Codable {
    let success: Bool
    let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case success, _meta
    }
}

// MARK: - Release Terminal

nonisolated struct ReleaseTerminalRequest: Codable {
    let terminalId: TerminalId
    let sessionId: String
    let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case terminalId
        case sessionId
        case _meta
    }
}

nonisolated struct ReleaseTerminalResponse: Codable {
    let success: Bool
    let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case success, _meta
    }
}
