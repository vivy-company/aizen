import Foundation
import os.log

@MainActor
extension PullRequestsViewModel {
    // MARK: - Actions

    func merge(method: PRMergeMethod) async {
        guard let pr = selectedPR else { return }

        isPerformingAction = true
        actionError = nil

        do {
            try await hostingService.mergePullRequestWithMethod(
                repoPath: repoPath,
                number: pr.number,
                method: method
            )
            await refresh()
        } catch {
            logger.error("Failed to merge PR: \(error.localizedDescription)")
            actionError = error.localizedDescription
        }

        isPerformingAction = false
    }

    func close() async {
        guard let pr = selectedPR else { return }

        isPerformingAction = true
        actionError = nil

        do {
            try await hostingService.closePullRequest(repoPath: repoPath, number: pr.number)
            await refresh()
        } catch {
            logger.error("Failed to close PR: \(error.localizedDescription)")
            actionError = error.localizedDescription
        }

        isPerformingAction = false
    }

}
