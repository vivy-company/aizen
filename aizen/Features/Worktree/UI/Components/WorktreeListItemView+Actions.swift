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

}
