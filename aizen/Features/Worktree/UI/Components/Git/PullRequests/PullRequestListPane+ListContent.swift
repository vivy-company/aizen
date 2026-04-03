//
//  PullRequestListPane+ListContent.swift
//  aizen
//
//  List content states for the pull request list pane.
//

import SwiftUI

extension PullRequestListPane {
    @ViewBuilder
    var listContent: some View {
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

    var loadingView: some View {
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

    func errorView(_ error: String) -> some View {
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

    var emptyListView: some View {
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

    var prList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.pullRequests) { pr in
                    PRRowView(
                        pr: pr,
                        isSelected: viewModel.selectedPR?.id == pr.id,
                        isHovered: hoveredPullRequestID == pr.id,
                        selectedForegroundColor: selectedForegroundColor,
                        selectionFillColor: selectionFillColor
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.selectPR(pr)
                    }
                    .onHover { hovering in
                        hoveredPullRequestID = hovering ? pr.id :
                            (hoveredPullRequestID == pr.id ? nil : hoveredPullRequestID)
                    }
                    GitWindowDivider()
                }

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
            .padding(.bottom, Layout.listBottomPadding)
        }
    }
}
