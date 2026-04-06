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
