//
//  GitChangesOverlayContainer.swift
//  aizen
//
//  Container that manages GitRepositoryService for the overlay
//

import SwiftUI
import os.log

struct GitChangesOverlayContainer: View {
    let worktree: Worktree
    let repository: Repository
    let repositoryManager: RepositoryManager
    @Binding var showingGitChanges: Bool

    @StateObject private var gitRepositoryService: GitRepositoryService

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen", category: "GitChangesOverlay")

    init(
        worktree: Worktree,
        repository: Repository,
        repositoryManager: RepositoryManager,
        showingGitChanges: Binding<Bool>
    ) {
        self.worktree = worktree
        self.repository = repository
        self.repositoryManager = repositoryManager
        _showingGitChanges = showingGitChanges
        _gitRepositoryService = StateObject(wrappedValue: GitRepositoryService(worktreePath: worktree.path ?? ""))
    }

    private var gitOperations: WorktreeGitOperations {
        WorktreeGitOperations(
            gitRepositoryService: gitRepositoryService,
            repositoryManager: repositoryManager,
            worktree: worktree,
            logger: logger
        )
    }

    var body: some View {
        GitChangesOverlayView(
            worktreePath: worktree.path ?? "",
            repository: repository,
            repositoryManager: repositoryManager,
            gitStatus: gitRepositoryService.currentStatus,
            isOperationPending: gitRepositoryService.isOperationPending,
            onClose: {
                showingGitChanges = false
            },
            onStageFile: gitOperations.stageFile,
            onUnstageFile: gitOperations.unstageFile,
            onStageAll: gitOperations.stageAll,
            onUnstageAll: gitOperations.unstageAll,
            onCommit: gitOperations.commit,
            onAmendCommit: gitOperations.amendCommit,
            onCommitWithSignoff: gitOperations.commitWithSignoff,
            onSwitchBranch: gitOperations.switchBranch,
            onCreateBranch: gitOperations.createBranch,
            onFetch: gitOperations.fetch,
            onPull: gitOperations.pull,
            onPush: gitOperations.push
        )
        .onAppear {
            gitRepositoryService.reloadStatus()
        }
    }
}
