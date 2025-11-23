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
        gitService.stageFile(file) { [logger] error in
            ToastManager.shared.show("Failed to stage file", type: .error)
            logger.error("Failed to stage file: \(error)")
        }
    }

    func unstageFile(_ file: String) {
        gitService.unstageFile(file) { [logger] error in
            ToastManager.shared.show("Failed to unstage file", type: .error)
            logger.error("Failed to unstage file: \(error)")
        }
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
        gitService.unstageAll { [logger] error in
            ToastManager.shared.show("Failed to unstage files", type: .error)
            logger.error("Failed to unstage all files: \(error)")
        }
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
        ToastManager.shared.showLoading("Fetching changes...")
        gitService.fetch(
            onSuccess: {
                ToastManager.shared.show("Fetch completed successfully", type: .success)
            },
            onError: { [logger] error in
                ToastManager.shared.show("Fetch failed: \(error.localizedDescription)", type: .error, duration: 5.0)
                logger.error("Failed to fetch changes: \(error)")
            }
        )

        if let repository = repository {
            Task { [repositoryManager] in
                try? await repositoryManager.refreshRepository(repository)
            }
        }
    }

    func pull(repository: Repository?) {
        ToastManager.shared.showLoading("Pulling changes...")
        gitService.pull(
            onSuccess: {
                ToastManager.shared.show("Pull completed successfully", type: .success)
            },
            onError: { [logger] error in
                ToastManager.shared.show("Pull failed: \(error.localizedDescription)", type: .error, duration: 5.0)
                logger.error("Failed to pull changes: \(error)")
            }
        )

        if let repository = repository {
            Task { [repositoryManager] in
                try? await repositoryManager.refreshRepository(repository)
            }
        }
    }

    func push(repository: Repository?) {
        logger.info("Push initiated - checking remote...")
        ToastManager.shared.showLoading("Checking remote...")

        // Fetch first to check for remote changes
        gitService.fetch(
            onSuccess: { [self] in
                self.logger.info("Fetch completed successfully in push flow")

                // After fetch, check if we're behind
                let status = self.gitService.currentStatus
                self.logger.info("Current status - ahead: \(status.aheadCount), behind: \(status.behindCount)")

                if status.behindCount > 0 {
                    self.logger.warning("Remote has \(status.behindCount) commits ahead, blocking push")
                    ToastManager.shared.show(
                        "Remote has \(status.behindCount) new commit(s). Pull manually before pushing.",
                        type: .error,
                        duration: 5.0
                    )
                } else {
                    // No remote changes, proceed with push
                    self.logger.info("No remote changes detected, proceeding with push")
                    self.performPush(repository: repository)
                }
            },
            onError: { [self] error in
                self.logger.error("Fetch failed in push flow: \(error.localizedDescription)")
                // Fetch failed, try push anyway
                self.performPush(repository: repository)
            }
        )
    }

    private func performPush(repository: Repository?) {
        logger.info("performPush called")
        ToastManager.shared.showLoading("Pushing changes...")
        gitService.push(
            onSuccess: { [self] in
                self.logger.info("Push completed successfully")
                ToastManager.shared.show("Push completed successfully", type: .success)
            },
            onError: { [self] error in
                self.logger.error("Failed to push changes: \(error)")
                ToastManager.shared.show("Push failed: \(error.localizedDescription)", type: .error, duration: 5.0)
            }
        )

        if let repository = repository {
            Task { [repositoryManager] in
                try? await repositoryManager.refreshRepository(repository)
            }
        }
    }
}
