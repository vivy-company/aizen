//
//  GitOperationService.swift
//  aizen
//
//  Stateless-ish Git mutation service for a single worktree path.
//

import Combine
import Foundation
import os.log

@MainActor
final class GitOperationService: ObservableObject {
    @Published private(set) var isOperationPending = false

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen.app", category: "GitOperationService")

    private let stagingService = GitStagingService()
    private let branchService = GitBranchService()
    private let remoteService = GitRemoteService()
    private let statusService = GitStatusService()

    private let worktreePath: String
    private let onMutationCompleted: @MainActor () -> Void

    init(worktreePath: String, onMutationCompleted: @escaping @MainActor () -> Void) {
        self.worktreePath = worktreePath
        self.onMutationCompleted = onMutationCompleted
    }

    // MARK: - Staging Operations

    func stageFile(_ file: String, onSuccess: (() -> Void)? = nil, onError: ((Error) -> Void)? = nil) {
        let worktreePath = self.worktreePath
        let stagingService = self.stagingService
        Task.detached { [weak self] in
            guard let self else { return }
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
            guard let self else { return }
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
            guard let self else { return }
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
            guard let self else { return }
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
            guard let self else { return }
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
            guard let self else { return }
            await self.executeOperationBackground(
                { try await stagingService.cleanUntracked(at: worktreePath) },
                onSuccess: self.makeRefreshingSuccessHandler(original: onSuccess),
                onError: onError
            )
        }
    }

    // MARK: - Commit Operations

    func commit(message: String, onSuccess: (() -> Void)? = nil, onError: ((Error) -> Void)? = nil) {
        let worktreePath = self.worktreePath
        let stagingService = self.stagingService
        Task.detached { [weak self] in
            guard let self else { return }
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
            guard let self else { return }
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
            guard let self else { return }
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
            guard let self else { return }
            await self.executeOperationBackground(
                { try await branchService.checkoutBranch(at: worktreePath, branch: branch) },
                onSuccess: self.makeMutationOnlySuccessHandler(),
                onError: onError
            )
        }
    }

    func createBranch(_ name: String, from: String? = nil, onError: ((Error) -> Void)? = nil) {
        let worktreePath = self.worktreePath
        let branchService = self.branchService
        Task.detached { [weak self] in
            guard let self else { return }
            await self.executeOperationBackground(
                { try await branchService.createBranch(at: worktreePath, name: name, from: from) },
                onSuccess: self.makeMutationOnlySuccessHandler(),
                onError: onError
            )
        }
    }

    // MARK: - Remote Operations

    func fetch(onSuccess: (() -> Void)? = nil, onError: ((Error) -> Void)? = nil) {
        let worktreePath = self.worktreePath
        let remoteService = self.remoteService
        Task.detached { [weak self] in
            guard let self else { return }
            await self.executeOperationBackground(
                { try await remoteService.fetch(at: worktreePath) },
                onSuccess: self.makeRefreshingSuccessHandler(original: onSuccess),
                onError: onError
            )
        }
    }

    func pull(onSuccess: (() -> Void)? = nil, onError: ((Error) -> Void)? = nil) {
        let worktreePath = self.worktreePath
        let remoteService = self.remoteService
        Task.detached { [weak self] in
            guard let self else { return }
            await self.executeOperationBackground(
                { try await remoteService.pull(at: worktreePath) },
                onSuccess: self.makeRefreshingSuccessHandler(original: onSuccess),
                onError: onError
            )
        }
    }

    func push(setUpstream: Bool = false, onSuccess: (() -> Void)? = nil, onError: ((Error) -> Void)? = nil) {
        let worktreePath = self.worktreePath
        let remoteService = self.remoteService
        Task.detached { [weak self] in
            guard let self else { return }
            await self.executeOperationBackground(
                { try await remoteService.push(at: worktreePath, setUpstream: setUpstream) },
                onSuccess: self.makeRefreshingSuccessHandler(original: onSuccess),
                onError: onError
            )
        }
    }

    func fetchThenPush(setUpstream: Bool = false, onSuccess: ((Bool) -> Void)? = nil, onError: ((Error) -> Void)? = nil) {
        let worktreePath = self.worktreePath
        let remoteService = self.remoteService
        let statusService = self.statusService
        Task.detached { [weak self] in
            guard let self else { return }
            await self.executeOperationBackground(
                { try await remoteService.fetch(at: worktreePath) },
                onSuccess: {
                    let behindCount: Int
                    do {
                        let branchStatus = try await statusService.getBranchStatus(at: worktreePath)
                        behindCount = branchStatus.behind
                    } catch {
                        behindCount = 0
                    }

                    if behindCount > 0 {
                        await MainActor.run { onSuccess?(false) }
                        return
                    }

                    do {
                        try await remoteService.push(at: worktreePath, setUpstream: setUpstream)
                        await MainActor.run {
                            self.onMutationCompleted()
                            onSuccess?(true)
                        }
                    } catch {
                        await MainActor.run {
                            onError?(error)
                        }
                    }
                },
                onError: onError
            )
        }
    }

    // MARK: - Helpers

    private func makeRefreshingSuccessHandler(original: (() -> Void)?) -> () async -> Void {
        return { [weak self] in
            guard let self else {
                await MainActor.run { original?() }
                return
            }
            await MainActor.run {
                self.onMutationCompleted()
                original?()
            }
        }
    }

    private func makeMutationOnlySuccessHandler() -> () async -> Void {
        return { [weak self] in
            guard let self else { return }
            await MainActor.run {
                self.onMutationCompleted()
            }
        }
    }

    private func executeOperationBackground(
        _ operation: @escaping () async throws -> Void,
        onSuccess: (() async -> Void)? = nil,
        onError: ((Error) -> Void)? = nil
    ) async {
        await MainActor.run {
            self.isOperationPending = true
        }

        do {
            try await operation()
            if let onSuccess {
                await onSuccess()
            }
        } catch {
            await MainActor.run {
                onError?(error)
            }
            logger.error("Git operation failed: \(error.localizedDescription)")
        }

        await MainActor.run {
            self.isOperationPending = false
        }
    }
}
