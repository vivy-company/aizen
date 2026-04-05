//
//  WorktreeDetailsSheet+Content.swift
//  aizen
//
//  Created by OpenAI Codex on 06.04.26.
//

import SwiftUI

extension WorktreeDetailsSheet {
    var header: some View {
        DetailHeaderBar(showsBackground: false) {
            VStack(alignment: .leading, spacing: 4) {
                Text(worktree.branch ?? String(localized: "worktree.list.unknown"))
                    .font(.title2)
                    .fontWeight(.bold)

                if worktree.isPrimary {
                    PillBadge(
                        text: String(localized: "worktree.detail.primary"),
                        color: .blue,
                        textColor: .white,
                        font: .caption,
                        fontWeight: .semibold,
                        horizontalPadding: 8,
                        verticalPadding: 3,
                        backgroundOpacity: 1.0
                    )
                }
            }
        } trailing: {
            DetailCloseButton { dismiss() }
        }
    }

    var branchStatus: some View {
        Group {
            if isLoading {
                HStack {
                    ProgressView()
                    Text("worktree.detail.loadingStatus", bundle: .main)
                        .foregroundStyle(.secondary)
                }
            } else if ahead > 0 || behind > 0 {
                HStack(spacing: 16) {
                    if ahead > 0 {
                        Label(String(localized: "worktree.detail.ahead \(ahead)"), systemImage: "arrow.up.circle.fill")
                            .foregroundStyle(.green)
                    }
                    if behind > 0 {
                        Label(String(localized: "worktree.detail.behind \(behind)"), systemImage: "arrow.down.circle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            } else {
                Label(String(localized: "worktree.detail.upToDate"), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
    }

    var informationSection: some View {
        GroupBox(String(localized: "worktree.detail.information")) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("worktree.detail.path", bundle: .main)
                        .foregroundStyle(.secondary)
                        .frame(width: 80, alignment: .leading)
                    Text(worktree.path ?? String(localized: "worktree.list.unknown"))
                        .textSelection(.enabled)
                }

                Divider()

                HStack {
                    Text("worktree.detail.branch", bundle: .main)
                        .foregroundStyle(.secondary)
                        .frame(width: 80, alignment: .leading)
                    Text(currentBranch.isEmpty ? (worktree.branch ?? String(localized: "worktree.list.unknown")) : currentBranch)
                        .textSelection(.enabled)
                }

                if let lastAccessed = worktree.lastAccessed {
                    Divider()
                    HStack {
                        Text("worktree.detail.lastAccessed", bundle: .main)
                            .foregroundStyle(.secondary)
                            .frame(width: 80, alignment: .leading)
                        Text(lastAccessed.formatted(date: .abbreviated, time: .shortened))
                    }
                }
            }
            .padding(8)
        }
    }

    @ViewBuilder
    var errorSection: some View {
        if let error = errorMessage {
            Text(error)
                .foregroundStyle(.red)
                .padding()
                .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    func refreshStatus() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let status = try await repositoryManager.getWorktreeStatus(worktree)
                await MainActor.run {
                    currentBranch = status.branch
                    ahead = status.ahead
                    behind = status.behind
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
}
