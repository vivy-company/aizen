//
//  PullRequestsView.swift
//  aizen
//
//  Main container view for PR list with detail pane
//

import SwiftUI

struct PullRequestsView: View {
    let repoPath: String

    @StateObject private var viewModel = PullRequestsViewModel()
    @State private var listWidth: CGFloat = 300

    private let minListWidth: CGFloat = 250
    private let maxListWidth: CGFloat = 450

    var body: some View {
        HStack(spacing: 0) {
            // Left: PR List
            PullRequestListPane(viewModel: viewModel)
                .frame(width: listWidth)

            // Resizable divider
            resizableDivider

            // Right: PR Detail
            if let pr = viewModel.selectedPR {
                PullRequestDetailPane(viewModel: viewModel, pr: pr)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            viewModel.configure(repoPath: repoPath)
            Task {
                await viewModel.loadPullRequests()
            }
        }
    }

    private var resizableDivider: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: 1)
            .overlay(
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 8)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let newWidth = listWidth + value.translation.width
                                listWidth = min(max(newWidth, minListWidth), maxListWidth)
                            }
                    )
                    .onHover { hovering in
                        if hovering {
                            NSCursor.resizeLeftRight.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
            )
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.triangle.merge")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text("Select a \(viewModel.prTerminology)")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Choose a \(viewModel.prTerminology.lowercased()) from the list to view details")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
    }
}
