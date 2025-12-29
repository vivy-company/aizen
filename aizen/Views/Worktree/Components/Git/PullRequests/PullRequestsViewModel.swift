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

    private let hostingService = GitHostingService()
    private var repoPath: String = ""
    private var currentPage = 0
    private let pageSize = 30
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen", category: "PullRequestsViewModel")

    // MARK: - Initialization

    func configure(repoPath: String) {
        self.repoPath = repoPath
        Task {
            hostingInfo = await hostingService.getHostingInfo(for: repoPath)
        }
    }

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

            // Auto-select first PR if none selected
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

            // Filter out duplicates
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

        // Refresh selected PR detail if any
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

        // Clear previous data
        comments = []
        diffOutput = ""

        // Refresh PR details to get latest state (but don't update list to avoid jumps)
        do {
            let updatedPR = try await hostingService.getPullRequestDetail(repoPath: repoPath, number: pr.number)
            // Only update selectedPR, not the list (list updates on refresh only)
            if selectedPR?.id == pr.id {
                selectedPR = updatedPR
            }
        } catch {
            logger.error("Failed to refresh PR detail: \(error.localizedDescription)")
        }
    }

    /// Load comments on-demand (called when Comments tab is selected)
    func loadCommentsIfNeeded() async {
        guard let pr = selectedPR, comments.isEmpty, !isLoadingComments else { return }
        await loadComments(for: pr)
    }

    /// Load diff on-demand (called when Diff tab is selected)
    func loadDiffIfNeeded() async {
        guard let pr = selectedPR, diffOutput.isEmpty, !isLoadingDiff else { return }
        await loadDiff(for: pr)
    }

    private func loadComments(for pr: PullRequest) async {
        isLoadingComments = true
        do {
            comments = try await hostingService.getPullRequestComments(repoPath: repoPath, number: pr.number)
        } catch {
            logger.error("Failed to load comments: \(error.localizedDescription)")
            comments = []
        }
        isLoadingComments = false
    }

    private func loadDiff(for pr: PullRequest) async {
        isLoadingDiff = true
        do {
            diffOutput = try await hostingService.getPullRequestDiff(repoPath: repoPath, number: pr.number)
        } catch {
            logger.error("Failed to load diff: \(error.localizedDescription)")
            diffOutput = ""
        }
        isLoadingDiff = false
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

        do {
            let result = try await ProcessExecutor.shared.executeWithOutput(
                executable: "/usr/bin/git",
                arguments: ["checkout", pr.sourceBranch],
                workingDirectory: repoPath
            )

            if result.exitCode != 0 {
                // Try fetching first then checkout
                _ = try await ProcessExecutor.shared.executeWithOutput(
                    executable: "/usr/bin/git",
                    arguments: ["fetch", "origin", pr.sourceBranch],
                    workingDirectory: repoPath
                )

                let retryResult = try await ProcessExecutor.shared.executeWithOutput(
                    executable: "/usr/bin/git",
                    arguments: ["checkout", pr.sourceBranch],
                    workingDirectory: repoPath
                )

                if retryResult.exitCode != 0 {
                    // Create tracking branch
                    let trackResult = try await ProcessExecutor.shared.executeWithOutput(
                        executable: "/usr/bin/git",
                        arguments: ["checkout", "-b", pr.sourceBranch, "origin/\(pr.sourceBranch)"],
                        workingDirectory: repoPath
                    )

                    if trackResult.exitCode != 0 {
                        throw GitHostingError.commandFailed(message: trackResult.stderr)
                    }
                }
            }
        } catch {
            logger.error("Failed to checkout branch: \(error.localizedDescription)")
            actionError = error.localizedDescription
        }

        isPerformingAction = false
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
