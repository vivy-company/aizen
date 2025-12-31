//
//  ACPContentTypes.swift
//  aizen
//
//  Agent Client Protocol - Content Block Types
//

import Foundation

// MARK: - Annotations

nonisolated struct Annotations: Codable {
    let audience: [String]?  // Array of Role strings
    let lastModified: String?  // ISO 8601 datetime
    let priority: Int?
    let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case audience
        case lastModified
        case priority, _meta
    }
}

// MARK: - Content Types

nonisolated enum ContentBlock: Codable {
    case text(TextContent)
    case image(ImageContent)
    case audio(AudioContent)
    case resourceLink(ResourceLinkContent)
    case resource(ResourceContent)

    enum CodingKeys: String, CodingKey {
        case type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "text":
            self = .text(try TextContent(from: decoder))
        case "image":
            self = .image(try ImageContent(from: decoder))
        case "audio":
            self = .audio(try AudioContent(from: decoder))
        case "resource_link":
            self = .resourceLink(try ResourceLinkContent(from: decoder))
        case "resource":
            self = .resource(try ResourceContent(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown content type: \(type)")
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .text(let content):
            try content.encode(to: encoder)
        case .image(let content):
            try content.encode(to: encoder)
        case .audio(let content):
            try content.encode(to: encoder)
        case .resourceLink(let content):
            try content.encode(to: encoder)
        case .resource(let content):
            try content.encode(to: encoder)
        }
    }
}

// MARK: - Text Content

nonisolated struct TextContent: Codable {
    let type: String = "text"
    let text: String
    let annotations: Annotations?
    let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case type, text, annotations, _meta
    }

    init(text: String, annotations: Annotations? = nil, _meta: [String: AnyCodable]? = nil) {
        self.text = text
        self.annotations = annotations
        self._meta = _meta
    }
}

// MARK: - Image Content

nonisolated struct ImageContent: Codable {
    let type: String = "image"
    let data: String
    let mimeType: String
    let uri: String?
    let annotations: Annotations?
    let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case type, data, uri, mimeType, annotations, _meta
    }

    init(data: String, mimeType: String, uri: String? = nil, annotations: Annotations? = nil, _meta: [String: AnyCodable]? = nil) {
        self.data = data
        self.mimeType = mimeType
        self.uri = uri
        self.annotations = annotations
        self._meta = _meta
    }
}

// MARK: - Audio Content

nonisolated struct AudioContent: Codable {
    let type: String = "audio"
    let data: String
    let mimeType: String
    let annotations: Annotations?
    let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case type, data, mimeType, annotations, _meta
    }
}

// MARK: - Resource Link Content

nonisolated struct ResourceLinkContent: Codable {
    let type: String = "resource_link"
    let uri: String
    let name: String
    let title: String?
    let description: String?
    let mimeType: String?
    let size: Int?
    let annotations: Annotations?
    let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case type, uri, name, title, description, mimeType, size, annotations, _meta
    }
}

// MARK: - Embedded Resource Types

nonisolated enum EmbeddedResourceType: Codable {
    case text(EmbeddedTextResourceContents)
    case blob(EmbeddedBlobResourceContents)

    enum CodingKeys: String, CodingKey {
        case type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "text":
            self = .text(try EmbeddedTextResourceContents(from: decoder))
        case "blob":
            self = .blob(try EmbeddedBlobResourceContents(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown resource type: \(type)")
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .text(let content):
            try content.encode(to: encoder)
        case .blob(let content):
            try content.encode(to: encoder)
        }
    }
}

nonisolated struct EmbeddedTextResourceContents: Codable {
    let type: String = "text"
    let text: String
    let mimeType: String?
    let uri: String
    let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case type, text, mimeType, uri, _meta
    }
}

nonisolated struct EmbeddedBlobResourceContents: Codable {
    let type: String = "blob"
    let blob: String
    let mimeType: String?
    let uri: String
    let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case type, blob, mimeType, uri, _meta
    }
}

// MARK: - Resource Content

nonisolated struct ResourceContent: Codable {
    let type: String = "resource"
    let resource: EmbeddedResourceType
    let annotations: Annotations?
    let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case type, resource, annotations, _meta
    }
}

extension EmbeddedResourceType {
    /// Convenience accessor for the resource URI regardless of variant
    var uri: String? {
        switch self {
        case .text(let contents): return contents.uri
        case .blob(let contents): return contents.uri
        }
    }

    /// Convenience accessor for the resource mime type regardless of variant
    var mimeType: String? {
        switch self {
        case .text(let contents): return contents.mimeType
        case .blob(let contents): return contents.mimeType
        }
    }

    /// Convenience accessor for embedded text contents
    var text: String? {
        switch self {
        case .text(let contents): return contents.text
        case .blob: return nil
        }
    }
}
