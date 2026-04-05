//
//  DiffView+Parsing.swift
//  aizen
//

import Foundation

extension DiffView {
    static func filePaths(in diff: String) -> [String] {
        diff
            .components(separatedBy: .newlines)
            .compactMap { line in
                guard line.hasPrefix("diff --git ") else { return nil }
                let parts = line.split(separator: " ")
                guard parts.count >= 4 else { return nil }
                let bPath = String(parts[3])
                if bPath.hasPrefix("b/") {
                    return String(bPath.dropFirst(2))
                }
                return bPath
            }
    }

    static func unifiedDiff(from lines: [DiffLine]) -> String {
        let detectedPath = detectPath(from: lines) ?? "file"
        var output: [String] = []

        output.append("diff --git a/\(detectedPath) b/\(detectedPath)")
        output.append("--- a/\(detectedPath)")
        output.append("+++ b/\(detectedPath)")

        var hasHunkHeader = false

        for line in lines {
            switch line.type {
            case .header:
                let trimmedHeader = line.content.trimmingCharacters(in: .whitespaces)
                if trimmedHeader.hasPrefix("@@") {
                    output.append(trimmedHeader)
                    hasHunkHeader = true
                } else if line.content.hasPrefix("index ")
                    || line.content.hasPrefix("new file")
                    || line.content.hasPrefix("deleted file")
                    || line.content.hasPrefix("Binary files") {
                    output.append(line.content)
                }
            case .added:
                if !hasHunkHeader {
                    output.append("@@ -1,1 +1,1 @@")
                    hasHunkHeader = true
                }
                output.append("+\(line.content)")
            case .deleted:
                if !hasHunkHeader {
                    output.append("@@ -1,1 +1,1 @@")
                    hasHunkHeader = true
                }
                output.append("-\(line.content)")
            case .context:
                let trimmedContext = line.content.trimmingCharacters(in: .whitespaces)
                if trimmedContext.hasPrefix("@@") {
                    output.append(trimmedContext)
                    hasHunkHeader = true
                    continue
                }
                if !hasHunkHeader {
                    output.append("@@ -1,1 +1,1 @@")
                    hasHunkHeader = true
                }
                output.append(" \(line.content)")
            }
        }

        if !hasHunkHeader {
            output.append("@@ -1,1 +1,1 @@")
        }

        return output.joined(separator: "\n")
    }

    static func collapsedDeletedFileSections(in diff: String) -> String {
        guard diff.contains("deleted file mode") else {
            return diff
        }

        let lines = diff.components(separatedBy: .newlines)
        var preamble: [String] = []
        var chunks: [[String]] = []
        var currentChunk: [String] = []
        var hasDiffHeader = false

        for line in lines {
            if line.hasPrefix("diff --git ") {
                if hasDiffHeader {
                    chunks.append(currentChunk)
                    currentChunk = [line]
                } else {
                    hasDiffHeader = true
                    preamble = currentChunk
                    currentChunk = [line]
                }
                continue
            }
            currentChunk.append(line)
        }

        guard hasDiffHeader else {
            return diff
        }

        chunks.append(currentChunk)

        var output: [String] = preamble
        for chunk in chunks {
            if isDeletedFileChunk(chunk) {
                output.append(contentsOf: summarizedDeletedChunk(chunk))
            } else {
                output.append(contentsOf: chunk)
            }
        }
        return output.joined(separator: "\n")
    }

    static func isDeletedFileChunk(_ chunk: [String]) -> Bool {
        chunk.contains(where: { $0.hasPrefix("deleted file mode ") })
            || chunk.contains(where: { $0.hasPrefix("+++ /dev/null") })
    }

    static func summarizedDeletedChunk(_ chunk: [String]) -> [String] {
        var output: [String] = []

        if let header = chunk.first(where: { $0.hasPrefix("diff --git ") }) {
            output.append(header)
        }
        if let index = chunk.first(where: { $0.hasPrefix("index ") }) {
            output.append(index)
        }
        if let deletedMode = chunk.first(where: { $0.hasPrefix("deleted file mode ") }) {
            output.append(deletedMode)
        }
        if let oldFile = chunk.first(where: { $0.hasPrefix("--- ") }) {
            output.append(oldFile)
        }
        if let newFile = chunk.first(where: { $0.hasPrefix("+++ ") }) {
            output.append(newFile)
        } else {
            output.append("+++ /dev/null")
        }
        return output
    }

    static func detectPath(from lines: [DiffLine]) -> String? {
        for line in lines where line.type == .header {
            if line.content.hasPrefix("new file: ") {
                let value = line.content.replacingOccurrences(of: "new file: ", with: "")
                if !value.isEmpty {
                    return value
                }
            }
            if line.content.contains("/") {
                return line.content
            }
        }
        return nil
    }
}
