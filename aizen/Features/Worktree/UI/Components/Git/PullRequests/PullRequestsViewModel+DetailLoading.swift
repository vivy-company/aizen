import Foundation
import os.log

@MainActor
extension PullRequestsViewModel {
    // MARK: - Detail Operations

    func selectPR(_ pr: PullRequest) {
        guard selectedPR?.id != pr.id else { return }
        selectedPR = pr
        Task {
            await loadDetail(for: pr)
        }
    }

    func loadDetail(for pr: PullRequest) async {
        detailError = nil
        comments = []
        diffOutput = ""

        do {
            let updatedPR = try await hostingService.getPullRequestDetail(
                repoPath: repoPath,
                number: pr.number
            )
            if selectedPR?.id == pr.id {
                selectedPR = updatedPR
            }
        } catch {
            logger.error("Failed to refresh PR detail: \(error.localizedDescription)")
        }
    }

    func loadCommentsIfNeeded() async {
        guard let pr = selectedPR, comments.isEmpty, !isLoadingComments else { return }
        await loadComments(for: pr)
    }

    func loadDiffIfNeeded() async {
        guard let pr = selectedPR, diffOutput.isEmpty, !isLoadingDiff else { return }
        await loadDiff(for: pr)
    }

    func loadComments(for pr: PullRequest) async {
        isLoadingComments = true
        do {
            comments = try await hostingService.getPullRequestComments(
                repoPath: repoPath,
                number: pr.number
            )
        } catch {
            logger.error("Failed to load comments: \(error.localizedDescription)")
            comments = []
        }
        isLoadingComments = false
    }

    func loadDiff(for pr: PullRequest) async {
        isLoadingDiff = true
        do {
            diffOutput = try await hostingService.getPullRequestDiff(
                repoPath: repoPath,
                number: pr.number
            )
        } catch {
            logger.error("Failed to load diff: \(error.localizedDescription)")
            diffOutput = ""
        }
        isLoadingDiff = false
    }
}
