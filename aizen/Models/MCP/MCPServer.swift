//
//  MCPServer.swift
//  aizen
//
//  Data models for MCP Registry API responses
//

import Foundation

// MARK: - Server

struct MCPServer: Codable, Identifiable {
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

struct MCPIcon: Codable, Identifiable {
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

struct MCPRepository: Codable {
    let url: String?
    let source: String?
}

// MARK: - Transport

struct MCPTransport: Codable {
    let type: String
}

// MARK: - Package

struct MCPPackage: Codable, Identifiable {
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

struct MCPRemote: Codable, Identifiable {
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

struct MCPArgument: Codable, Identifiable {
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

struct MCPEnvVar: Codable, Identifiable {
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

struct MCPHeader: Codable {
    let name: String
    let value: String?
    let isRequired: Bool?
    let isSecret: Bool?
}

// MARK: - Config Schema

struct MCPConfigSchema: Codable {
    let type: String?
    let properties: [String: MCPConfigProperty]?
    let required: [String]?
}

struct MCPConfigProperty: Codable {
    let type: String?
    let description: String?
    let `default`: String?
}

// MARK: - Search Result

struct MCPSearchResult: Codable {
    let servers: [MCPServerWrapper]
    let metadata: MCPMetadata
}

struct MCPServerWrapper: Codable {
    let server: MCPServer
}

struct MCPMetadata: Codable {
    let nextCursor: String?
    let count: Int?

    /// Returns true if there are more results (nextCursor is present)
    var hasMore: Bool {
        nextCursor != nil
    }
}
