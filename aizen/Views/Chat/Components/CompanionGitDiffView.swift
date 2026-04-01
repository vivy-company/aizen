//
//  CompanionGitDiffView.swift
//  aizen
//
//  Diff-only companion panel content for chat split view
//

import SwiftUI

struct CompanionGitDiffView: View {
    let worktree: Worktree
    let onSummaryChange: ((String) -> Void)?

    private let runtime: WorktreeRuntime
    @ObservedObject private var gitSummaryStore: GitSummaryStore
    @ObservedObject private var gitDiffStore: GitDiffRuntimeStore

    @State private var isAgentStreaming = false

    @AppStorage("editorFontFamily") private var editorFontFamily: String = "Menlo"
    @AppStorage("diffFontSize") private var diffFontSize: Double = 11.0

    init(worktree: Worktree, onSummaryChange: ((String) -> Void)? = nil) {
        self.worktree = worktree
        self.onSummaryChange = onSummaryChange
        let runtime = WorktreeRuntimeCoordinator.shared.runtime(for: worktree.path ?? "")
        self.runtime = runtime
        self._gitSummaryStore = ObservedObject(wrappedValue: runtime.summaryStore)
        self._gitDiffStore = ObservedObject(wrappedValue: runtime.diffStore)
    }

    private var worktreePath: String {
        worktree.path ?? ""
    }

    private var gitStatus: GitStatus {
        gitSummaryStore.status
    }

    private var allChangedFiles: [String] {
        var files = Set<String>()
        files.formUnion(gitStatus.stagedFiles)
        files.formUnion(gitStatus.modifiedFiles)
        files.formUnion(gitStatus.untrackedFiles)
        files.formUnion(gitStatus.conflictedFiles)
        return files.sorted()
    }

    var body: some View {
        VStack(spacing: 0) {
            if allChangedFiles.isEmpty {
                AllFilesDiffEmptyView()
            } else if gitDiffStore.isLoading && gitDiffStore.diffOutput.isEmpty {
                VStack {
                    Spacer()
                    CompanionDiffSpinner()
                    Text(String(localized: "git.diff.loading"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                DiffView(
                    diffOutput: gitDiffStore.diffOutput,
                    fontSize: diffFontSize,
                    fontFamily: editorFontFamily,
                    repoPath: worktreePath,
                    onOpenFile: { file in
                        let fullPath = (worktreePath as NSString).appendingPathComponent(file)
                        NotificationCenter.default.post(
                            name: .openFileInEditor,
                            object: nil,
                            userInfo: ["path": fullPath]
                        )
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            guard !worktreePath.isEmpty else { return }
            runtime.setCompanionDiffVisible(true)
            runtime.setCompanionDiffRefreshSuspended(isAgentStreaming)
            publishSummary()
        }
        .onDisappear {
            runtime.setCompanionDiffVisible(false)
        }
        .onChange(of: gitStatus) { _, _ in
            publishSummary()
        }
        .onChange(of: worktreePath) { _, newPath in
            guard !newPath.isEmpty else { return }
            publishSummary()
        }
        .onReceive(NotificationCenter.default.publisher(for: .agentStreamingDidStart)) { notification in
            guard let path = notification.userInfo?["worktreePath"] as? String,
                  path == worktreePath else { return }
            isAgentStreaming = true
            runtime.setCompanionDiffRefreshSuspended(true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .agentStreamingDidStop)) { notification in
            guard let path = notification.userInfo?["worktreePath"] as? String,
                  path == worktreePath else { return }
            isAgentStreaming = false
            runtime.setCompanionDiffRefreshSuspended(false)
            runtime.refreshWorkingDiffNow()
        }
    }

    private func publishSummary() {
        let branch = gitStatus.currentBranch.isEmpty ? "HEAD" : gitStatus.currentBranch
        let filesLabel = allChangedFiles.count == 1 ? "1 file" : "\(allChangedFiles.count) files"
        onSummaryChange?("\(branch)  +\(gitStatus.additions)  -\(gitStatus.deletions)  \(filesLabel)")
    }
}

private struct CompanionDiffSpinner: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAnimating = false

    var body: some View {
        Image(systemName: "arrow.triangle.2.circlepath")
            .font(.system(size: 20, weight: .medium))
            .rotationEffect(.degrees(isAnimating ? 360 : 0))
            .animation(
                reduceMotion ? nil : .linear(duration: 1.0).repeatForever(autoreverses: false),
                value: isAnimating
            )
            .onAppear { isAnimating = true }
            .onDisappear { isAnimating = false }
    }
}
