//
//  GitRepositoryService.swift
//  aizen
//
//  Orchestrates Git operations using domain services with libgit2
//

import Foundation
import Combine
import os.log

class GitRepositoryService: ObservableObject {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen.app", category: "GitRepository")
    @Published private(set) var currentStatus: GitStatus = .empty
    @Published private(set) var isOperationPending = false

    private(set) var worktreePath: String

    // Domain services (no longer need executor)
    private let statusService = GitStatusService()
    private let stagingService = GitStagingService()
    private let branchService = GitBranchService()
    private let remoteService = GitRemoteService()

    // Debouncing for status reload
    private var statusReloadTask: Task<Void, Never>?
    private var isStatusReloadPending = false
    private let statusReloadDebounceInterval: TimeInterval = 1.0
    private var inFlightStatusTask: Task<Void, Never>?
    private var pendingReloadIsLightweight = true

    init(worktreePath: String) {
        self.worktreePath = worktreePath
    }

    // MARK: - Public API - Staging Operations

    func stageFile(_ file: String, onSuccess: (() -> Void)? = nil, onError: ((Error) -> Void)? = nil) {
        let worktreePath = self.worktreePath
        let stagingService = self.stagingService
        Task.detached { [weak self] in
            guard let self = self else { return }
            await self.executeOperationBackground(
                { try await stagingService.stageFile(at: worktreePath, file: file) },
                onSuccess: self.makeRefreshingSuccessHandler(original: onSuccess),
                onError: onError
            )
        }
    }

    func unstageFile(_ file: String, onSuccess: (() -> Void)? = nil, onError: ((Error) -> Void)? = nil) {
        let worktreePath = self.worktreePath
        let stagingService = self.stagingService
        Task.detached { [weak self] in
            guard let self = self else { return }
            await self.executeOperationBackground(
                { try await stagingService.unstageFile(at: worktreePath, file: file) },
                onSuccess: self.makeRefreshingSuccessHandler(original: onSuccess),
                onError: onError
            )
        }
    }

    func stageAll(onSuccess: (() -> Void)? = nil, onError: ((Error) -> Void)? = nil) {
        let worktreePath = self.worktreePath
        let stagingService = self.stagingService
        Task.detached { [weak self] in
            guard let self = self else { return }
            await self.executeOperationBackground(
                { try await stagingService.stageAll(at: worktreePath) },
                onSuccess: self.makeRefreshingSuccessHandler(original: onSuccess),
                onError: onError
            )
        }
    }

    func unstageAll(onSuccess: (() -> Void)? = nil, onError: ((Error) -> Void)? = nil) {
        let worktreePath = self.worktreePath
        let stagingService = self.stagingService
        Task.detached { [weak self] in
            guard let self = self else { return }
            await self.executeOperationBackground(
                { try await stagingService.unstageAll(at: worktreePath) },
                onSuccess: self.makeRefreshingSuccessHandler(original: onSuccess),
                onError: onError
            )
        }
    }

    func discardAll(onSuccess: (() -> Void)? = nil, onError: ((Error) -> Void)? = nil) {
        let worktreePath = self.worktreePath
        let stagingService = self.stagingService
        Task.detached { [weak self] in
            guard let self = self else { return }
            await self.executeOperationBackground(
                { try await stagingService.discardAll(at: worktreePath) },
                onSuccess: self.makeRefreshingSuccessHandler(original: onSuccess),
                onError: onError
            )
        }
    }

    func cleanUntracked(onSuccess: (() -> Void)? = nil, onError: ((Error) -> Void)? = nil) {
        let worktreePath = self.worktreePath
        let stagingService = self.stagingService
        Task.detached { [weak self] in
            guard let self = self else { return }
            await self.executeOperationBackground(
                { try await stagingService.cleanUntracked(at: worktreePath) },
                onSuccess: self.makeRefreshingSuccessHandler(original: onSuccess),
                onError: onError
            )
        }
    }

    func commit(message: String, onSuccess: (() -> Void)? = nil, onError: ((Error) -> Void)? = nil) {
        let worktreePath = self.worktreePath
        let stagingService = self.stagingService
        Task.detached { [weak self] in
            guard let self = self else { return }
            await self.executeOperationBackground(
                { try await stagingService.commit(at: worktreePath, message: message) },
                onSuccess: self.makeRefreshingSuccessHandler(original: onSuccess),
                onError: onError
            )
        }
    }

    func amendCommit(message: String, onSuccess: (() -> Void)? = nil, onError: ((Error) -> Void)? = nil) {
        let worktreePath = self.worktreePath
        let stagingService = self.stagingService
        Task.detached { [weak self] in
            guard let self = self else { return }
            await self.executeOperationBackground(
                { try await stagingService.amendCommit(at: worktreePath, message: message) },
                onSuccess: self.makeRefreshingSuccessHandler(original: onSuccess),
                onError: onError
            )
        }
    }

