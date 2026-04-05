import os.log
import SwiftUI

extension WorktreeListItemView {
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
