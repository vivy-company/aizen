//
//  AgentInstallMethod.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import Foundation

/// Installation method for agents
enum AgentInstallMethod: Codable, Equatable {
    case npm(package: String)
    case uv(package: String)
    case binary(url: String)
    case githubRelease(repo: String, assetPattern: String)
    case script(url: String)

    enum CodingKeys: String, CodingKey {
        case type, package, url, repo, assetPattern
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "npm":
            let package = try container.decode(String.self, forKey: .package)
            self = .npm(package: package)
        case "uv":
            let package = try container.decode(String.self, forKey: .package)
            self = .uv(package: package)
        case "binary":
            let url = try container.decode(String.self, forKey: .url)
            self = .binary(url: url)
        case "githubRelease":
            let repo = try container.decode(String.self, forKey: .repo)
            let assetPattern = try container.decode(String.self, forKey: .assetPattern)
            self = .githubRelease(repo: repo, assetPattern: assetPattern)
        case "script":
            let url = try container.decode(String.self, forKey: .url)
            self = .script(url: url)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown install method")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .npm(let package):
            try container.encode("npm", forKey: .type)
            try container.encode(package, forKey: .package)
        case .uv(let package):
            try container.encode("uv", forKey: .type)
            try container.encode(package, forKey: .package)
        case .binary(let url):
            try container.encode("binary", forKey: .type)
            try container.encode(url, forKey: .url)
        case .githubRelease(let repo, let assetPattern):
            try container.encode("githubRelease", forKey: .type)
            try container.encode(repo, forKey: .repo)
            try container.encode(assetPattern, forKey: .assetPattern)
        case .script(let url):
            try container.encode("script", forKey: .type)
            try container.encode(url, forKey: .url)
        }
    }
}
