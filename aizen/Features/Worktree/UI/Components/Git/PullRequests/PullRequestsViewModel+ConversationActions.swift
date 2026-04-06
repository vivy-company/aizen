import Foundation
import os.log

@MainActor
extension PullRequestsViewModel {
    func approve(body: String? = nil) async {
        guard let pr = selectedPR else { return }

        isPerformingAction = true
        actionError = nil

        do {
            try await hostingService.approvePullRequest(
                repoPath: repoPath,
                number: pr.number,
                body: body
            )
            await loadDetail(for: pr)
            await loadComments(for: pr)
        } catch {
            logger.error("Failed to approve PR: \(error.localizedDescription)")
            actionError = error.localizedDescription
        }

        isPerformingAction = false
    }

    func requestChanges(body: String) async {
        guard let pr = selectedPR else { return }

        isPerformingAction = true
        actionError = nil

        do {
            try await hostingService.requestChanges(
                repoPath: repoPath,
                number: pr.number,
                body: body
            )
            await loadDetail(for: pr)
            await loadComments(for: pr)
        } catch {
            logger.error("Failed to request changes: \(error.localizedDescription)")
            actionError = error.localizedDescription
        }

        isPerformingAction = false
    }

    func addComment(body: String) async {
        guard let pr = selectedPR else { return }

        isPerformingAction = true
        actionError = nil

        do {
            try await hostingService.addPullRequestComment(
                repoPath: repoPath,
                number: pr.number,
                body: body
            )
            await loadComments(for: pr)
        } catch {
            logger.error("Failed to add comment: \(error.localizedDescription)")
            actionError = error.localizedDescription
        }

        isPerformingAction = false
    }

    func submitConversationAction(_ action: ConversationAction, body: String) async {
        guard let pr = selectedPR else { return }

        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let requiresBody = action == .comment || action == .requestChanges
        if requiresBody && trimmedBody.isEmpty {
            return
        }

        isPerformingAction = true
        actionError = nil

        do {
            switch action {
            case .comment:
                try await hostingService.addPullRequestComment(
                    repoPath: repoPath,
                    number: pr.number,
                    body: trimmedBody
                )

            case .approve:
                try await hostingService.approvePullRequest(
                    repoPath: repoPath,
                    number: pr.number,
                    body: trimmedBody.isEmpty ? nil : trimmedBody
                )
                if !trimmedBody.isEmpty, hostingInfo?.provider == .gitlab {
                    try await hostingService.addPullRequestComment(
                        repoPath: repoPath,
                        number: pr.number,
                        body: trimmedBody
                    )
                }

            case .requestChanges:
                try await hostingService.requestChanges(
                    repoPath: repoPath,
                    number: pr.number,
                    body: trimmedBody
                )
            }

            await loadDetail(for: pr)
            await loadComments(for: pr)
        } catch {
            logger.error("Failed to submit conversation action: \(error.localizedDescription)")
            actionError = error.localizedDescription
        }

        isPerformingAction = false
    }
}
