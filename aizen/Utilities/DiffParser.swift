//
//  DiffParser.swift
//  aizen
//
//  Unified diff parsing utilities
//

import Foundation

nonisolated enum DiffParser {
    /// Parse unified diff output into DiffLine array
    static func parseUnifiedDiff(_ diffOutput: String) -> [DiffLine] {
        var parsed: [DiffLine] = []
        parsed.reserveCapacity(max(256, diffOutput.count / 48))

        var lineCounter = 0
        var oldLineNum = 0
        var newLineNum = 0

        diffOutput.enumerateLines { line, _ in
            if line.hasPrefix("@@") {
                // Hunk header
                for component in line.split(separator: " ") {
                    if component.hasPrefix("-") && !component.hasPrefix("---") {
                        let rangeStr = component.dropFirst()
                        if let numPart = rangeStr.split(separator: ",").first,
                           let start = Int(numPart) {
                            oldLineNum = start - 1
                        }
                    } else if component.hasPrefix("+") && !component.hasPrefix("+++") {
                        let rangeStr = component.dropFirst()
                        if let numPart = rangeStr.split(separator: ",").first,
                           let start = Int(numPart) {
                            newLineNum = start - 1
                        }
                    }
                }

                parsed.append(DiffLine(
                    lineNumber: lineCounter,
                    oldLineNumber: nil,
                    newLineNumber: nil,
                    content: line,
                    type: .header
                ))
                lineCounter += 1
                return
            }

            if line.hasPrefix("+++") || line.hasPrefix("---") ||
                line.hasPrefix("diff ") || line.hasPrefix("index ") {
                // Skip file headers
                return
            }

            if line.hasPrefix("+") {
                newLineNum += 1
                parsed.append(DiffLine(
                    lineNumber: lineCounter,
                    oldLineNumber: nil,
                    newLineNumber: String(newLineNum),
                    content: String(line.dropFirst()),
                    type: .added
                ))
                lineCounter += 1
                return
            }

            if line.hasPrefix("-") {
                oldLineNum += 1
                parsed.append(DiffLine(
                    lineNumber: lineCounter,
                    oldLineNumber: String(oldLineNum),
                    newLineNumber: nil,
                    content: String(line.dropFirst()),
                    type: .deleted
                ))
                lineCounter += 1
                return
            }

            if line.hasPrefix(" ") {
                oldLineNum += 1
                newLineNum += 1
                parsed.append(DiffLine(
                    lineNumber: lineCounter,
                    oldLineNumber: String(oldLineNum),
                    newLineNumber: String(newLineNum),
                    content: String(line.dropFirst()),
                    type: .context
                ))
                lineCounter += 1
            }
        }

        return parsed
    }

    /// Split multi-file diff output by file path
    static func splitDiffByFile(_ diffOutput: String) -> [String: [DiffLine]] {
        var result: [String: [DiffLine]] = [:]

        var currentFilePath: String?
        var currentChunkLines: [String] = []
        currentChunkLines.reserveCapacity(256)

        func flushCurrentChunk() {
            guard let path = currentFilePath, !path.isEmpty, !currentChunkLines.isEmpty else {
                currentFilePath = nil
                currentChunkLines.removeAll(keepingCapacity: true)
                return
            }

            let chunkText = currentChunkLines.joined(separator: "\n")
            let lines = parseUnifiedDiff(chunkText)
            if !lines.isEmpty {
                result[path] = lines
            }

            currentFilePath = nil
            currentChunkLines.removeAll(keepingCapacity: true)
        }

        diffOutput.enumerateLines { line, _ in
            if line.hasPrefix("diff --git ") {
                flushCurrentChunk()
                currentChunkLines.append(line)
                currentFilePath = parseFilePathFromDiffHeader(line)
                return
            }

            guard currentFilePath != nil else { return }
            currentChunkLines.append(line)
        }

        flushCurrentChunk()
        return result
    }

    private static func parseFilePathFromDiffHeader(_ line: String) -> String? {
        // Format: "diff --git a/<path> b/<path>"
        let parts = line.split(separator: " ")
        guard parts.count >= 4 else { return nil }
        let bPart = parts[3]
        if bPart.hasPrefix("b/") {
            return String(bPart.dropFirst(2))
        }
        return String(bPart)
    }
}
