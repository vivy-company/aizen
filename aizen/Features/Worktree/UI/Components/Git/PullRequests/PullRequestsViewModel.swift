//
//  PullRequestsViewModel.swift
//  aizen
//
//  ViewModel for managing PR list and detail state
//

import Foundation
import SwiftUI
import Combine
import AppKit
import os.log

@MainActor
class PullRequestsViewModel: ObservableObject {
    enum ConversationAction: String, CaseIterable {
        case comment
        case approve
        case requestChanges
    }

    // MARK: - List State

    @Published var pullRequests: [PullRequest] = []
    @Published var selectedPR: PullRequest?
    @Published var filter: PRFilter = .open
    @Published var isLoadingList = false
    @Published var hasMore = true
    @Published var listError: String?

    // MARK: - Detail State

    @Published var comments: [PRComment] = []
    @Published var diffOutput: String = ""
    @Published var isLoadingComments = false
    @Published var isLoadingDiff = false
    @Published var detailError: String?

    // MARK: - Action State

    @Published var isPerformingAction = false
    @Published var actionError: String?
    @Published var showMergeOptions = false

    // MARK: - Hosting Info

    @Published var hostingInfo: GitHostingInfo?

    // MARK: - Private

    let hostingService = GitHostingService.shared
    var repoPath: String = ""
    var currentPage = 0
    let pageSize = 30
    let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen", category: "PullRequestsViewModel")

    // MARK: - Initialization

    func configure(repoPath: String) {
        self.repoPath = repoPath
        Task {
            hostingInfo = await hostingService.getHostingInfo(for: repoPath)
        }
    }

    // MARK: - Actions

    func merge(method: PRMergeMethod) async {
        guard let pr = selectedPR else { return }

        isPerformingAction = true
        actionError = nil

        do {
            try await hostingService.mergePullRequestWithMethod(repoPath: repoPath, number: pr.number, method: method)
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

    func approve(body: String? = nil) async {
        guard let pr = selectedPR else { return }

        isPerformingAction = true
        actionError = nil

        do {
            try await hostingService.approvePullRequest(repoPath: repoPath, number: pr.number, body: body)
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
            try await hostingService.requestChanges(repoPath: repoPath, number: pr.number, body: body)
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
            try await hostingService.addPullRequestComment(repoPath: repoPath, number: pr.number, body: body)
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
                try await hostingService.addPullRequestComment(repoPath: repoPath, number: pr.number, body: trimmedBody)

            case .approve:
                try await hostingService.approvePullRequest(
                    repoPath: repoPath,
                    number: pr.number,
                    body: trimmedBody.isEmpty ? nil : trimmedBody
                )
                if !trimmedBody.isEmpty, hostingInfo?.provider == .gitlab {
                    try await hostingService.addPullRequestComment(repoPath: repoPath, number: pr.number, body: trimmedBody)
                }

            case .requestChanges:
                try await hostingService.requestChanges(repoPath: repoPath, number: pr.number, body: trimmedBody)
            }

            await loadDetail(for: pr)
            await loadComments(for: pr)
        } catch {
            logger.error("Failed to submit conversation action: \(error.localizedDescription)")
            actionError = error.localizedDescription
        }

        isPerformingAction = false
    }

    func checkoutBranch() async {
        guard let pr = selectedPR else { return }

        isPerformingAction = true
        actionError = nil
        var primaryError: Error?

        if let provider = hostingInfo?.provider, provider == .github || provider == .gitlab {
            do {
                try await hostingService.checkoutPullRequest(repoPath: repoPath, number: pr.number)
                isPerformingAction = false
                return
            } catch {
                primaryError = error
                logger.error("PR checkout via CLI failed: \(error.localizedDescription)")
            }
        }

        do {
            try await checkoutBranchWithGit(pr.sourceBranch)
        } catch {
            logger.error("Failed to checkout branch: \(error.localizedDescription)")
            if let primaryError {
                actionError = "\(primaryError.localizedDescription)\n\(error.localizedDescription)"
            } else {
                actionError = error.localizedDescription
            }
        }

        isPerformingAction = false
    }

    private func checkoutBranchWithGit(_ branch: String) async throws {
        let result = try await ProcessExecutor.shared.executeWithOutput(
            executable: "/usr/bin/git",
            arguments: ["checkout", branch],
            workingDirectory: repoPath
        )

        if result.exitCode != 0 {
            // Try fetching first then checkout
            _ = try await ProcessExecutor.shared.executeWithOutput(
                executable: "/usr/bin/git",
                arguments: ["fetch", "origin", branch],
                workingDirectory: repoPath
            )

            let retryResult = try await ProcessExecutor.shared.executeWithOutput(
                executable: "/usr/bin/git",
                arguments: ["checkout", branch],
                workingDirectory: repoPath
            )

            if retryResult.exitCode != 0 {
                // Create tracking branch
                let trackResult = try await ProcessExecutor.shared.executeWithOutput(
                    executable: "/usr/bin/git",
                    arguments: ["checkout", "-b", branch, "origin/\(branch)"],
                    workingDirectory: repoPath
                )

                if trackResult.exitCode != 0 {
                    throw GitHostingError.commandFailed(message: trackResult.stderr)
                }
            }
        }
    }

    func openInBrowser() {
        guard let pr = selectedPR, let url = URL(string: pr.url) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Helpers

    var prTerminology: String {
        hostingInfo?.provider.prTerminology ?? "Pull Request"
    }

    var canMerge: Bool {
        guard let pr = selectedPR else { return false }
        return pr.state == .open && pr.mergeable.isMergeable
    }

    var canClose: Bool {
        guard let pr = selectedPR else { return false }
        return pr.state == .open
    }

    var canApprove: Bool {
        guard let pr = selectedPR else { return false }
        return pr.state == .open
    }
}
