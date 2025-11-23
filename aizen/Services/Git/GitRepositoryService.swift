//
//  GitRepositoryService.swift
//  aizen
//
//  Orchestrates Git operations using domain services
//  Based on Zed editor architecture
//

import Foundation
import Combine
import os.log

class GitRepositoryService: ObservableObject {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen.app", category: "GitRepository")
    @Published private(set) var currentStatus: GitStatus = .empty
    @Published private(set) var isOperationPending = false

    private let worktreePath: String

    // Shared executor (reused across all operations)
    private let executor: GitCommandExecutor

    // Domain services
    private let statusService: GitStatusService
    private let stagingService: GitStagingService
    private let branchService: GitBranchService
    private let remoteService: GitRemoteService

    init(worktreePath: String) {
        self.worktreePath = worktreePath

        // Initialize shared executor
        let executor = GitCommandExecutor()
        self.executor = executor

        // Initialize domain services
        self.statusService = GitStatusService(executor: executor)
        self.stagingService = GitStagingService(executor: executor)
        self.branchService = GitBranchService(executor: executor)
        self.remoteService = GitRemoteService(executor: executor)
    }

    // MARK: - Public API - Staging Operations

    func stageFile(_ file: String, onError: ((Error) -> Void)? = nil) {
        Task { [weak self] in
            guard let self = self else { return }
            await self.executeOperationBackground(
                { try await self.stagingService.stageFile(at: self.worktreePath, file: file) },
                onError: onError
            )
        }
    }

    func unstageFile(_ file: String, onError: ((Error) -> Void)? = nil) {
        Task { [weak self] in
            guard let self = self else { return }
            await self.executeOperationBackground(
                { try await self.stagingService.unstageFile(at: self.worktreePath, file: file) },
                onError: onError
            )
        }
    }

    func stageAll(onSuccess: (() -> Void)? = nil, onError: ((Error) -> Void)? = nil) {
        Task { [weak self] in
            guard let self = self else { return }
            await self.executeOperationBackground(
                { try await self.stagingService.stageAll(at: self.worktreePath) },
                onSuccess: onSuccess,
                onError: onError
            )
        }
    }

    func unstageAll(onError: ((Error) -> Void)? = nil) {
        Task { [weak self] in
            guard let self = self else { return }
            await self.executeOperationBackground(
                { try await self.stagingService.unstageAll(at: self.worktreePath) },
                onError: onError
            )
        }
    }

    func commit(message: String, onSuccess: (() -> Void)? = nil, onError: ((Error) -> Void)? = nil) {
        Task { [weak self] in
            guard let self = self else { return }
            await self.executeOperationBackground(
                { try await self.stagingService.commit(at: self.worktreePath, message: message) },
                onSuccess: onSuccess,
                onError: onError
            )
        }
    }

    func amendCommit(message: String, onSuccess: (() -> Void)? = nil, onError: ((Error) -> Void)? = nil) {
        Task { [weak self] in
            guard let self = self else { return }
            await self.executeOperationBackground(
                { try await self.stagingService.amendCommit(at: self.worktreePath, message: message) },
                onSuccess: onSuccess,
                onError: onError
            )
        }
    }

    func commitWithSignoff(message: String, onSuccess: (() -> Void)? = nil, onError: ((Error) -> Void)? = nil) {
        Task { [weak self] in
            guard let self = self else { return }
            await self.executeOperationBackground(
                { try await self.stagingService.commitWithSignoff(at: self.worktreePath, message: message) },
                onSuccess: onSuccess,
                onError: onError
            )
        }
    }

    // MARK: - Branch Operations

    func checkoutBranch(_ branch: String, onError: ((Error) -> Void)? = nil) {
        Task { [weak self] in
            guard let self = self else { return }
            await self.executeOperationBackground(
                { try await self.branchService.checkoutBranch(at: self.worktreePath, branch: branch) },
                onError: onError
            )
        }
    }

    func createBranch(_ name: String, from: String? = nil, onError: ((Error) -> Void)? = nil) {
        Task { [weak self] in
            guard let self = self else { return }
            await self.executeOperationBackground(
                { try await self.branchService.createBranch(at: self.worktreePath, name: name, from: from) },
                onError: onError
            )
        }
    }

    // MARK: - Remote Operations

