//
//  ChatAgentSessionMessaging+Attachments.swift
//  aizen
//

import ACP
import CoreData
import Foundation
import UniformTypeIdentifiers

@MainActor
extension ChatAgentSession {
    /// Create an image content block from a file URL.
    func createImageBlock(from url: URL) async throws -> ContentBlock {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let maxFileSize = 10 * 1024 * 1024
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: url.path)
        if let fileSize = fileAttributes[.size] as? Int64, fileSize > maxFileSize {
            throw AgentSessionError.custom(
                "Image too large: \(url.lastPathComponent) (\(fileSize / 1024 / 1024)MB). Maximum size is 10MB."
            )
        }

        let mimeType = getMimeType(for: url) ?? "image/png"
        let data = try await readDataFileAsync(url: url)
        let encodedImageData = try await encodeBase64Async(data)

        let imageContent = ImageContent(
            data: encodedImageData,
            mimeType: mimeType,
            uri: url.absoluteString
        )
        return .image(imageContent)
    }

    /// Create a resource content block from a file URL.
    func createResourceBlock(from url: URL) async throws -> ContentBlock {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let maxFileSize = 10 * 1024 * 1024
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: url.path)
        if let fileSize = fileAttributes[.size] as? Int64, fileSize > maxFileSize {
            throw AgentSessionError.custom(
                "File too large: \(url.lastPathComponent) (\(fileSize / 1024 / 1024)MB). Maximum size is 10MB."
            )
        }

        let mimeType = getMimeType(for: url)
        let isTextFile =
            mimeType?.hasPrefix("text/") ?? false || mimeType == "application/json"
            || mimeType == "application/xml" || mimeType == "application/javascript"

        if isTextFile {
            let text = try await readTextFileAsync(url: url)
            let textResource = EmbeddedTextResourceContents(
                text: text,
                uri: url.absoluteString,
                mimeType: mimeType,
                _meta: nil
            )
            let resourceContent = ResourceContent(
                resource: .text(textResource),
                annotations: nil,
                _meta: nil
            )
            return .resource(resourceContent)
        } else {
            let data = try await readDataFileAsync(url: url)
            let base64 = try await encodeBase64Async(data)
            let blobResource = EmbeddedBlobResourceContents(
                blob: base64,
                uri: url.absoluteString,
                mimeType: mimeType,
                _meta: nil
            )
            let resourceContent = ResourceContent(
                resource: .blob(blobResource),
                annotations: nil,
                _meta: nil
            )
            return .resource(resourceContent)
        }
    }

    /// Asynchronously read text file.
    func readTextFileAsync(url: URL) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let text = try String(contentsOf: url, encoding: .utf8)
                    continuation.resume(returning: text)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Asynchronously read binary file.
    func readDataFileAsync(url: URL) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let data = try Data(contentsOf: url)
                    continuation.resume(returning: data)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Asynchronously base64-encode binary payloads off the main actor.
    func encodeBase64Async(_ data: Data) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: data.base64EncodedString())
            }
        }
    }

    /// Get MIME type from file URL.
    func getMimeType(for url: URL) -> String? {
        if let utType = UTType(filenameExtension: url.pathExtension) {
            return utType.preferredMIMEType
        }
        return nil
    }

    func createResourceLinkBlock(from url: URL) -> ContentBlock {
        let fileSize: Int?
        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attributes[.size] as? Int64,
           size <= Int64(Int.max) {
            fileSize = Int(size)
        } else {
            fileSize = nil
        }

        let link = ResourceLinkContent(
            uri: url.absoluteString,
            name: url.lastPathComponent,
            title: nil,
            description: nil,
            mimeType: getMimeType(for: url),
            size: fileSize,
            annotations: nil,
            _meta: nil
        )
        return .resourceLink(link)
    }

    func makePathReferenceNote(for url: URL, agentDisplayName: String) -> String {
        "Attached file path for \(agentDisplayName): \(url.path)"
    }
}
