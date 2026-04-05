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

}
