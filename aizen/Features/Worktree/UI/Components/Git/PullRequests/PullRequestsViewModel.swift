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
