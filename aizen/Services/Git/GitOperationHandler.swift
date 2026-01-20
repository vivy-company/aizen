//
//  GitOperationHandler.swift
//  aizen
//
//  Handles git operations with toast notifications and error handling
//

import Foundation
import os.log

@MainActor
class GitOperationHandler {
    private let gitService: GitRepositoryService
    private let repositoryManager: RepositoryManager
    private let logger: Logger

    init(gitService: GitRepositoryService, repositoryManager: RepositoryManager, logger: Logger) {
        self.gitService = gitService
        self.repositoryManager = repositoryManager
        self.logger = logger
    }

    // MARK: - Staging Operations

    func stageFile(_ file: String) {
        gitService.stageFile(file, onError: { [logger] error in
            ToastManager.shared.show("Failed to stage file", type: .error)
            logger.error("Failed to stage file: \(error)")
        })
    }

    func unstageFile(_ file: String) {
        gitService.unstageFile(file, onError: { [logger] error in
            ToastManager.shared.show("Failed to unstage file", type: .error)
            logger.error("Failed to unstage file: \(error)")
        })
    }

    func stageAll(onComplete: @escaping () -> Void) {
        gitService.stageAll(
            onSuccess: {
                onComplete()
            },
            onError: { [logger] error in
                ToastManager.shared.show("Failed to stage files", type: .error)
                logger.error("Failed to stage all files: \(error)")
            }
        )
    }

    func unstageAll() {
        gitService.unstageAll(
            onSuccess: nil,
            onError: { [logger] error in
                ToastManager.shared.show("Failed to unstage files", type: .error)
                logger.error("Failed to unstage all files: \(error)")
            }
        )
    }

    func discardAll() {
        gitService.discardAll(
            onSuccess: {
                ToastManager.shared.show("All changes discarded", type: .success)
            },
            onError: { [logger] error in
                ToastManager.shared.show("Failed to discard changes", type: .error)
                logger.error("Failed to discard all changes: \(error)")
            }
        )
    }

    func cleanUntracked() {
        gitService.cleanUntracked(
            onSuccess: {
                ToastManager.shared.show("Untracked files removed", type: .success)
            },
            onError: { [logger] error in
                ToastManager.shared.show("Failed to remove untracked files", type: .error)
                logger.error("Failed to clean untracked files: \(error)")
            }
        )
    }

    // MARK: - Commit Operations

    func commit(_ message: String) {
        ToastManager.shared.showLoading("Committing changes...")
        gitService.commit(
            message: message,
            onSuccess: {
                ToastManager.shared.show("Changes committed", type: .success)
            },
            onError: { [logger] error in
                ToastManager.shared.show("Commit failed: \(error.localizedDescription)", type: .error, duration: 5.0)
                logger.error("Failed to commit changes: \(error)")
            }
        )
    }

    func amendCommit(_ message: String) {
        ToastManager.shared.showLoading("Amending commit...")
        gitService.amendCommit(
            message: message,
            onSuccess: {
                ToastManager.shared.show("Commit amended", type: .success)
            },
            onError: { [logger] error in
                ToastManager.shared.show("Amend failed: \(error.localizedDescription)", type: .error, duration: 5.0)
                logger.error("Failed to amend commit: \(error)")
            }
        )
    }

    func commitWithSignoff(_ message: String) {
        ToastManager.shared.showLoading("Committing with sign-off...")
        gitService.commitWithSignoff(
            message: message,
            onSuccess: {
                ToastManager.shared.show("Changes committed", type: .success)
            },
            onError: { [logger] error in
                ToastManager.shared.show("Commit failed: \(error.localizedDescription)", type: .error, duration: 5.0)
                logger.error("Failed to commit with signoff: \(error)")
            }
        )
    }

    // MARK: - Branch Operations

    func switchBranch(_ branch: String, repository: Repository?) {
        gitService.checkoutBranch(branch) { [logger] error in
            ToastManager.shared.show("Failed to switch branch: \(error.localizedDescription)", type: .error, duration: 5.0)
            logger.error("Failed to switch branch: \(error)")
        }

        if let repository = repository {
            Task { [repositoryManager] in
                try? await repositoryManager.refreshRepository(repository)
            }
        }
    }

    func createBranch(_ name: String, repository: Repository?) {
        gitService.createBranch(name) { [logger] error in
            ToastManager.shared.show("Failed to create branch: \(error.localizedDescription)", type: .error, duration: 5.0)
            logger.error("Failed to create branch: \(error)")
        }

        if let repository = repository {
            Task { [repositoryManager] in
                try? await repositoryManager.refreshRepository(repository)
            }
        }
    }

    // MARK: - Remote Operations

    func fetch(repository: Repository?) {
        gitService.fetch(
            onSuccess: nil,
            onError: { [logger] error in
                logger.error("Failed to fetch changes: \(error)")
            }
        )
    }

    func pull(repository: Repository?) {
        gitService.pull(
            onSuccess: nil,
            onError: { [logger] error in
                logger.error("Failed to pull changes: \(error)")
            }
        )
    }

    func push(repository: Repository?) {
        logger.info("Push initiated - using combined fetch+push operation")

        // Use combined fetch-then-push to keep isOperationPending true throughout
        gitService.fetchThenPush(
            onSuccess: { [self] didPush in
                if didPush {
                    self.logger.info("Push completed successfully")
                } else {
                    self.logger.warning("Push skipped - remote has commits ahead, pull required")
                }
            },
            onError: { [self] error in
                self.logger.error("Push operation failed: \(error.localizedDescription)")
            }
        )
    }
}
