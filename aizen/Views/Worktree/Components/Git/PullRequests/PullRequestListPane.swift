//
//  PullRequestListPane.swift
//  aizen
//
//  Left pane showing list of PRs with filter and pagination
//

import SwiftUI

struct PullRequestListPane: View {
    @ObservedObject var viewModel: PullRequestsViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            listContent
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var header: some View {
        HStack {
            Text(viewModel.prTerminology + "s")
                .font(.headline)

            Spacer()

            Picker("Filter", selection: Binding(
                get: { viewModel.filter },
                set: { viewModel.changeFilter(to: $0) }
            )) {
                ForEach(PRFilter.allCases, id: \.self) { filter in
                    Text(filter.displayName).tag(filter)
                }
            }
            .pickerStyle(.menu)
            .fixedSize()

            Button {
                Task { await viewModel.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(viewModel.isLoadingList)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var listContent: some View {
        if viewModel.isLoadingList && viewModel.pullRequests.isEmpty {
            loadingView
        } else if let error = viewModel.listError {
            errorView(error)
        } else if viewModel.pullRequests.isEmpty {
            emptyListView
        } else {
            prList
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
            Text("Loading \(viewModel.prTerminology.lowercased())s...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundStyle(.orange)

            Text("Failed to load")
                .font(.headline)

            Text(error)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Retry") {
                Task { await viewModel.loadPullRequests() }
            }
            .buttonStyle(.bordered)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyListView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)

            Text("No \(viewModel.prTerminology.lowercased())s")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("No \(viewModel.filter.displayName.lowercased()) \(viewModel.prTerminology.lowercased())s found")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var prList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.pullRequests) { pr in
                    PRRowView(
                        pr: pr,
                        isSelected: viewModel.selectedPR?.id == pr.id,
                        terminology: viewModel.prTerminology
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.selectPR(pr)
                    }

                    Divider()
                        .padding(.leading, 12)
                }

                // Pagination trigger
                if viewModel.hasMore {
                    Color.clear
                        .frame(height: 1)
                        .onAppear {
                            Task { await viewModel.loadMore() }
                        }

                    if viewModel.isLoadingList {
                        HStack {
                            Spacer()
                            ProgressView()
                                .scaleEffect(0.7)
                            Spacer()
                        }
                        .padding(.vertical, 12)
                    }
                }
            }
        }
    }
}

// MARK: - PR Row View

struct PRRowView: View {
    let pr: PullRequest
    let isSelected: Bool
    let terminology: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("#\(pr.number)")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)

                Text(pr.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()

                PRStateBadge(state: pr.state, isDraft: pr.isDraft)
            }

            HStack(spacing: 8) {
                Label(pr.author, systemImage: "person")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Text("•")
                    .foregroundStyle(.quaternary)

                HStack(spacing: 2) {
                    Text(pr.sourceBranch)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 8))
                    Text(pr.targetBranch)
                }
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)

                Spacer()

                Text(pr.relativeCreatedAt)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            // Status indicators
            if pr.state == .open {
                HStack(spacing: 8) {
                    if let checks = pr.checksStatus {
                        PRChecksBadge(status: checks)
                    }

                    if let review = pr.reviewDecision {
                        PRReviewBadge(decision: review)
                    }

                    if pr.changedFiles > 0 {
                        HStack(spacing: 4) {
                            Text("+\(pr.additions)")
                                .foregroundStyle(.green)
                            Text("-\(pr.deletions)")
                                .foregroundStyle(.red)
                        }
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                    }

                    Spacer()
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .contentShape(Rectangle())
    }
}

// MARK: - Badge Views

struct PRStateBadge: View {
    let state: PullRequest.State
    let isDraft: Bool

    var body: some View {
        Text(isDraft ? "Draft" : state.displayName)
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(backgroundColor)
            .foregroundStyle(foregroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var backgroundColor: Color {
        if isDraft {
            return Color.gray.opacity(0.2)
        }
        switch state {
        case .open: return Color.green.opacity(0.2)
        case .merged: return Color.purple.opacity(0.2)
        case .closed: return Color.red.opacity(0.2)
        }
    }

    private var foregroundColor: Color {
        if isDraft {
            return .gray
        }
        switch state {
        case .open: return .green
        case .merged: return .purple
        case .closed: return .red
        }
    }
}

struct PRChecksBadge: View {
    let status: PullRequest.ChecksStatus

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: status.iconName)
                .font(.system(size: 9))
            Text(status.displayName)
                .font(.system(size: 10))
        }
        .foregroundStyle(color)
    }

    private var color: Color {
        switch status {
        case .passing: return .green
        case .failing: return .red
        case .pending: return .orange
        }
    }
}

struct PRReviewBadge: View {
    let decision: PullRequest.ReviewDecision

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: decision.iconName)
                .font(.system(size: 9))
            Text(decision.displayName)
                .font(.system(size: 10))
        }
        .foregroundStyle(color)
    }

    private var color: Color {
        switch decision {
        case .approved: return .green
        case .changesRequested: return .red
        case .reviewRequired: return .orange
        }
    }
}
