//
//  AgentEnvironmentVariable.swift
//  aizen
//
//  Persisted per-agent environment variable overrides.
//

import Foundation

nonisolated struct AgentEnvironmentVariable: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    var value: String
    var isSecret: Bool

    init(id: UUID = UUID(), name: String = "", value: String = "", isSecret: Bool = false) {
        self.id = id
        self.name = name
        self.value = value
        self.isSecret = isSecret
    }

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isBlankRow: Bool {
        trimmedName.isEmpty && value.isEmpty
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case value
        case isSecret
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        value = try container.decodeIfPresent(String.self, forKey: .value) ?? ""
        isSecret = try container.decodeIfPresent(Bool.self, forKey: .isSecret) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(value, forKey: .value)
        try container.encode(isSecret, forKey: .isSecret)
    }
}

nonisolated extension Array where Element == AgentEnvironmentVariable {
    var launchEnvironment: [String: String] {
        reduce(into: [:]) { environment, variable in
            let name = variable.trimmedName
            guard !name.isEmpty else { return }
            environment[name] = variable.value
        }
    }

    var persistedVariables: [AgentEnvironmentVariable] {
        filter { !$0.isBlankRow }
    }

    var duplicateNames: [String] {
        var counts: [String: Int] = [:]
        for variable in self {
            let name = variable.trimmedName
            guard !name.isEmpty else { continue }
            counts[name, default: 0] += 1
        }

        return counts
            .filter { $0.value > 1 }
            .map(\.key)
            .sorted()
    }

    var ignoredValueCount: Int {
        filter { $0.trimmedName.isEmpty && !$0.value.isEmpty }.count
    }
}
