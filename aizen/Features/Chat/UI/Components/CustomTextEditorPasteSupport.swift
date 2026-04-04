//
//  CustomTextEditorPasteSupport.swift
//  aizen
//
//  Created by OpenAI Codex on 05.04.26.
//

import AppKit
import Foundation

enum CustomTextEditorPasteSupport {
    static func handleLargeTextPaste(
        onLargeTextPaste: ((String) -> Void)?
    ) -> Bool {
        guard let onLargeTextPaste else { return false }
        guard let pastedText = Clipboard.readString() else { return false }

        let lineCount = pastedText.components(separatedBy: .newlines).count
        let charCount = pastedText.count

        if charCount >= CustomTextEditor.largeTextCharacterThreshold ||
           lineCount >= CustomTextEditor.largeTextLineThreshold {
            onLargeTextPaste(pastedText)
            return true
        }

        return false
    }

    static func handleImagePaste(
        onImagePaste: ((Data, String) -> Void)?,
        onFilePaste: ((URL) -> Void)?
    ) -> Bool {
        let pasteboard = NSPasteboard.general

        if let data = pasteboard.data(forType: .png) {
            guard let onImagePaste else { return false }
            onImagePaste(data, "image/png")
            return true
        }

        if let data = pasteboard.data(forType: .tiff) {
            guard let onImagePaste else { return false }
            if let image = NSImage(data: data),
               let tiffData = image.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiffData),
               let pngData = bitmap.representation(using: .png, properties: [:]) {
                onImagePaste(pngData, "image/png")
                return true
            }
        }

        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           let url = urls.first {
            let ext = url.pathExtension.lowercased()
            let imageExtensions = ["png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "tiff", "bmp"]
            if imageExtensions.contains(ext) {
                if let onFilePaste {
                    onFilePaste(url)
                    return true
                }
                guard let onImagePaste else { return false }
                if let data = try? Data(contentsOf: url) {
                    onImagePaste(data, mimeType(forExtension: ext))
                    return true
                }
            }
        }

        return false
    }

    private static func mimeType(forExtension ext: String) -> String {
        switch ext.lowercased() {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "heic", "heif": return "image/heic"
        case "tiff", "tif": return "image/tiff"
        case "bmp": return "image/bmp"
        default: return "image/png"
        }
    }
}