    func commitWithSignoff(message: String, onSuccess: (() -> Void)? = nil, onError: ((Error) -> Void)? = nil) {
        let worktreePath = self.worktreePath
        let stagingService = self.stagingService
        Task.detached { [weak self] in
            guard let self = self else { return }
            await self.executeOperationBackground(
                { try await stagingService.commitWithSignoff(at: worktreePath, message: message) },
                onSuccess: self.makeRefreshingSuccessHandler(original: onSuccess),
                onError: onError
            )
        }
    }

    // MARK: - Branch Operations

    func checkoutBranch(_ branch: String, onError: ((Error) -> Void)? = nil) {
        let worktreePath = self.worktreePath
        let branchService = self.branchService
        Task.detached { [weak self] in
            guard let self = self else { return }
            await self.executeOperationBackground(
                { try await branchService.checkoutBranch(at: worktreePath, branch: branch) },
                onError: onError
            )
        }
    }

    func createBranch(_ name: String, from: String? = nil, onError: ((Error) -> Void)? = nil) {
        let worktreePath = self.worktreePath
        let branchService = self.branchService
        Task.detached { [weak self] in
            guard let self = self else { return }
            await self.executeOperationBackground(
                { try await branchService.createBranch(at: worktreePath, name: name, from: from) },
                onSuccess: nil,
                onError: onError
            )
        }
    }

    // MARK: - Remote Operations

