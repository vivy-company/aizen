//
//  FileBrowserStore+GitStatus.swift
//  aizen
//
//  Git status loading for the file browser
//

import Foundation

extension FileBrowserStore {
    func loadGitStatus() async {
        guard let worktreePath = worktree.path else { return }
        let expandedPathsSnapshot = expandedPaths
        let snapshot = await gitRuntime.loadGitSnapshot(
            basePath: worktreePath,
            expandedPaths: expandedPathsSnapshot
        )

        gitFileStatus = snapshot.fileStatus
        gitIgnoredPaths = snapshot.ignoredPaths
        refreshTree()
    }

    func refreshGitStatus() {
        Task {
            await loadGitStatus()
        }
    }
}
