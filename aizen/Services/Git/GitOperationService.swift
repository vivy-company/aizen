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
    private let operationRunner = GitOperationRunner()

    private let worktreePath: String
    private let onMutationCompleted: @MainActor () -> Void

    init(worktreePath: String, onMutationCompleted: @escaping @MainActor () -> Void) {
        self.worktreePath = worktreePath
        self.onMutationCompleted = onMutationCompleted
    }

    // MARK: - Staging Operations

    func stageFile(_ file: String, onSuccess: (() -> Void)? = nil, onError: ((Error) -> Void)? = nil) {
        let worktreePath = self.worktreePath
        let operationRunner = self.operationRunner
        enqueueOperation(
            { try await operationRunner.stageFile(at: worktreePath, file: file) },
            onSuccess: makeRefreshingSuccessHandler(original: onSuccess),
            onError: onError
        )
    }

    func unstageFile(_ file: String, onSuccess: (() -> Void)? = nil, onError: ((Error) -> Void)? = nil) {
        let worktreePath = self.worktreePath
        let operationRunner = self.operationRunner
        enqueueOperation(
            { try await operationRunner.unstageFile(at: worktreePath, file: file) },
            onSuccess: makeRefreshingSuccessHandler(original: onSuccess),
            onError: onError
        )
    }

    func stageAll(onSuccess: (() -> Void)? = nil, onError: ((Error) -> Void)? = nil) {
        let worktreePath = self.worktreePath
        let operationRunner = self.operationRunner
        enqueueOperation(
            { try await operationRunner.stageAll(at: worktreePath) },
            onSuccess: makeRefreshingSuccessHandler(original: onSuccess),
            onError: onError
        )
    }

    func unstageAll(onSuccess: (() -> Void)? = nil, onError: ((Error) -> Void)? = nil) {
        let worktreePath = self.worktreePath
        let operationRunner = self.operationRunner
        enqueueOperation(
            { try await operationRunner.unstageAll(at: worktreePath) },
            onSuccess: makeRefreshingSuccessHandler(original: onSuccess),
            onError: onError
        )
    }

    func discardAll(onSuccess: (() -> Void)? = nil, onError: ((Error) -> Void)? = nil) {
        let worktreePath = self.worktreePath
        let operationRunner = self.operationRunner
        enqueueOperation(
            { try await operationRunner.discardAll(at: worktreePath) },
            onSuccess: makeRefreshingSuccessHandler(original: onSuccess),
            onError: onError
        )
    }

    func cleanUntracked(onSuccess: (() -> Void)? = nil, onError: ((Error) -> Void)? = nil) {
        let worktreePath = self.worktreePath
        let operationRunner = self.operationRunner
        enqueueOperation(
            { try await operationRunner.cleanUntracked(at: worktreePath) },
            onSuccess: makeRefreshingSuccessHandler(original: onSuccess),
            onError: onError
        )
    }

    // MARK: - Commit Operations

    func commit(message: String, onSuccess: (() -> Void)? = nil, onError: ((Error) -> Void)? = nil) {
        let worktreePath = self.worktreePath
        let operationRunner = self.operationRunner
        enqueueOperation(
            { try await operationRunner.commit(at: worktreePath, message: message) },
            onSuccess: makeRefreshingSuccessHandler(original: onSuccess),
            onError: onError
        )
    }

    func amendCommit(message: String, onSuccess: (() -> Void)? = nil, onError: ((Error) -> Void)? = nil) {
        let worktreePath = self.worktreePath
        let operationRunner = self.operationRunner
        enqueueOperation(
            { try await operationRunner.amendCommit(at: worktreePath, message: message) },
            onSuccess: makeRefreshingSuccessHandler(original: onSuccess),
            onError: onError
        )
    }

    func commitWithSignoff(message: String, onSuccess: (() -> Void)? = nil, onError: ((Error) -> Void)? = nil) {
        let worktreePath = self.worktreePath
        let operationRunner = self.operationRunner
        enqueueOperation(
            { try await operationRunner.commitWithSignoff(at: worktreePath, message: message) },
            onSuccess: makeRefreshingSuccessHandler(original: onSuccess),
            onError: onError
        )
    }

    // MARK: - Branch Operations

    func checkoutBranch(_ branch: String, onError: ((Error) -> Void)? = nil) {
        let worktreePath = self.worktreePath
        let operationRunner = self.operationRunner
        enqueueOperation(
            { try await operationRunner.checkoutBranch(at: worktreePath, branch: branch) },
            onSuccess: makeMutationOnlySuccessHandler(),
            onError: onError
        )
    }

    func createBranch(_ name: String, from: String? = nil, onError: ((Error) -> Void)? = nil) {
        let worktreePath = self.worktreePath
        let operationRunner = self.operationRunner
        enqueueOperation(
            { try await operationRunner.createBranch(at: worktreePath, name: name, from: from) },
            onSuccess: makeMutationOnlySuccessHandler(),
            onError: onError
        )
    }

    // MARK: - Remote Operations

    func fetch(onSuccess: (() -> Void)? = nil, onError: ((Error) -> Void)? = nil) {
        let worktreePath = self.worktreePath
        let operationRunner = self.operationRunner
        enqueueOperation(
            { try await operationRunner.fetch(at: worktreePath) },
            onSuccess: makeRefreshingSuccessHandler(original: onSuccess),
            onError: onError
        )
    }

    func pull(onSuccess: (() -> Void)? = nil, onError: ((Error) -> Void)? = nil) {
        let worktreePath = self.worktreePath
        let operationRunner = self.operationRunner
        enqueueOperation(
            { try await operationRunner.pull(at: worktreePath) },
            onSuccess: makeRefreshingSuccessHandler(original: onSuccess),
            onError: onError
        )
    }

    func push(setUpstream: Bool = false, onSuccess: (() -> Void)? = nil, onError: ((Error) -> Void)? = nil) {
        let worktreePath = self.worktreePath
        let operationRunner = self.operationRunner
        enqueueOperation(
            { try await operationRunner.push(at: worktreePath, setUpstream: setUpstream) },
            onSuccess: makeRefreshingSuccessHandler(original: onSuccess),
            onError: onError
        )
    }

    func fetchThenPush(setUpstream: Bool = false, onSuccess: ((Bool) -> Void)? = nil, onError: ((Error) -> Void)? = nil) {
        let worktreePath = self.worktreePath
        let operationRunner = self.operationRunner
        enqueueOperation(
            { try await operationRunner.fetchThenPush(at: worktreePath, setUpstream: setUpstream) },
            onSuccess: { [weak self] didPush in
                guard let self else { return }
                await MainActor.run {
                    if didPush {
                        self.onMutationCompleted()
                    }
                    onSuccess?(didPush)
                }
            },
            onError: onError
        )
    }

    // MARK: - Helpers

    private func makeRefreshingSuccessHandler(original: (() -> Void)?) -> (() async -> Void) {
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

    private func makeMutationOnlySuccessHandler() -> (() async -> Void) {
        return { [weak self] in
            guard let self else { return }
            await MainActor.run {
                self.onMutationCompleted()
            }
        }
    }

    private func enqueueOperation<T>(
        _ operation: @escaping () async throws -> T,
        onSuccess: ((T) async -> Void)? = nil,
        onError: ((Error) -> Void)? = nil
    ) {
        Task { [weak self] in
            guard let self else { return }
            await self.executeOperationBackground(operation, onSuccess: onSuccess, onError: onError)
        }
    }

    private func executeOperationBackground<T>(
        _ operation: @escaping () async throws -> T,
        onSuccess: ((T) async -> Void)? = nil,
        onError: ((Error) -> Void)? = nil
    ) async {
        await MainActor.run {
            self.isOperationPending = true
        }

        do {
            let result = try await operation()
            if let onSuccess {
                await onSuccess(result)
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
