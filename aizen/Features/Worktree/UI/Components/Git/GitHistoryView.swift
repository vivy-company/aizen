//
//  GitHistoryView.swift
//  aizen
//
//  Displays git commit history with detailed info
//

import SwiftUI

struct GitHistoryView: View {
    let worktreePath: String
    let selectedCommit: GitCommit?
    let onSelectCommit: (GitCommit?) -> Void

    @Environment(\.controlActiveState) var controlActiveState
    @State var commits: [GitCommit] = []
    @State var isLoading = true
    @State var isLoadingMore = false
    @State var hasMoreCommits = true
    @State var errorMessage: String?
    @State var hoveredCommitID: String?

    private let logService = GitLogService()
    let pageSize = 30
    let dividerOpacity: CGFloat = 1.4

    var selectedForegroundColor: Color {
        controlActiveState == .key ? .accentColor : .accentColor.opacity(0.78)
    }

    var selectionFillColor: Color {
        let base = NSColor.unemphasizedSelectedContentBackgroundColor
        let alpha: Double = controlActiveState == .key ? 0.26 : 0.18
        return Color(nsColor: base).opacity(alpha)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            GitWindowDivider(opacity: dividerOpacity)

            if isLoading && commits.isEmpty {
                loadingView
            } else if let error = errorMessage, commits.isEmpty {
                errorView(error)
            } else if commits.isEmpty {
                emptyView
            } else {
                commitsList
            }
        }
        .task {
            await loadCommits()
        }
    }

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
