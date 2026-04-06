//
//  DiffView+DeletedFiles.swift
//  aizen
//

import Foundation

extension DiffView {
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
}
