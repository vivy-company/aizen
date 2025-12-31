//
//  MCPServer.swift
//  aizen
//
//  Data models for MCP Registry API responses
//

import Foundation

// MARK: - Server

nonisolated struct MCPServer: Codable, Identifiable, Sendable {
    let name: String
    let title: String?
    let description: String?
    let version: String?
    let websiteUrl: String?
    let icons: [MCPIcon]?
    let repository: MCPRepository?
    let packages: [MCPPackage]?
    let remotes: [MCPRemote]?

    var id: String { name }

    var displayTitle: String {
        title ?? displayName
    }

    var primaryIcon: MCPIcon? {
        icons?.first
    }

    var displayName: String {
        String(name.split(separator: "/").last ?? Substring(name))
    }

    var isRemoteOnly: Bool {
        (packages == nil || packages!.isEmpty) && (remotes != nil && !remotes!.isEmpty)
    }

    var primaryPackage: MCPPackage? {
        packages?.first
    }

    var primaryRemote: MCPRemote? {
        remotes?.first
    }
}

// MARK: - Icon

nonisolated struct MCPIcon: Codable, Identifiable, Sendable {
    let url: String?
    let src: String?  // Alternative field name used by some servers
    let type: String?
    let size: String?

    var id: String { iconUrl ?? UUID().uuidString }

    var iconUrl: String? {
        url ?? src
    }
}

// MARK: - Repository

nonisolated struct MCPRepository: Codable, Sendable {
    let url: String?
    let source: String?
}

// MARK: - Transport

nonisolated struct MCPTransport: Codable, Sendable {
    let type: String
}

// MARK: - Package

nonisolated struct MCPPackage: Codable, Identifiable, Sendable {
    let registryType: String
    let identifier: String
    let transport: MCPTransport?
    let runtime: String?
    let runtimeArguments: [String]?
    let packageArguments: [MCPArgument]?
    let environmentVariables: [MCPEnvVar]?

    var id: String { "\(registryType):\(identifier)" }

    var packageName: String {
        // Extract package name from identifier (e.g., "docker.io/aliengiraffe/spotdb:0.1.0" -> "aliengiraffe/spotdb")
        // or "@anthropic/mcp-server-github" -> "@anthropic/mcp-server-github"
        if identifier.contains(":") {
            let withoutVersion = identifier.components(separatedBy: ":").first ?? identifier
            if withoutVersion.hasPrefix("docker.io/") {
                return String(withoutVersion.dropFirst("docker.io/".count))
            }
            return withoutVersion
        }
        return identifier
    }

    var runtimeHint: String {
        switch registryType {
        case "npm": return runtime ?? "npx"
        case "pypi": return runtime ?? "uvx"
        case "oci": return runtime ?? "docker"
        default: return runtime ?? registryType
        }
    }

    var registryBadge: String {
        switch registryType {
        case "npm": return "npm"
        case "pypi": return "pip"
        case "oci": return "docker"
        default: return registryType
        }
    }

    var transportType: String {
        transport?.type ?? "stdio"
    }
}

// MARK: - Remote

nonisolated struct MCPRemote: Codable, Identifiable, Sendable {
    let type: String
    let url: String
    let headers: [MCPHeader]?
    let configSchema: MCPConfigSchema?

    var id: String { url }

    var transportBadge: String {
        switch type {
        case "http", "streamable-http": return "HTTP"
        case "sse": return "SSE"
        default: return type.uppercased()
        }
    }
}

// MARK: - Argument

nonisolated struct MCPArgument: Codable, Identifiable, Sendable {
    let name: String?
    let description: String?
    let isRequired: Bool?
    let value: String?
    let valueHint: String?
    let isRepeated: Bool?
    let `default`: String?

    var id: String { name ?? UUID().uuidString }

    var displayName: String {
        name ?? "arg"
    }

    var required: Bool {
        isRequired ?? false
    }
}

// MARK: - Environment Variable

nonisolated struct MCPEnvVar: Codable, Identifiable, Sendable {
    let name: String
    let description: String?
    let isRequired: Bool?
    let isSecret: Bool?
    let `default`: String?
    let format: String?

    var id: String { name }

    var required: Bool {
        isRequired ?? false
    }

    var secret: Bool {
        isSecret ?? false
    }
}

// MARK: - Header

nonisolated struct MCPHeader: Codable, Sendable {
    let name: String
    let value: String?
    let isRequired: Bool?
    let isSecret: Bool?
}

// MARK: - Config Schema

nonisolated struct MCPConfigSchema: Codable, Sendable {
    let type: String?
    let properties: [String: MCPConfigProperty]?
    let required: [String]?
}

nonisolated struct MCPConfigProperty: Codable, Sendable {
    let type: String?
    let description: String?
    let `default`: String?
}

// MARK: - Search Result

nonisolated struct MCPSearchResult: Codable, Sendable {
    let servers: [MCPServerWrapper]
    let metadata: MCPMetadata
}

nonisolated struct MCPServerWrapper: Codable, Sendable {
    let server: MCPServer
}

nonisolated struct MCPMetadata: Codable, Sendable {
    let nextCursor: String?
    let count: Int?

    /// Returns true if there are more results (nextCursor is present)
    var hasMore: Bool {
        nextCursor != nil
    }
}
