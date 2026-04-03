import Foundation

extension GitPanelWindowContent {
    func updateChangedFilesCache() -> Bool {
        var files = Set<String>()
        files.formUnion(gitStatus.stagedFiles)
        files.formUnion(gitStatus.modifiedFiles)
        files.formUnion(gitStatus.untrackedFiles)
        files.formUnion(gitStatus.conflictedFiles)

        let sortedFiles = files.sorted()
        if sortedFiles != cachedChangedFiles {
            cachedChangedFiles = sortedFiles
            return true
        }
        return false
    }

    func validateCommentsAgainstDiff() {
        guard selectedHistoryCommit == nil else { return }

        let filesInDiff = Set(allChangedFiles)
        let commentsToRemove = reviewManager.comments.filter { !filesInDiff.contains($0.filePath) }

        for comment in commentsToRemove {
            reviewManager.deleteComment(id: comment.id)
        }
    }

    @MainActor
    func synchronizeDiffOutput(for commit: GitCommit?) async {
        let path = worktreePath
        guard !path.isEmpty else {
            applyDiffOutput("")
            return
        }

        let commitID = commit?.id
        guard let commitID else {
            applyDiffOutput(gitDiffStore.diffOutput)
            return
        }

        let output = await Self.loadCommitDiff(path: path, commitID: commitID)
        guard !Task.isCancelled else { return }
        guard worktreePath == path else { return }
        guard selectedHistoryCommit?.id == commitID else { return }
        applyDiffOutput(output)
    }

    func applyDiffOutput(_ output: String) {
        if historyDiffOutput != output {
            historyDiffOutput = output
        }
    }

    func syncRuntimeVisibility() {
        let shouldUseWorkingDiff = selectedHistoryCommit == nil && selectedTab != .workflows && selectedTab != .prs
        runtime.setGitPanelVisible(true, showsWorkingDiff: shouldUseWorkingDiff, showsWorkflow: selectedTab == .workflows)
    }

    nonisolated static func loadCommitDiff(path: String, commitID: String) async -> String {
        do {
            let result = try await ProcessExecutor.shared.executeWithOutput(
                executable: "/usr/bin/git",
                arguments: ["show", "--format=", commitID],
                workingDirectory: path
            )
            return result.stdout
        } catch {
            return ""
        }
    }
}
