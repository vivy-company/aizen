//
//  ACPConfigOptions.swift
//  aizen
//
//  Agent Client Protocol - Config Options Types (newer API that replaces modes/models)
//

import Foundation

// MARK: - Session Config Option

nonisolated struct SessionConfigOption: Codable {
    let id: SessionConfigId
    let name: String
    let kind: SessionConfigKind

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case kind
    }
}

// MARK: - Session Config ID & Value ID

nonisolated struct SessionConfigId: Codable, Hashable {
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

nonisolated struct SessionConfigValueId: Codable, Hashable {
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

// MARK: - Session Config Kind

nonisolated enum SessionConfigKind: Codable {
    case select(SessionConfigSelect)
    // Future: can add toggle, slider, etc.

    enum CodingKeys: String, CodingKey {
        case type
        case currentValue
        case options
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "select":
            let select = SessionConfigSelect(
                currentValue: try container.decode(SessionConfigValueId.self, forKey: .currentValue),
                options: try container.decode(SessionConfigSelectOptions.self, forKey: .options)
            )
            self = .select(select)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unsupported config kind: \(type)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .select(let select):
            try container.encode("select", forKey: .type)
            try container.encode(select.currentValue, forKey: .currentValue)
            try container.encode(select.options, forKey: .options)
        }
    }
}

// MARK: - Session Config Select

nonisolated struct SessionConfigSelect: Codable {
    var currentValue: SessionConfigValueId
    let options: SessionConfigSelectOptions

    enum CodingKeys: String, CodingKey {
        case currentValue
        case options
    }
}

// MARK: - Session Config Select Options

nonisolated enum SessionConfigSelectOptions: Codable {
    case ungrouped([SessionConfigSelectOption])
    case grouped([SessionConfigSelectGroup])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        // Try to decode as array of options first
        if let options = try? container.decode([SessionConfigSelectOption].self) {
            self = .ungrouped(options)
        } else if let groups = try? container.decode([SessionConfigSelectGroup].self) {
            self = .grouped(groups)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid session config select options"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .ungrouped(let options):
            try container.encode(options)
        case .grouped(let groups):
            try container.encode(groups)
        }
    }
}

// MARK: - Session Config Select Option

nonisolated struct SessionConfigSelectOption: Codable {
    let value: SessionConfigValueId
    let label: String

    enum CodingKeys: String, CodingKey {
        case value
        case label
    }
}

// MARK: - Session Config Select Group

nonisolated struct SessionConfigSelectGroup: Codable {
    let label: String
    let options: [SessionConfigSelectOption]

    enum CodingKeys: String, CodingKey {
        case label
        case options
    }
}
