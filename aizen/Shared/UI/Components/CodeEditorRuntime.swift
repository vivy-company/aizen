//
//  CodeEditorRuntime.swift
//  aizen
//
//  Persistent editor runtime for retaining VVCode document state across view mounts.
//

import Combine
import Foundation
import VVCode

@MainActor
final class CodeEditorRuntime: ObservableObject {
    struct DocumentSyncKey: Hashable {
        let content: String
        let language: String?
    }

    struct DiffReloadKey: Hashable {
        let content: String
        let filePath: String?
        let repoPath: String?
        let hasUnsavedChanges: Bool
    }

    var document: VVDocument
    @Published private(set) var gitDiffText: String?

    private var lastDocumentSyncKey: DocumentSyncKey?
    private var lastDiffReloadKey: DiffReloadKey?
    private var diffReloadTask: Task<Void, Never>?
    private var pendingSelectionRequest: SearchOpenRequest?
    private var selectionRevision = 0
    private var appliedSelectionRevision = 0

    var hasPendingLocationSelection: Bool {
        pendingSelectionRequest?.hasLocation == true && selectionRevision != appliedSelectionRevision
    }

    init(content: String, language: String?) {
        self.document = VVDocument(
            text: content,
            language: VVLanguageBridge.language(from: language)
        )
        self.lastDocumentSyncKey = DocumentSyncKey(content: content, language: language)
    }

    deinit {
        diffReloadTask?.cancel()
    }

    func syncDocument(content: String, language: String?) {
        let key = DocumentSyncKey(content: content, language: language)
        guard key != lastDocumentSyncKey else { return }
        lastDocumentSyncKey = key

        if document.text != content {
            document.text = content
        }

        let resolvedLanguage = VVLanguageBridge.language(from: language)
        if document.language != resolvedLanguage {
            document.language = resolvedLanguage
        }
    }

    func reloadGitDiffIfNeeded(
        content: String,
        filePath: String?,
        repoPath: String?,
        hasUnsavedChanges: Bool
    ) {
        let key = DiffReloadKey(
            content: content,
            filePath: filePath,
            repoPath: repoPath,
            hasUnsavedChanges: hasUnsavedChanges
        )

        guard key != lastDiffReloadKey else { return }
        lastDiffReloadKey = key

        diffReloadTask?.cancel()

        guard !hasUnsavedChanges else {
            gitDiffText = nil
            return
        }

        diffReloadTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(300))
            } catch {
                return
            }

            guard let self, !Task.isCancelled else { return }
            await self.loadGitDiff(filePath: filePath, repoPath: repoPath)
            self.diffReloadTask = nil
        }
    }

    func clearGitDiff() {
        diffReloadTask?.cancel()
        diffReloadTask = nil
        lastDiffReloadKey = nil
        gitDiffText = nil
    }

    func queueSelectionRequest(_ request: SearchOpenRequest?) {
        guard pendingSelectionRequest != request else { return }
        pendingSelectionRequest = request
        selectionRevision += 1
    }

    func consumePendingSelectionRange(
        for filePath: String?,
        content: String
    ) -> NSRange? {
        guard selectionRevision != appliedSelectionRevision else {
            return nil
        }

        guard let pendingSelectionRequest else {
            appliedSelectionRevision = selectionRevision
            return nil
        }

        if let filePath,
           pendingSelectionRequest.path != filePath {
            return nil
        }

        appliedSelectionRevision = selectionRevision

        guard pendingSelectionRequest.hasLocation else {
            return nil
        }

        return selectionRange(for: pendingSelectionRequest, in: content)
    }

    private func loadGitDiff(filePath: String?, repoPath: String?) async {
        guard let filePath, let repoPath else {
            gitDiffText = nil
            return
        }

        let fileURL = URL(fileURLWithPath: filePath)
        let repoURL = URL(fileURLWithPath: repoPath)
        var relativePath = fileURL.path
        if fileURL.path.hasPrefix(repoURL.path + "/") {
            relativePath = String(fileURL.path.dropFirst(repoURL.path.count + 1))
        }

        if let diff = await runGitDiff(repoPath: repoPath, arguments: ["diff", "HEAD", "--", relativePath]),
           !diff.isEmpty {
            gitDiffText = diff
            return
        }

        if let diff = await runGitDiff(repoPath: repoPath, arguments: ["diff", "--", relativePath]),
           !diff.isEmpty {
            gitDiffText = diff
            return
        }

        gitDiffText = nil
    }

    private func runGitDiff(repoPath: String, arguments: [String]) async -> String? {
        await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["git", "-C", repoPath] + arguments

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            do {
                try process.run()
            } catch {
                return nil
            }

            process.waitUntilExit()

            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            guard !data.isEmpty else { return nil }
            return String(data: data, encoding: .utf8)
        }.value
    }

    private func selectionRange(for request: SearchOpenRequest, in content: String) -> NSRange {
        let lineMap = LineMap(text: content)
        let requestedStartLine = max(request.line ?? 1, 1)
        let startLine = min(requestedStartLine, max(lineMap.lineCount, 1))
        let startLineRange = lineMap.range(forLine: startLine)
        let maxStartColumn = max(1, startLineRange.length + 1)
        let startColumn = min(max(request.column ?? 1, 1), maxStartColumn)
        let startOffset = lineMap.offset(forLine: startLine, column: startColumn)

        guard let endLine = request.endLine ?? request.line,
              let endColumn = request.endColumn else {
            return NSRange(location: startOffset, length: 0)
        }

        let clampedEndLine = min(max(endLine, 1), max(lineMap.lineCount, 1))
        let endLineRange = lineMap.range(forLine: clampedEndLine)
        let maxEndColumn = max(1, endLineRange.length + 1)
        let clampedEndColumn = min(max(endColumn, 1), maxEndColumn)
        let endOffset = lineMap.offset(forLine: clampedEndLine, column: clampedEndColumn)
        let rangeStart = min(startOffset, endOffset)
        let rangeLength = max(0, max(startOffset, endOffset) - rangeStart)
        return NSRange(location: rangeStart, length: rangeLength)
    }
}
