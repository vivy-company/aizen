//
//  AgentMetadata.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import Foundation

/// Metadata for an agent configuration
nonisolated struct AgentMetadata: Codable, Identifiable, Sendable {
    let id: String
    var name: String
    var description: String?
    var iconType: AgentIconType
    var isBuiltIn: Bool
    var isEnabled: Bool
    var executablePath: String?
    var launchArgs: [String]
    var installMethod: AgentInstallMethod?
    var environmentVariables: [AgentEnvironmentVariable]

    /// Whether the user can edit the executable path (custom agents only)
    var canEditPath: Bool {
        !isBuiltIn
    }

    init(
        id: String,
        name: String,
        description: String? = nil,
        iconType: AgentIconType,
        isBuiltIn: Bool,
        isEnabled: Bool = true,
        executablePath: String? = nil,
        launchArgs: [String] = [],
        installMethod: AgentInstallMethod? = nil,
        environmentVariables: [AgentEnvironmentVariable] = []
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.iconType = iconType
        self.isBuiltIn = isBuiltIn
        self.isEnabled = isEnabled
        self.executablePath = executablePath
        self.launchArgs = launchArgs
        self.installMethod = installMethod
        self.environmentVariables = environmentVariables
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case iconType
        case isBuiltIn
        case isEnabled
        case executablePath
        case launchArgs
        case installMethod
        case environmentVariables
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        iconType = try container.decode(AgentIconType.self, forKey: .iconType)
        isBuiltIn = try container.decode(Bool.self, forKey: .isBuiltIn)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        executablePath = try container.decodeIfPresent(String.self, forKey: .executablePath)
        launchArgs = try container.decodeIfPresent([String].self, forKey: .launchArgs) ?? []
        installMethod = try container.decodeIfPresent(AgentInstallMethod.self, forKey: .installMethod)
        environmentVariables =
            try container.decodeIfPresent([AgentEnvironmentVariable].self, forKey: .environmentVariables) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encode(iconType, forKey: .iconType)
        try container.encode(isBuiltIn, forKey: .isBuiltIn)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encodeIfPresent(executablePath, forKey: .executablePath)
        try container.encode(launchArgs, forKey: .launchArgs)
        try container.encodeIfPresent(installMethod, forKey: .installMethod)
        try container.encode(environmentVariables, forKey: .environmentVariables)
    }
}
