//
//  ChatMessageList+Helpers.swift
//  aizen
//

import ACP
import Foundation
import VVChatTimeline

extension ChatMessageList {
    func entryRevision(_ entry: VVChatTimelineEntry) -> Int {
        switch entry {
        case .message(let message):
            return message.revision
        case .custom(let custom):
            return custom.revision
        }
    }

    func diffLineDelta(oldText: String?, newText: String) -> (added: Int, removed: Int) {
        diffLineDelta(
            oldLines: diffTextLines(oldText),
            newLines: diffTextLines(newText)
        )
    }

    func primaryPath(for toolCall: ToolCall) -> String? {
        if let path = toolCall.locations?.first?.path {
            return path
        }

        for content in toolCall.content {
            if case .diff(let diff) = content {
                return diff.path
            }
        }

        if toolCall.title.contains("/") {
            return toolCall.title
        }

        return nil
    }

    func isToolGroupEntryID(_ entryID: String) -> Bool {
        lastBuildMetadata.groupEntryIDs.contains(entryID)
    }

    func destinationPath(from url: URL) -> String? {
        if url.scheme?.lowercased() == "aizen-file" {
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let rawPath = components.queryItems?.first(where: { $0.name == "path" })?.value,
                  !rawPath.isEmpty else {
                return nil
            }
            return resolveSummaryFilePath(rawPath)
        }

        if url.isFileURL {
            return url.standardizedFileURL.path
        }

        return nil
    }

    func inlineDiffPreviewDocument(for diff: ToolCallDiff) -> String {
        diffDocument(for: diff, contextLines: 2, maxOutputLines: 16)
    }

    func revisionKey(_ value: String) -> Int {
        let hashed = value.hashValue
        if hashed == Int.min {
            return Int.max
        }
        return abs(hashed)
    }

    private func diffTextLines(_ text: String?) -> [String] {
        guard let text, !text.isEmpty else { return [] }
        return text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    private func diffLineDelta(oldLines: [String], newLines: [String]) -> (added: Int, removed: Int) {
        if oldLines.isEmpty && newLines.isEmpty {
            return (0, 0)
        }
        if oldLines.isEmpty {
            return (newLines.count, 0)
        }
        if newLines.isEmpty {
            return (0, oldLines.count)
        }

        let lcs = longestCommonSubsequence(oldLines, newLines)
        var oldIndex = 0
        var newIndex = 0
        var lcsIndex = 0
        var added = 0
        var removed = 0

        while oldIndex < oldLines.count || newIndex < newLines.count {
            if lcsIndex < lcs.count,
               oldIndex < oldLines.count,
               newIndex < newLines.count,
               oldLines[oldIndex] == lcs[lcsIndex],
               newLines[newIndex] == lcs[lcsIndex] {
                oldIndex += 1
                newIndex += 1
                lcsIndex += 1
            } else if oldIndex < oldLines.count,
                      lcsIndex >= lcs.count || oldLines[oldIndex] != lcs[lcsIndex] {
                removed += 1
                oldIndex += 1
            } else if newIndex < newLines.count {
                added += 1
                newIndex += 1
            }
        }

        return (added, removed)
    }
}