    func fetch(onSuccess: (() -> Void)? = nil, onError: ((Error) -> Void)? = nil) {
        logger.info("GitRepositoryService.fetch() called")
        let worktreePath = self.worktreePath
        let remoteService = self.remoteService
        Task.detached { [weak self] in
            guard let self = self else { return }
            self.logger.info("fetch: starting executeOperationBackground")
            await self.executeOperationBackground(
                {
                    self.logger.info("fetch: executing remoteService.fetch")
                    try await remoteService.fetch(at: worktreePath)
                    self.logger.info("fetch: remoteService.fetch completed")
                },
                onSuccess: { [weak self] in
                    guard let self = self else {
                        await MainActor.run { onSuccess?() }
                        return
                    }
                    self.logger.info("fetch onSuccess: calling reloadStatusInternal")
                    await self.reloadStatusInternal()
                    self.logger.info("fetch onSuccess: reloadStatusInternal completed, calling callback")
                    await MainActor.run {
                        onSuccess?()
                        self.logger.info("fetch onSuccess: callback completed")
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
        let worktreePath = self.worktreePath
        let remoteService = self.remoteService
        Task.detached { [weak self] in
            guard let self = self else { return }
            await self.executeOperationBackground(
                { try await remoteService.pull(at: worktreePath) },
                onSuccess: { [weak self] in
                    guard let self = self else {
                        await MainActor.run { onSuccess?() }
                        return
                    }
                    await self.reloadStatusInternal()
                    await MainActor.run {
                        onSuccess?()
                    }
                },
                onError: onError
            )
        }
    }

    func push(setUpstream: Bool = false, onSuccess: (() -> Void)? = nil, onError: ((Error) -> Void)? = nil) {
        logger.info("GitRepositoryService.push() called")
        let worktreePath = self.worktreePath
        let remoteService = self.remoteService
        Task.detached { [weak self] in
            guard let self = self else { return }
            self.logger.info("push: starting executeOperationBackground")
            await self.executeOperationBackground(
                {
                    self.logger.info("push: executing remoteService.push")
                    try await remoteService.push(at: worktreePath, setUpstream: setUpstream)
                    self.logger.info("push: remoteService.push completed")
                },
                onSuccess: { [weak self] in
                    guard let self = self else {
                        await MainActor.run { onSuccess?() }
                        return
                    }
                    self.logger.info("push onSuccess: calling reloadStatusInternal")
                    await self.reloadStatusInternal()
                    self.logger.info("push onSuccess: reloadStatusInternal completed, calling callback")
                    await MainActor.run {
                        onSuccess?()
                        self.logger.info("push onSuccess: callback completed")
                    }
                },
                onError: { error in
                    self.logger.error("push failed: \(error.localizedDescription)")
                    onError?(error)
                }
            )
        }
    }

    /// Combined fetch-then-push operation that keeps isOperationPending true throughout
    /// Returns true if push was performed, false if blocked due to remote being ahead
    func fetchThenPush(setUpstream: Bool = false, onSuccess: ((Bool) -> Void)? = nil, onError: ((Error) -> Void)? = nil) {
        logger.info("GitRepositoryService.fetchThenPush() called")
        let worktreePath = self.worktreePath
        let remoteService = self.remoteService
        Task.detached { [weak self] in
            guard let self = self else { return }
            self.logger.info("fetchThenPush: starting executeOperationBackground")
            await self.executeOperationBackground(
                {
                    // First, fetch to get remote state
                    self.logger.info("fetchThenPush: executing fetch")
                    try await remoteService.fetch(at: worktreePath)
                    self.logger.info("fetchThenPush: fetch completed")
                },
                onSuccess: { [weak self] in
                    guard let self = self else {
                        await MainActor.run { onSuccess?(false) }
                        return
                    }
                    // Check behind/ahead without doing a full status reload (diffStats/status can be heavy on large repos)
                    let behindCount: Int
                    do {
                        let branchStatus = try await self.statusService.getBranchStatus(at: worktreePath)
                        behindCount = branchStatus.behind
                    } catch {
                        behindCount = 0
                    }

                    if behindCount > 0 {
                        self.logger.warning("fetchThenPush: Remote has \(behindCount) commits ahead, blocking push")
                        await MainActor.run { onSuccess?(false) }
                        return
                    }

                    // Proceed with push
                    self.logger.info("fetchThenPush: proceeding with push")
                    do {
                        try await remoteService.push(at: worktreePath, setUpstream: setUpstream)
                        self.logger.info("fetchThenPush: push completed")
                        await self.reloadStatusInternal()
                        await MainActor.run { onSuccess?(true) }
                    } catch {
                        self.logger.error("fetchThenPush: push failed - \(error.localizedDescription)")
                        await MainActor.run { onError?(error) }
                    }
                },
                onError: { [weak self] error in
                    self?.logger.error("fetchThenPush: fetch failed - \(error.localizedDescription)")
                    onError?(error)
                }
            )
        }
    }

    // MARK: - Status Loading

    func reloadStatus(lightweight: Bool = false) {
        Task { @MainActor [weak self] in
            self?.reloadStatusDebouncedOnMain(lightweight: lightweight)
        }
    }

    func updateWorktreePath(_ newPath: String) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard newPath != self.worktreePath else { return }
            self.worktreePath = newPath
            self.currentStatus = .empty
            self.reloadStatusDebouncedOnMain(lightweight: true)
        }
    }

    // MARK: - Private Methods

    private func makeRefreshingSuccessHandler(original: (() -> Void)?) -> () async -> Void {
        return { [weak self] in
            guard let self = self else {
                await MainActor.run { original?() }
                return
            }
            await self.reloadStatusNow(lightweight: false)
            await MainActor.run {
                original?()
            }
        }
    }

    private func executeOperationBackground(_ operation: @escaping () async throws -> Void, onSuccess: (() async -> Void)? = nil, onError: ((Error) -> Void)? = nil) async {
        await MainActor.run {
            self.isOperationPending = true
        }

        do {
            try await operation()

            // Await the async success handler before marking operation complete
            if let onSuccess = onSuccess {
                await onSuccess()
            }
        } catch {
            await MainActor.run {
                onError?(error)
            }
        }

        await MainActor.run {
            self.isOperationPending = false
        }
    }

    private func reloadStatusInternal() async {
        await reloadStatusNow(lightweight: false)
    }

    nonisolated
    private func loadGitStatus(at path: String, lightweight: Bool) async throws -> GitStatus {
        let detailedStatus = try await statusService.getDetailedStatus(
            at: path,
            includeUntracked: !lightweight,
            includeDiffStats: !lightweight
        )

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

    private func reloadStatusNow(lightweight: Bool) async {
        let task = await MainActor.run { () -> Task<Void, Never>? in
            statusReloadTask?.cancel()
            isStatusReloadPending = false
            pendingReloadIsLightweight = true

            let path = worktreePath

            inFlightStatusTask?.cancel()
            let task = Task(priority: .utility) { [weak self] in
                guard let self else { return }
                do {
                    let status = try await self.loadGitStatus(at: path, lightweight: lightweight)
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        // Guard against path changes while loading (e.g. worktree switch).
                        guard self.worktreePath == path else { return }
                        self.currentStatus = status
                    }
                } catch {
                    self.logger.error("Failed to reload Git status for \(path): \(error)")
                }
            }
            inFlightStatusTask = task
            return task
        }
        await task?.value
    }

    @MainActor
    private func reloadStatusDebouncedOnMain(lightweight: Bool) {
        if isStatusReloadPending {
            // Upgrade pending lightweight reload to full if requested.
            if pendingReloadIsLightweight && !lightweight {
                pendingReloadIsLightweight = false
            }
            return
        }

        isStatusReloadPending = true
        pendingReloadIsLightweight = lightweight

        statusReloadTask?.cancel()
        statusReloadTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: .seconds(self.statusReloadDebounceInterval))
            } catch {
                return
            }

            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.isStatusReloadPending = false
            }
            let doLightweight = await MainActor.run { self.pendingReloadIsLightweight }
            await self.reloadStatusNow(lightweight: doLightweight)
        }
    }

}
