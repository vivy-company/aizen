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

    @StateObject private var gitRepositoryService: GitRepositoryService

    @State private var diffOutput: String = ""
    @State private var isLoadingDiff: Bool = false
    @State private var gitIndexWatchToken: UUID?
    @State private var diffReloadTask: Task<Void, Never>?
    @State private var diffLoadTask: Task<Void, Never>?
    @State private var isAgentStreaming: Bool = false

    @AppStorage("editorFontFamily") private var editorFontFamily: String = "Menlo"
    @AppStorage("diffFontSize") private var diffFontSize: Double = 11.0

    init(worktree: Worktree, onSummaryChange: ((String) -> Void)? = nil) {
        self.worktree = worktree
        self.onSummaryChange = onSummaryChange
        self._gitRepositoryService = StateObject(
            wrappedValue: GitRepositoryService(worktreePath: worktree.path ?? "")
        )
    }

    private var worktreePath: String {
        worktree.path ?? ""
    }

    private var gitStatus: GitStatus {
        gitRepositoryService.currentStatus
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
            } else if isLoadingDiff && diffOutput.isEmpty {
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
                    diffOutput: diffOutput,
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
            gitRepositoryService.updateWorktreePath(worktreePath)
            gitRepositoryService.reloadStatus()
            reloadDiffNow()
            setupGitWatcher()
            publishSummary()
        }
        .onDisappear {
            if let token = gitIndexWatchToken {
                Task {
                    await GitIndexWatchCenter.shared.removeSubscriber(worktreePath: worktreePath, id: token)
                }
            }
            gitIndexWatchToken = nil
            diffReloadTask?.cancel()
            diffReloadTask = nil
            diffLoadTask?.cancel()
            diffLoadTask = nil
        }
        .onChange(of: gitStatus) { _, _ in
            guard !isAgentStreaming else { return }
            reloadDiffDebounced()
            publishSummary()
        }
        .onChange(of: worktreePath) { _, newPath in
            guard !newPath.isEmpty else { return }
            gitRepositoryService.updateWorktreePath(newPath)
            guard !isAgentStreaming else { return }
            gitRepositoryService.reloadStatus(lightweight: true)
            reloadDiffNow()
            publishSummary()
        }
        .onReceive(NotificationCenter.default.publisher(for: .agentStreamingDidStart)) { notification in
            guard let path = notification.userInfo?["worktreePath"] as? String,
                  path == worktreePath else { return }
            isAgentStreaming = true
            diffReloadTask?.cancel()
            diffReloadTask = nil
            diffLoadTask?.cancel()
            diffLoadTask = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .agentStreamingDidStop)) { notification in
            guard let path = notification.userInfo?["worktreePath"] as? String,
                  path == worktreePath else { return }
            isAgentStreaming = false
            gitRepositoryService.reloadStatus()
            reloadDiffDebounced()
        }
    }

    private func publishSummary() {
        let branch = gitStatus.currentBranch.isEmpty ? "HEAD" : gitStatus.currentBranch
        let filesLabel = allChangedFiles.count == 1 ? "1 file" : "\(allChangedFiles.count) files"
        onSummaryChange?("\(branch)  +\(gitStatus.additions)  -\(gitStatus.deletions)  \(filesLabel)")
    }

    private func setupGitWatcher() {
        guard gitIndexWatchToken == nil else { return }
        guard !worktreePath.isEmpty else { return }

        Task {
            let service = gitRepositoryService
            let token = await GitIndexWatchCenter.shared.addSubscriber(worktreePath: worktreePath) { [weak service] in
                service?.reloadStatus(lightweight: true)
            }
            await MainActor.run {
                gitIndexWatchToken = token
            }
        }
    }

    private func reloadDiffDebounced() {
        diffReloadTask?.cancel()
        diffReloadTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            reloadDiffNow()
        }
    }

    private func reloadDiffNow() {
        let path = worktreePath
        guard !path.isEmpty else {
            diffOutput = ""
            isLoadingDiff = false
            return
        }

        diffLoadTask?.cancel()
        isLoadingDiff = true

        diffLoadTask = Task {
            let output = await Self.loadWorkingDiff(path: path)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                diffOutput = output
                isLoadingDiff = false
            }
        }
    }

    nonisolated private static func loadWorkingDiff(path: String) async -> String {
        await Task.detached(priority: .utility) {
            do {
                let repo = try Libgit2Repository(path: path)

                let headDiff = try repo.diffUnified()
                if !headDiff.isEmpty {
                    return headDiff
                }

                let stagedDiff = try repo.diffStagedUnified()
                if !stagedDiff.isEmpty {
                    return stagedDiff
                }

                let unstagedDiff = try repo.diffUnstagedUnified()
                if !unstagedDiff.isEmpty {
                    return unstagedDiff
                }

                let status = try repo.status()
                if !status.untracked.isEmpty {
                    var output = ""
                    for entry in status.untracked.prefix(50) {
                        output += buildFileDiff(file: entry.path, basePath: path)
                    }
                    return output
                }

                return ""
            } catch {
                return ""
            }
        }.value
    }

    nonisolated private static func buildFileDiff(file: String, basePath: String) -> String {
        let fullPath = (basePath as NSString).appendingPathComponent(file)
        guard let data = FileManager.default.contents(atPath: fullPath),
              let content = String(data: data, encoding: .utf8) else {
            return ""
        }

        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        var parts = [String]()
        parts.reserveCapacity(lines.count + 5)

        parts.append("diff --git a/\(file) b/\(file)")
        parts.append("new file mode 100644")
        parts.append("--- /dev/null")
        parts.append("+++ b/\(file)")
        parts.append("@@ -0,0 +1,\(lines.count) @@")

        for line in lines {
            parts.append("+\(line)")
        }

        return parts.joined(separator: "\n") + "\n"
    }
}

private struct CompanionDiffSpinner: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAnimating = false

    var body: some View {
        Circle()
            .trim(from: 0.18, to: 0.92)
            .stroke(
                Color.secondary.opacity(0.85),
                style: StrokeStyle(lineWidth: 2, lineCap: .round)
            )
            .frame(width: 18, height: 18)
            .rotationEffect(.degrees(isAnimating ? 360 : 0))
            .animation(
                reduceMotion ? .none : .linear(duration: 0.9).repeatForever(autoreverses: false),
                value: isAnimating
            )
            .onAppear {
                isAnimating = true
            }
            .onDisappear {
                isAnimating = false
            }
    }
}
