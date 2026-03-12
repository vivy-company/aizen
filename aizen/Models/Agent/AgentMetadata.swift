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
    var source: AgentSource
    var isEnabled: Bool
    var executablePath: String?
    var command: String?
    var launchArgs: [String]
    var baseEnvironment: [String: String]
    var registryVersion: String?
    var registryRepositoryURL: String?
    var registryIconURL: String?
    var registryDistributionType: RegistryDistributionType?
    var environmentVariables: [AgentEnvironmentVariable]

    var isCustom: Bool {
        source == .custom
    }

    var isRegistry: Bool {
        source == .registry
    }

    var canEditPath: Bool {
        source == .custom
    }

    var requiresInstall: Bool {
        source == .registry && registryDistributionType == .binary
    }

    init(
        id: String,
        name: String,
        description: String? = nil,
        iconType: AgentIconType,
        source: AgentSource,
        isEnabled: Bool = true,
        executablePath: String? = nil,
        command: String? = nil,
        launchArgs: [String] = [],
        baseEnvironment: [String: String] = [:],
        registryVersion: String? = nil,
        registryRepositoryURL: String? = nil,
        registryIconURL: String? = nil,
        registryDistributionType: RegistryDistributionType? = nil,
        environmentVariables: [AgentEnvironmentVariable] = []
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.iconType = iconType
        self.source = source
        self.isEnabled = isEnabled
        self.executablePath = executablePath
        self.command = command
        self.launchArgs = launchArgs
        self.baseEnvironment = baseEnvironment
        self.registryVersion = registryVersion
        self.registryRepositoryURL = registryRepositoryURL
        self.registryIconURL = registryIconURL
        self.registryDistributionType = registryDistributionType
        self.environmentVariables = environmentVariables
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case iconType
        case source
        case isEnabled
        case executablePath
        case command
        case launchArgs
        case baseEnvironment
        case registryVersion
        case registryRepositoryURL
        case registryIconURL
        case registryDistributionType
        case environmentVariables
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        iconType = try container.decode(AgentIconType.self, forKey: .iconType)
        source = try container.decode(AgentSource.self, forKey: .source)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        executablePath = try container.decodeIfPresent(String.self, forKey: .executablePath)
        command = try container.decodeIfPresent(String.self, forKey: .command)
        launchArgs = try container.decodeIfPresent([String].self, forKey: .launchArgs) ?? []
        baseEnvironment = try container.decodeIfPresent([String: String].self, forKey: .baseEnvironment) ?? [:]
        registryVersion = try container.decodeIfPresent(String.self, forKey: .registryVersion)
        registryRepositoryURL = try container.decodeIfPresent(String.self, forKey: .registryRepositoryURL)
        registryIconURL = try container.decodeIfPresent(String.self, forKey: .registryIconURL)
        registryDistributionType = try container.decodeIfPresent(RegistryDistributionType.self, forKey: .registryDistributionType)
        environmentVariables =
            try container.decodeIfPresent([AgentEnvironmentVariable].self, forKey: .environmentVariables) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encode(iconType, forKey: .iconType)
        try container.encode(source, forKey: .source)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encodeIfPresent(executablePath, forKey: .executablePath)
        try container.encodeIfPresent(command, forKey: .command)
        try container.encode(launchArgs, forKey: .launchArgs)
        try container.encode(baseEnvironment, forKey: .baseEnvironment)
        try container.encodeIfPresent(registryVersion, forKey: .registryVersion)
        try container.encodeIfPresent(registryRepositoryURL, forKey: .registryRepositoryURL)
        try container.encodeIfPresent(registryIconURL, forKey: .registryIconURL)
        try container.encodeIfPresent(registryDistributionType, forKey: .registryDistributionType)
        try container.encode(environmentVariables, forKey: .environmentVariables)
    }
}
