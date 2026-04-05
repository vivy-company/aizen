import SwiftUI

extension GitHistoryView {
    var header: some View {
        HStack(spacing: 12) {
            Text(String(localized: "git.history.title"))
                .font(.headline)

            if !commits.isEmpty {
                TagBadge(
                    text: "\(commits.count)\(hasMoreCommits ? "+" : "")",
                    color: .secondary,
                    cornerRadius: 6
                )
            }

            Spacer()

            Button {
                Task { await refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .help(String(localized: "git.history.refresh"))
            .disabled(isLoading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            Text(String(localized: "git.history.loading"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundStyle(.orange)

            Text(String(localized: "git.history.loadFailed"))
                .font(.system(size: 13, weight: .medium))

            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button(String(localized: "general.retry")) {
                Task { await loadCommits() }
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)

            Text(String(localized: "git.history.empty"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var commitsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if selectedCommit != nil {
                    workingChangesRow
                    GitWindowDivider(opacity: dividerOpacity)
                }

                ForEach(commits) { commit in
                    commitRow(commit)
                        .onAppear {
                            if commit.id == commits.last?.id && hasMoreCommits && !isLoadingMore {
                                Task { await loadMoreCommits() }
                            }
                        }
                    GitWindowDivider(opacity: dividerOpacity)
                }

                if isLoadingMore {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(String(localized: "git.history.loadingMore"))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                } else if hasMoreCommits {
                    Button {
                        Task { await loadMoreCommits() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.down.circle")
                                .font(.system(size: 11))
                            Text(String(localized: "git.history.loadMore"))
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(.blue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

}
