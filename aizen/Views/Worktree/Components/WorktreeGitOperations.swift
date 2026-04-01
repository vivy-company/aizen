//
//  WorktreeGitOperations.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import SwiftUI
import os.log

@MainActor
struct WorktreeGitOperations {
    let gitOperationService: GitOperationService
    let repositoryManager: RepositoryManager
    let worktree: Worktree
    let logger: Logger

    func stageFile(_ file: String) {
        gitOperationService.stageFile(file, onError: { [logger] error in
            ToastManager.shared.show("Failed to stage file", type: .error)
            logger.error("Failed to stage file: \(error)")
        })
    }

    func unstageFile(_ file: String) {
        gitOperationService.unstageFile(file, onError: { [logger] error in
            ToastManager.shared.show("Failed to unstage file", type: .error)
            logger.error("Failed to unstage file: \(error)")
        })
    }

    func stageAll(onComplete: @escaping () -> Void) {
        gitOperationService.stageAll(
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
        gitOperationService.unstageAll(
            onSuccess: nil,
            onError: { [logger] error in
                ToastManager.shared.show("Failed to unstage files", type: .error)
                logger.error("Failed to unstage all files: \(error)")
            }
        )
    }

    func discardAll() {
        gitOperationService.discardAll(
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
        gitOperationService.cleanUntracked(
            onSuccess: {
                ToastManager.shared.show("Untracked files removed", type: .success)
            },
            onError: { [logger] error in
                ToastManager.shared.show("Failed to remove untracked files", type: .error)
                logger.error("Failed to clean untracked files: \(error)")
            }
        )
    }

    func commit(_ message: String) {
        ToastManager.shared.showLoading("Committing changes...")
        gitOperationService.commit(
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
        gitOperationService.amendCommit(
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
        gitOperationService.commitWithSignoff(
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

    func switchBranch(_ branch: String) {
        gitOperationService.checkoutBranch(branch) { [logger] error in
            ToastManager.shared.show("Failed to switch branch: \(error.localizedDescription)", type: .error, duration: 5.0)
            logger.error("Failed to switch branch: \(error)")
        }

        guard let repository = worktree.repository else { return }
        Task { [repositoryManager] in
            try? await repositoryManager.refreshRepository(repository)
        }
    }

    func createBranch(_ name: String) {
        gitOperationService.createBranch(name) { [logger] error in
            ToastManager.shared.show("Failed to create branch: \(error.localizedDescription)", type: .error, duration: 5.0)
            logger.error("Failed to create branch: \(error)")
        }

        guard let repository = worktree.repository else { return }
        Task { [repositoryManager] in
            try? await repositoryManager.refreshRepository(repository)
        }
    }

    func fetch() {
        gitOperationService.fetch(
            onSuccess: nil,
            onError: { [logger] error in
                logger.error("Failed to fetch changes: \(error)")
            }
        )
    }

    func pull() {
        gitOperationService.pull(
            onSuccess: nil,
            onError: { [logger] error in
                logger.error("Failed to pull changes: \(error)")
            }
        )
    }

    func push() {
        logger.info("Push initiated - using combined fetch+push operation")
        gitOperationService.fetchThenPush(
            onSuccess: { [logger] didPush in
                if didPush {
                    logger.info("Push completed successfully")
                } else {
                    logger.warning("Push skipped - remote has commits ahead, pull required")
                }
            },
            onError: { [logger] error in
                logger.error("Push operation failed: \(error.localizedDescription)")
            }
        )
    }
}
