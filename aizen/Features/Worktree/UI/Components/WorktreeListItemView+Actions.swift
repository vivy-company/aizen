import os.log
import SwiftUI

extension WorktreeListItemView {
    func setWorktreeStatus(_ status: ItemStatus) {
        do {
            try repositoryManager.updateWorktreeStatus(worktree, status: status)
        } catch {
            logger.error("Failed to update worktree status: \(error.localizedDescription)")
        }
    }

    func checkUnsavedChanges() {
        guard isGitEnvironment else {
            hasUnsavedChanges = false
            showingDeleteConfirmation = true
            return
        }

        Task {
            do {
                let changes = try await repositoryManager.hasUnsavedChanges(worktree)
                await MainActor.run {
                    hasUnsavedChanges = changes
                    showingDeleteConfirmation = true
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    func deleteWorktree() {
        Task {
            do {
                if let currentIndex = allWorktrees.firstIndex(where: { $0.id == worktree.id }) {
                    let nextWorktree: Worktree?

                    if currentIndex + 1 < allWorktrees.count {
                        nextWorktree = allWorktrees[currentIndex + 1]
                    } else if currentIndex > 0 {
                        nextWorktree = allWorktrees[currentIndex - 1]
                    } else {
                        nextWorktree = nil
                    }

                    try await repositoryManager.deleteWorktree(worktree, force: hasUnsavedChanges)

                    await MainActor.run {
                        selectedWorktree = nextWorktree
                    }
                } else {
                    try await repositoryManager.deleteWorktree(worktree, force: hasUnsavedChanges)
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    func loadWorktreeStatuses() {
        guard supportsMergeOperations else {
            worktreeStatuses = []
            return
        }
        guard !isLoadingStatuses else { return }

        Task {
            await MainActor.run {
                isLoadingStatuses = true
            }

            var statuses: [WorktreeStatusInfo] = []

            for wt in allWorktrees {
                if wt.isIndependentEnvironment {
                    continue
                }
                guard let path = wt.path, GitUtils.isGitRepository(at: path) else {
                    continue
                }
                do {
                    let hasChanges = try await repositoryManager.hasUnsavedChanges(wt)
                    let branch = wt.branch ?? "unknown"
                    statuses.append(
                        WorktreeStatusInfo(
                            worktree: wt,
                            hasUncommittedChanges: hasChanges,
                            branch: branch
                        )
                    )
                } catch {
                    continue
                }
            }

            await MainActor.run {
                worktreeStatuses = statuses
                isLoadingStatuses = false
            }
        }
    }

    func performMerge(from source: Worktree, to target: Worktree) {
        guard supportsMergeOperations else { return }
        Task {
            do {
                let result = try await repositoryManager.mergeFromWorktree(target: target, source: source)

                await MainActor.run {
                    switch result {
                    case .success:
                        mergeSuccessMessage = "Successfully merged \(source.branch ?? "unknown") into \(target.branch ?? "unknown")"
                        showingMergeSuccess = true
                    case .conflict(let files):
                        mergeConflictFiles = files
                        showingMergeConflict = true
                    case .alreadyUpToDate:
                        mergeSuccessMessage = "Already up to date with \(source.branch ?? "unknown")"
                        showingMergeSuccess = true
                    }

                    loadWorktreeStatuses()
                }
            } catch {
                await MainActor.run {
                    mergeErrorMessage = error.localizedDescription
                }
            }
        }
    }

    func loadAvailableBranches() {
        guard supportsBranchOperations else {
            availableBranches = []
            return
        }
        guard !isLoadingBranches else { return }

        Task {
            await MainActor.run {
                isLoadingBranches = true
            }

            do {
                guard let repo = worktree.repository else {
                    logger.warning("Cannot load branches: worktree has no repository")
                    await MainActor.run { isLoadingBranches = false }
                    return
                }
                let branches = try await repositoryManager.getBranches(for: repo)

                await MainActor.run {
                    let localBranches = branches
                        .filter { !$0.isRemote && $0.name != worktree.branch }
                        .prefix(5)

                    let remoteBranches = branches
                        .filter { $0.isRemote }
                        .prefix(3)

                    availableBranches = Array(localBranches) + Array(remoteBranches)
                    isLoadingBranches = false
                }
            } catch {
                logger.error("Failed to load available branches: \(error.localizedDescription)")
                await MainActor.run { isLoadingBranches = false }
            }
        }
    }

    func switchToBranch(_ branch: BranchInfo) {
        guard supportsBranchOperations else { return }
        Task {
            do {
                if branch.isRemote {
                    let localName = branch.name.split(separator: "/").dropFirst().joined(separator: "/")
                    try await repositoryManager.createAndSwitchBranch(
                        worktree,
                        name: localName,
                        from: branch.name
                    )
                } else {
                    try await repositoryManager.switchBranch(worktree, to: branch.name)
                }

                await MainActor.run {
                    loadAvailableBranches()
                }
            } catch {
                await MainActor.run {
                    branchSwitchError = error.localizedDescription
                }
            }
        }
    }

    func createNewBranch(name: String) {
        guard supportsBranchOperations else { return }
        Task {
            do {
                guard let currentBranch = worktree.branch else {
                    throw Libgit2Error.branchNotFound("No current branch")
                }

                try await repositoryManager.createAndSwitchBranch(
                    worktree,
                    name: name,
                    from: currentBranch
                )

                await MainActor.run {
                    loadAvailableBranches()
                }
            } catch {
                await MainActor.run {
                    branchSwitchError = error.localizedDescription
                }
            }
        }
    }
}
