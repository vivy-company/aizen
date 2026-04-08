//  InlineDiffView+Runtime.swift
//  aizen
//

import ACP
import AppKit
import SwiftUI
import VVCode

extension InlineDiffView {
    var diffId: String {
        "\(diff.path)-\(diff.oldText?.hashValue ?? 0)-\(diff.newText.hashValue)"
    }

    var diffTaskId: String {
        allowCompute ? diffId : "diff-deferred-\(diff.path)"
    }

    var diffLines: [ChatDiffLine] {
        cachedDiffLines ?? []
    }

    var isDeletedFileDiff: Bool {
        guard let oldText = diff.oldText else { return false }
        return !oldText.isEmpty && diff.newText.isEmpty
    }

    var hasMoreLines: Bool {
        diffLines.count > previewLineCount
    }

    var previewDiffLines: [ChatDiffLine] {
        Array(diffLines.prefix(previewRenderLineCap))
    }

    var previewHeight: CGFloat {
        let rowHeight = max(15, CGFloat(diffFontSize + 4))
        return CGFloat(previewLineCount) * rowHeight + 26
    }

    var unifiedDiffText: String {
        Self.buildUnifiedDiff(path: diff.path, lines: diffLines)
    }

    var previewUnifiedDiffText: String {
        Self.buildUnifiedDiff(path: diff.path, lines: previewDiffLines)
    }

    func computeDiffAsync() async {
        guard allowCompute else { return }

        if lastComputedDiffId != diffId {
            cachedDiffLines = nil
        }

        guard cachedDiffLines == nil else { return }
        lastComputedDiffId = diffId

        if isDeletedFileDiff {
            cachedDiffLines = []
            isComputing = false
            return
        }

        isComputing = true

        let oldText = diff.oldText
        let newText = diff.newText
        let oldLineCount = oldText?.split(separator: "\n", omittingEmptySubsequences: false).count ?? 0
        let newLineCount = newText.split(separator: "\n", omittingEmptySubsequences: false).count
        let combinedCharacters = (oldText?.count ?? 0) + newText.count
        let isLargeDiff = combinedCharacters > largeDiffCharacterThreshold || (oldLineCount + newLineCount) > largeDiffLineThreshold

        let lines = await Task.detached(priority: .userInitiated) {
            if isLargeDiff {
                return InlineDiffComputer.computeUnifiedDiff(
                    oldText: oldText,
                    newText: newText,
                    contextLines: 1,
                    maxOutputLines: 600
                )
            }
            return InlineDiffComputer.computeUnifiedDiff(
                oldText: oldText,
                newText: newText,
                contextLines: 3,
                maxOutputLines: 2_000
            )
        }.value

        cachedDiffLines = lines
        isComputing = false
    }
}
