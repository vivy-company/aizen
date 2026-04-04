import Foundation
import os.log

@MainActor
extension PullRequestsViewModel {
    // MARK: - List Operations

    func loadPullRequests() async {
        guard !isLoadingList else { return }

        isLoadingList = true
        listError = nil
        currentPage = 1

        do {
            let prs = try await hostingService.listPullRequests(
                repoPath: repoPath,
                filter: filter,
                page: currentPage,
                limit: pageSize
            )
            pullRequests = prs
            hasMore = prs.count >= pageSize

            if selectedPR == nil, let first = prs.first {
                selectedPR = first
                await loadDetail(for: first)
            }
        } catch {
            logger.error("Failed to load PRs: \(error.localizedDescription)")
            listError = error.localizedDescription
            pullRequests = []
        }

        isLoadingList = false
    }

    func loadMore() async {
        guard !isLoadingList, hasMore else { return }

        isLoadingList = true
        currentPage += 1

        do {
            let prs = try await hostingService.listPullRequests(
                repoPath: repoPath,
                filter: filter,
                page: currentPage,
                limit: pageSize
            )

            let existingIds = Set(pullRequests.map(\.id))
            let newPRs = prs.filter { !existingIds.contains($0.id) }

            pullRequests.append(contentsOf: newPRs)
            hasMore = prs.count >= pageSize
        } catch {
            logger.error("Failed to load more PRs: \(error.localizedDescription)")
            currentPage -= 1
        }

        isLoadingList = false
    }

    func refresh() async {
        currentPage = 1
        await loadPullRequests()

        if let pr = selectedPR {
            await loadDetail(for: pr)
        }
    }

    func changeFilter(to newFilter: PRFilter) {
        guard filter != newFilter else { return }
        filter = newFilter
        Task {
            await loadPullRequests()
        }
    }
}
