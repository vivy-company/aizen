import os.log
import SwiftUI

extension WorktreeListItemView {
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