    func fetch(onSuccess: (() -> Void)? = nil, onError: ((Error) -> Void)? = nil) {
        logger.info("GitRepositoryService.fetch() called")
        Task { [weak self] in
            guard let self = self else {
                self?.logger.error("fetch: self is nil in Task")
                return
            }
            self.logger.info("fetch: starting executeOperationBackground")
            await self.executeOperationBackground(
                {
                    self.logger.info("fetch: executing remoteService.fetch")
                    try await self.remoteService.fetch(at: self.worktreePath)
                    self.logger.info("fetch: remoteService.fetch completed")
                },
                onSuccess: { [weak self] in
                    guard let self = self else {
                        self?.logger.info("fetch onSuccess: self is nil, calling callback")
                        onSuccess?()
                        return
                    }
                    self.logger.info("fetch onSuccess: starting status reload")
                    // Refresh status after fetch to update ahead/behind counts
                    Task { [weak self] in
                        guard let self = self else { return }
                        self.logger.info("fetch onSuccess: calling reloadStatusInternal")
                        await self.reloadStatusInternal()
                        self.logger.info("fetch onSuccess: reloadStatusInternal completed, calling callback")
                        await MainActor.run {
                            onSuccess?()
                            self.logger.info("fetch onSuccess: callback completed")
                        }
                    }
                },
                onError: { error in
                    self.logger.error("fetch failed: \(error.localizedDescription)")
                    onError?(error)
                }
            )
        }
    }

    func pull(onSuccess: (() -> Void)? = nil, onError: ((Error) -> Void)? = nil) {
        Task { [weak self] in
            guard let self = self else { return }
            await self.executeOperationBackground(
                { try await self.remoteService.pull(at: self.worktreePath) },
                onSuccess: { [weak self] in
                    guard let self = self else {
                        onSuccess?()
                        return
                    }
                    // Refresh status after pull to update file lists and tracking info
                    Task { [weak self] in
                        guard let self = self else { return }
                        await self.reloadStatusInternal()
                        await MainActor.run {
                            onSuccess?()
                        }
                    }
                },
                onError: onError
            )
        }
    }

    func push(setUpstream: Bool = false, onSuccess: (() -> Void)? = nil, onError: ((Error) -> Void)? = nil) {
        logger.info("GitRepositoryService.push() called")
        Task { [weak self] in
            guard let self = self else { return }
            self.logger.info("push: starting executeOperationBackground")
            await self.executeOperationBackground(
                {
                    self.logger.info("push: executing remoteService.push")
                    try await self.remoteService.push(at: self.worktreePath, setUpstream: setUpstream)
                    self.logger.info("push: remoteService.push completed")
                },
                onSuccess: { [weak self] in
                    guard let self = self else {
                        self?.logger.info("push onSuccess: self is nil, calling callback")
                        onSuccess?()
                        return
                    }
                    self.logger.info("push onSuccess: starting status reload")
                    // Refresh status after push to update ahead/behind counts
                    Task { [weak self] in
                        guard let self = self else { return }
                        self.logger.info("push onSuccess: calling reloadStatusInternal")
                        await self.reloadStatusInternal()
                        self.logger.info("push onSuccess: reloadStatusInternal completed, calling callback")
                        await MainActor.run {
                            onSuccess?()
                            self.logger.info("push onSuccess: callback completed")
                        }
                    }
                },
                onError: { error in
                    self.logger.error("push failed: \(error.localizedDescription)")
                    onError?(error)
                }
            )
        }
    }

    // MARK: - Status Loading

    func reloadStatus() {
        Task { [weak self] in
            guard let self = self else { return }
            await self.reloadStatusInternal()
        }
    }

    // MARK: - Private Methods

    private func executeOperationBackground(_ operation: @escaping () async throws -> Void, onSuccess: (() -> Void)? = nil, onError: ((Error) -> Void)? = nil) async {
        // Set pending on MainActor
        await MainActor.run {
            self.isOperationPending = true
        }

        do {
            // Execute operation (already on background via Task)
            try await operation()

            // Success callback on MainActor
            if let onSuccess = onSuccess {
                await MainActor.run {
                    onSuccess()
                }
            }
        } catch {
            await MainActor.run {
                onError?(error)
            }
        }

        // Clear pending on MainActor
        await MainActor.run {
            self.isOperationPending = false
        }
    }

    private func reloadStatusInternal() async {
        do {
            let status = try await loadGitStatus()
            await MainActor.run {
                self.currentStatus = status
            }
        } catch {
            logger.error("Failed to reload Git status: \(error)")
        }
    }

    nonisolated
    private func loadGitStatus() async throws -> GitStatus {
        // Get detailed status from statusService (includes additions/deletions)
        let detailedStatus = try await statusService.getDetailedStatus(at: worktreePath)

        return GitStatus(
            stagedFiles: detailedStatus.stagedFiles,
            modifiedFiles: detailedStatus.modifiedFiles,
            untrackedFiles: detailedStatus.untrackedFiles,
            conflictedFiles: detailedStatus.conflictedFiles,
            currentBranch: detailedStatus.currentBranch ?? "",
            aheadCount: detailedStatus.aheadBy,
            behindCount: detailedStatus.behindBy,
            additions: detailedStatus.additions,
            deletions: detailedStatus.deletions
        )
    }
}
