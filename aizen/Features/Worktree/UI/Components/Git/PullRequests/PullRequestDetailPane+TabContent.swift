import SwiftUI

extension PullRequestDetailPane {
    @ViewBuilder
    var tabContent: some View {
        switch selectedTab {
        case .overview:
            overviewTab
        case .diff:
            diffTab
        case .comments:
            commentsTab
        }
    }

    @ViewBuilder
    var overviewTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !pr.body.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Description")
                            .font(.headline)

                        MessageContentView(content: pr.body)
                    }
                } else {
                    Text("No description provided")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                        .italic()
                }

                Spacer()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    var diffTab: some View {
        Group {
            if viewModel.isLoadingDiff {
                VStack {
                    Spacer()
                    ProgressView()
                    Text("Loading diff...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else if viewModel.diffOutput.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "doc.text")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text("No changes")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                DiffView(
                    diffOutput: viewModel.diffOutput,
                    fontSize: diffFontSize,
                    fontFamily: editorFontFamily,
                    repoPath: "",
                    scrollToFile: nil,
                    onFileVisible: { _ in },
                    onOpenFile: { _ in },
                    commentedLines: Set(),
                    onAddComment: { _, _ in }
                )
            }
        }
        .task(id: pr.id) {
            await viewModel.loadDiffIfNeeded()
        }
    }

    @ViewBuilder
    var commentsTab: some View {
        VStack(spacing: 0) {
            if viewModel.isLoadingComments {
                VStack {
                    Spacer()
                    ProgressView()
                    Text("Loading comments...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else if viewModel.comments.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text("No comments yet")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.comments) { comment in
                            PRCommentView(comment: comment)
                        }
                    }
                    .padding(16)
                }
            }

            GitWindowDivider()

            if pr.state == .open {
                commentInput
            }
        }
        .task(id: pr.id) {
            await viewModel.loadCommentsIfNeeded()
        }
    }
}
