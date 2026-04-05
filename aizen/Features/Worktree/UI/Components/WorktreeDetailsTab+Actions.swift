import SwiftUI
import os

extension DetailsTabView {
    func refreshStatus() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let status = try await repositoryManager.getWorktreeStatus(worktree)
                await MainActor.run {
                    currentBranch = status.branch
                    ahead = status.ahead
                    behind = status.behind
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }

    func openInTerminal() {
        guard let path = worktree.path else { return }
        repositoryManager.openInTerminal(path)
        updateLastAccessed()
    }

    func openInFinder() {
        guard let path = worktree.path else { return }
        repositoryManager.openInFinder(path)
        updateLastAccessed()
    }

    func openInEditor() {
        guard let path = worktree.path else { return }
        repositoryManager.openInEditor(path)
        updateLastAccessed()
    }

    func checkUnsavedChanges() {
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
                guard let repository = worktree.repository else { return }
                let allWorktrees = ((repository.worktrees as? Set<Worktree>) ?? []).sorted { wt1, wt2 in
                    if wt1.isPrimary != wt2.isPrimary {
                        return wt1.isPrimary
                    }
                    return (wt1.branch ?? "") < (wt2.branch ?? "")
                }

                let nextWorktree: Worktree?
                if let currentIndex = allWorktrees.firstIndex(where: { $0.id == worktree.id }) {
                    if currentIndex + 1 < allWorktrees.count {
                        nextWorktree = allWorktrees[currentIndex + 1]
                    } else if currentIndex > 0 {
                        nextWorktree = allWorktrees[currentIndex - 1]
                    } else {
                        nextWorktree = nil
                    }
                } else {
                    nextWorktree = nil
                }

                try await repositoryManager.deleteWorktree(worktree, force: hasUnsavedChanges)

                await MainActor.run {
                    onWorktreeDeleted?(nextWorktree)
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    func updateLastAccessed() {
        do {
            try repositoryManager.updateWorktreeAccess(worktree)
        } catch {
            logger.error("Failed to update last accessed: \(error.localizedDescription)")
        }
    }
}
