//
//  ACPPermissionTypes.swift
//  aizen
//
//  Agent Client Protocol - Permission Types
//

import Foundation

// MARK: - Permission Request

nonisolated struct RequestPermissionRequest: Codable {
    let message: String?
    let options: [PermissionOption]?
    let sessionId: SessionId?
    let toolCall: PermissionToolCall?

    enum CodingKeys: String, CodingKey {
        case message
        case options
        case sessionId
        case toolCall
    }
}

nonisolated struct PermissionOption: Codable {
    let kind: String
    let name: String
    let optionId: String

    enum CodingKeys: String, CodingKey {
        case kind
        case name
        case optionId
    }
}

nonisolated struct PermissionToolCall: Codable {
    let toolCallId: String
    let rawInput: AnyCodable?

    enum CodingKeys: String, CodingKey {
        case toolCallId
        case rawInput
    }
}

// MARK: - Permission Decision

nonisolated enum PermissionDecision: String, Codable {
    case allowOnce = "allow_once"
    case allowAlways = "allow_always"
    case rejectOnce = "reject_once"
    case rejectAlways = "reject_always"
}

// MARK: - Permission Response

nonisolated struct RequestPermissionResponse: Codable {
    let outcome: PermissionOutcome

    enum CodingKeys: String, CodingKey {
        case outcome
    }
}

nonisolated struct PermissionOutcome: Codable {
    let outcome: String // "selected" or "cancelled"
    let optionId: String?

    enum CodingKeys: String, CodingKey {
        case outcome
        case optionId
    }

    init(optionId: String) {
        self.outcome = "selected"
        self.optionId = optionId
    }

    init(cancelled: Bool) {
        self.outcome = "cancelled"
        self.optionId = nil
    }
}
