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

    var workingChangesRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "pencil.circle")
                .font(.system(size: 14))
                .foregroundStyle(.blue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "git.history.workingChanges"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)

                Text(String(localized: "git.history.viewUncommitted"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelectCommit(nil)
        }
    }

    func commitRow(_ commit: GitCommit) -> some View {
        let isSelected = selectedCommit?.id == commit.id
        let isHovered = hoveredCommitID == commit.id

        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 13))
                .foregroundStyle(isSelected ? selectedForegroundColor : .secondary)
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(commit.message)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isSelected ? selectedForegroundColor : .primary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer()

                    Text(commit.relativeDate)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.secondary.opacity(0.75))
                }

                HStack(spacing: 8) {
                    Text(commit.author)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    Text("•")
                        .foregroundStyle(Color.secondary.opacity(0.45))

                    Text(commit.shortHash)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)

                    if commit.filesChanged > 0 {
                        Text("•")
                            .foregroundStyle(Color.secondary.opacity(0.45))

                        HStack(spacing: 4) {
                            Image(systemName: "doc")
                                .font(.system(size: 10))
                            Text("\(commit.filesChanged)")
                                .font(.system(size: 11, design: .monospaced))
                        }
                        .foregroundStyle(.secondary)
                    }

                    if commit.additions > 0 {
                        Text("+\(commit.additions)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.green)
                    }

                    if commit.deletions > 0 {
                        Text("-\(commit.deletions)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(
            Group {
                if isSelected {
                    Rectangle().fill(selectionFillColor)
                } else if isHovered {
                    Rectangle().fill(Color.white.opacity(0.06))
                } else {
                    Color.clear
                }
            }
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelectCommit(commit)
        }
        .onHover { hovering in
            hoveredCommitID = hovering ? commit.id : (hoveredCommitID == commit.id ? nil : hoveredCommitID)
        }
    }
}
