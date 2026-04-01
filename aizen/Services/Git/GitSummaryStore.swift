//
//  GitSummaryStore.swift
//  aizen
//
//  Shared observable Git summary state for a worktree.
//

import Combine
import Foundation
import os.log

@MainActor
final class GitSummaryStore: ObservableObject {
    enum RefreshTier {
        case summary
        case full
    }

    @Published private(set) var currentStatus: GitStatus = .empty
    @Published private(set) var repositoryState: GitRepositoryState = .unknown
    @Published private(set) var isRefreshing = false
    @Published private(set) var isStale = true
    @Published private(set) var lastRefreshAt: Date?

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen.app", category: "GitSummaryStore")
    private let statusService = GitStatusService()
    private let worktreePath: String

    private var refreshTask: Task<Void, Never>?
    private var inFlightTask: Task<DetailedGitStatus, Error>?
    private var pendingTier: RefreshTier = .summary
    private let debounceInterval: Duration = .milliseconds(300)

    init(worktreePath: String) {
        self.worktreePath = worktreePath
    }

    var status: GitStatus {
        currentStatus
    }

    func markStale() {
        isStale = true
    }

    func refresh(reason: String, tier: RefreshTier = .summary, force: Bool = false) {
        if force {
            refreshTask?.cancel()
            refreshTask = nil
            pendingTier = tier
            Task { [weak self] in
                await self?.reloadNow(reason: reason, tier: tier)
            }
            return
        }

        if pendingTier == .summary, tier == .full {
            pendingTier = .full
        } else if refreshTask == nil {
            pendingTier = tier
        }

        guard refreshTask == nil else { return }

        refreshTask = Task { [weak self] in
            guard let self else { return }
            defer { self.refreshTask = nil }

            do {
                try await Task.sleep(for: self.debounceInterval)
            } catch {
                return
            }

            guard !Task.isCancelled else { return }
            let scheduledTier = self.pendingTier
            self.pendingTier = .summary
            await self.reloadNow(reason: reason, tier: scheduledTier)
        }
    }

    private func reloadNow(reason: String, tier: RefreshTier) async {
        inFlightTask?.cancel()
        isRefreshing = true

        let path = worktreePath
        let task = Task(priority: .utility) { [statusService] in
            try await statusService.getDetailedStatus(
                at: path,
                includeUntracked: true,
                includeDiffStats: tier == .full
            )
        }
        inFlightTask = task

        do {
            let detailedStatus = try await task.value
            guard !Task.isCancelled else { return }

            let nextStatus = GitStatus(
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

            if currentStatus != nextStatus {
                currentStatus = nextStatus
            }
            if repositoryState != .ready {
                repositoryState = .ready
            }
            isRefreshing = false
            isStale = false
            lastRefreshAt = Date()
        } catch {
            guard !Task.isCancelled else { return }
            currentStatus = .empty

            let nextState: GitRepositoryState
            if let gitError = error as? Libgit2Error {
                switch gitError {
                case .notARepository:
                    nextState = .notRepository
                case .repositoryPathMissing:
                    nextState = .missingPath
                default:
                    nextState = .error(gitError.localizedDescription)
                }
            } else {
                nextState = .error(error.localizedDescription)
            }

            if repositoryState != nextState {
                repositoryState = nextState
            }
            isRefreshing = false
            isStale = false
            lastRefreshAt = Date()
            logger.error("Git summary refresh failed for \(path) (\(reason)): \(error.localizedDescription)")
        }
    }
}
