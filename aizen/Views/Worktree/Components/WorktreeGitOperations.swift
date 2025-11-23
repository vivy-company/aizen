//
//  WorktreeGitOperations.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import SwiftUI
import os.log

struct WorktreeGitOperations {
    let gitRepositoryService: GitRepositoryService
    let repositoryManager: RepositoryManager
    let worktree: Worktree
    let logger: Logger

    private var handler: GitOperationHandler {
        GitOperationHandler(
            gitService: gitRepositoryService,
            repositoryManager: repositoryManager,
            logger: logger
        )
    }

    func stageFile(_ file: String) {
        handler.stageFile(file)
    }

    func unstageFile(_ file: String) {
        handler.unstageFile(file)
    }

    func stageAll(onComplete: @escaping () -> Void) {
        handler.stageAll(onComplete: onComplete)
    }

    func unstageAll() {
        handler.unstageAll()
    }

    func commit(_ message: String) {
        handler.commit(message)
    }

    func amendCommit(_ message: String) {
        handler.amendCommit(message)
    }

    func commitWithSignoff(_ message: String) {
        handler.commitWithSignoff(message)
    }

    func switchBranch(_ branch: String) {
        handler.switchBranch(branch, repository: worktree.repository)
    }

    func createBranch(_ name: String) {
        handler.createBranch(name, repository: worktree.repository)
    }

    func fetch() {
        handler.fetch(repository: worktree.repository)
    }

    func pull() {
        handler.pull(repository: worktree.repository)
    }

    func push() {
        handler.push(repository: worktree.repository)
    }
}
