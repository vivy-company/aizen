import SwiftUI

extension GitHistoryView {
    func loadCommits() async {
        isLoading = true
        errorMessage = nil

        do {
            let newCommits = try await logService.getCommitHistory(at: worktreePath, limit: pageSize, skip: 0)
            commits = newCommits
            hasMoreCommits = newCommits.count == pageSize
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func loadMoreCommits() async {
        guard !isLoadingMore && hasMoreCommits else { return }

        isLoadingMore = true

        do {
            let newCommits = try await logService.getCommitHistory(at: worktreePath, limit: pageSize, skip: commits.count)
            commits.append(contentsOf: newCommits)
            hasMoreCommits = newCommits.count == pageSize
        } catch {
            // Silently fail for load more - don't show error
        }

        isLoadingMore = false
    }

    func refresh() async {
        commits = []
        hasMoreCommits = true
        await loadCommits()
    }
}
