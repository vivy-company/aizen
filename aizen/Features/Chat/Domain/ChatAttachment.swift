//
//  ChatAttachment.swift
//  aizen
//
//  Attachment types for chat messages
//

import Foundation

enum ChatAttachment: Identifiable, Hashable {
    case file(URL)
    case image(Data, mimeType: String) // pasted image data
    case text(String) // large pasted text
    case reviewComments(String) // markdown content
    case buildError(String) // build error log

    var id: String {
        switch self {
        case .file(let url):
            return "file-\(url.absoluteString)"
        case .image(let data, _):
            return "image-\(data.hashValue)"
        case .text(let content):
            return "text-\(content.hashValue)"
        case .reviewComments(let content):
            return "review-\(content.hashValue)"
        case .buildError(let content):
            return "build-\(content.hashValue)"
        }
    }

    var displayName: String {
        switch self {
        case .file(let url):
            return url.lastPathComponent
        case .image:
            return "Pasted Image"
        case .text(let content):
            let lineCount = content.components(separatedBy: .newlines).count
            return "Pasted Text (\(lineCount) lines)"
        case .reviewComments:
            return "Review Comments"
        case .buildError:
            return "Build Error"
        }
    }

    var iconName: String {
        switch self {
        case .file:
            return "doc"
        case .image:
            return "photo"
        case .text:
            return "doc.text"
        case .reviewComments:
            return "text.bubble"
        case .buildError:
            return "xmark.circle.fill"
        }
    }

    // For sending to agent - returns the content to include in message
    var contentForAgent: String? {
        switch self {
        case .file:
            // Files are handled separately by the agent protocol
            return nil
        case .image:
            // Images are handled separately as ImageContent blocks
            return nil
        case .text(let content):
            return content
        case .reviewComments(let content):
            return content
        case .buildError(let content):
            return content
        }
    }

    // Get file URL if this is a file attachment
    var fileURL: URL? {
        if case .file(let url) = self {
            return url
        }
        return nil
    }

    // Get image data and mime type if this is an image attachment
    var imageData: (data: Data, mimeType: String)? {
        if case .image(let data, let mimeType) = self {
            return (data, mimeType)
        }
        return nil
    }

    // Check if this is an image (either pasted or file)
    var isImage: Bool {
        switch self {
        case .image:
            return true
        case .file(let url):
            let ext = url.pathExtension.lowercased()
            return ["png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "tiff", "bmp"].contains(ext)
        default:
            return false
        }
    }
}
