//
//  GitPanelWindowContent.swift
//  aizen
//
//  Main content view for the git panel window with toolbar tabs
//

import SwiftUI
import os.log

enum GitPanelTab: String, CaseIterable {
    case git
    case history
    case comments
    case workflows
    case prs

    var displayName: String {
        switch self {
        case .git: return String(localized: "git.panel.git")
        case .history: return String(localized: "git.panel.history")
        case .comments: return String(localized: "git.panel.comments")
        case .workflows: return String(localized: "git.panel.workflows")
        case .prs: return String(localized: "git.panel.prs")
        }
    }

    var icon: String {
        switch self {
        case .git: return "tray.full"
        case .history: return "clock"
        case .comments: return "text.bubble"
        case .workflows: return "bolt.circle"
        case .prs: return "arrow.triangle.merge"
        }
    }
}

struct GitPanelWindowContent: View {
    let context: GitChangesContext
    let repositoryManager: RepositoryManager
    @Binding var selectedTab: GitPanelTab
    let onClose: () -> Void

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen", category: "GitPanelWindow")
    @State private var selectedHistoryCommit: GitCommit?
    @State private var diffOutput: String = ""
    @State private var leftPanelWidth: CGFloat = 350
    @State private var visibleFile: String?
    @State private var scrollToFile: String?
    @State private var commentPopoverLine: DiffLine?
    @State private var commentPopoverFilePath: String?
    @State private var showAgentPicker: Bool = false
    @State private var cachedChangedFiles: [String] = []
    @State private var gitIndexWatchToken: UUID?
    @State private var diffReloadTask: Task<Void, Never>?

    @StateObject private var reviewManager = ReviewSessionManager()
    @StateObject private var workflowService = WorkflowService()
    @State private var selectedWorkflowForTrigger: Workflow?
    @State private var workflowServiceInitialized: Bool = false

    @AppStorage("editorFontFamily") private var editorFontFamily: String = "Menlo"
    @AppStorage("diffFontSize") private var diffFontSize: Double = 11.0

    private let minLeftPanelWidth: CGFloat = 280
    private let maxLeftPanelWidth: CGFloat = 500

    private var worktree: Worktree { context.worktree }
    private var worktreePath: String { worktree.path ?? "" }
    private var gitRepositoryService: GitRepositoryService { context.service }

    private var gitOperations: WorktreeGitOperations {
        WorktreeGitOperations(
            gitRepositoryService: gitRepositoryService,
            repositoryManager: repositoryManager,
            worktree: worktree,
            logger: logger
        )
    }

    private var gitStatus: GitStatus {
        gitRepositoryService.currentStatus
    }

    private var allChangedFiles: [String] {
        cachedChangedFiles
    }

    var body: some View {
        Group {
            if selectedTab == .prs {
                // PRs tab has its own split view layout
                PullRequestsView(repoPath: worktreePath)
            } else {
                HStack(spacing: 0) {
                    // Left: Tab content
                    leftPanel
                        .frame(width: leftPanelWidth)

                    // Resizable divider
                    resizableDivider

                    // Right: Diff view or Workflow details
                    rightPanel
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onAppear {
            if let path = worktree.path {
                gitRepositoryService.updateWorktreePath(path)
            }
            gitRepositoryService.reloadStatus()
            reviewManager.load(for: worktreePath)
            updateChangedFilesCache()
            setupGitWatcher()
        }
        .onChange(of: selectedTab) { newTab in
            // Lazy-load workflow service when workflows tab is selected
            if newTab == .workflows && !workflowServiceInitialized {
                workflowServiceInitialized = true
                Task {
                    await workflowService.configure(
                        repoPath: worktreePath,
                        branch: gitStatus.currentBranch ?? "main"
                    )
                }
            }
        }
        .onDisappear {
            if let token = gitIndexWatchToken {
                Task {
                    await GitIndexWatchCenter.shared.removeSubscriber(worktreePath: worktreePath, id: token)
                }
            }
            gitIndexWatchToken = nil
            workflowService.stopAutoRefresh()
        }
        .onChange(of: gitStatus) { _ in
            let changed = updateChangedFilesCache()
            if changed {
                reloadDiffDebounced()
            }
        }
        .onChange(of: selectedHistoryCommit) { commit in
            Task {
                await loadDiff(for: commit)
            }
        }
        .sheet(item: $commentPopoverLine) { line in
            CommentPopover(
                diffLine: line,
                filePath: commentPopoverFilePath ?? "",
                existingComment: reviewManager.comments.first {
                    $0.filePath == commentPopoverFilePath && $0.lineNumber == line.lineNumber
                },
                onSave: { text in
                    if let existing = reviewManager.comments.first(where: {
                        $0.filePath == commentPopoverFilePath && $0.lineNumber == line.lineNumber
                    }) {
                        reviewManager.updateComment(id: existing.id, comment: text)
                    } else {
                        reviewManager.addComment(for: line, filePath: commentPopoverFilePath ?? "", comment: text)
                    }
                    commentPopoverLine = nil
                },
                onCancel: {
                    commentPopoverLine = nil
                },
                onDelete: reviewManager.comments.first(where: {
                    $0.filePath == commentPopoverFilePath && $0.lineNumber == line.lineNumber
                }).map { existing in
                    {
                        reviewManager.deleteComment(id: existing.id)
                        commentPopoverLine = nil
                    }
                }
            )
        }
        .sheet(isPresented: $showAgentPicker) {
            SendToAgentSheet(
                worktree: worktree,
                commentsMarkdown: reviewManager.exportToMarkdown(),
                onDismiss: {
                    showAgentPicker = false
                },
                onSend: {
                    reviewManager.clearAll()
                    onClose()
                }
            )
        }
        .sheet(item: $selectedWorkflowForTrigger) { workflow in
            WorkflowTriggerFormView(
                workflow: workflow,
                currentBranch: gitStatus.currentBranch ?? "main",
                service: workflowService,
                onDismiss: {
                    selectedWorkflowForTrigger = nil
                }
            )
        }
    }

    // MARK: - Left Panel (Tab Content)

    @ViewBuilder
    private var leftPanel: some View {
        switch selectedTab {
        case .git:
            gitTabContent
        case .history:
            GitHistoryView(
                worktreePath: worktreePath,
                selectedCommit: selectedHistoryCommit,
                onSelectCommit: { commit in
                    selectedHistoryCommit = commit
                }
            )
        case .comments:
            ReviewCommentsPanel(
                reviewManager: reviewManager,
                onScrollToLine: { filePath, _ in
                    scrollToFile = filePath
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        scrollToFile = nil
                    }
                },
                onCopyAll: {
                    let markdown = reviewManager.exportToMarkdown()
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(markdown, forType: .string)
                },
                onSendToAgent: {
                    showAgentPicker = true
                }
            )
        case .workflows:
            WorkflowSidebarView(
                service: workflowService,
                onSelect: { workflow in
                    workflowService.selectedWorkflow = workflow
                    workflowService.selectedRun = nil
                },
                onTrigger: { workflow in
                    selectedWorkflowForTrigger = workflow
                }
            )
        case .prs:
            EmptyView()
        }
    }

    private var gitTabContent: some View {
        GitSidebarView(
            worktreePath: worktreePath,
            onClose: onClose,
            gitStatus: gitStatus,
            isOperationPending: gitRepositoryService.isOperationPending,
            selectedDiffFile: visibleFile,
            onStageFile: { file in
                gitOperations.stageFile(file)
                reloadDiff()
            },
            onUnstageFile: { file in
                gitOperations.unstageFile(file)
                reloadDiff()
            },
            onStageAll: { completion in
                gitOperations.stageAll {
                    reloadDiff()
                    completion()
                }
            },
            onUnstageAll: {
                gitOperations.unstageAll()
                reloadDiff()
            },
            onDiscardAll: {
                gitOperations.discardAll()
                reloadDiff()
            },
            onCleanUntracked: {
                gitOperations.cleanUntracked()
                reloadDiff()
            },
            onCommit: { message in
                gitOperations.commit(message)
                reloadDiff()
            },
            onAmendCommit: { message in
                gitOperations.amendCommit(message)
                reloadDiff()
            },
            onCommitWithSignoff: { message in
                gitOperations.commitWithSignoff(message)
                reloadDiff()
            },
            onFileClick: { file in
                visibleFile = file
                scrollToFile = file
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    scrollToFile = nil
                }
            }
        )
    }

    // MARK: - Diff Panel

    private var diffPanelHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            if let commit = selectedHistoryCommit {
                // Viewing a specific commit
                Text(commit.shortHash)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))

                Text(commit.message)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()

                Button(String(localized: "git.panel.backToChanges")) {
                    selectedHistoryCommit = nil
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                // Viewing working changes
                Text(gitStatus.currentBranch ?? "HEAD")
                    .font(.system(size: 13, weight: .medium))

                CopyButton(text: gitStatus.currentBranch ?? "", iconSize: 11)

                Spacer()

                HStack(spacing: 8) {
                    Text("+\(gitStatus.additions)")
                        .foregroundStyle(.green)
                    Text("-\(gitStatus.deletions)")
                        .foregroundStyle(.red)
                    Text("\(allChangedFiles.count) files")
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 12, weight: .medium, design: .monospaced))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
    }

    private var diffPanel: some View {
        VStack(spacing: 0) {
            diffPanelHeader
            Divider()

            if selectedHistoryCommit == nil && allChangedFiles.isEmpty {
                AllFilesDiffEmptyView()
            } else if diffOutput.isEmpty {
                VStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.8)
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
                    scrollToFile: scrollToFile,
                    onFileVisible: { file in
                        visibleFile = file
                    },
                    onOpenFile: { file in
                        let fullPath = (worktreePath as NSString).appendingPathComponent(file)
                        NotificationCenter.default.post(
                            name: .openFileInEditor,
                            object: nil,
                            userInfo: ["path": fullPath]
                        )
                        onClose()
                    },
                    commentedLines: selectedHistoryCommit == nil ? reviewManager.commentedLineKeys : Set(),
                    onAddComment: selectedHistoryCommit == nil ? { line, filePath in
                        commentPopoverFilePath = filePath
                        commentPopoverLine = line
                    } : { _, _ in }
                )
            }
        }
        .task {
            await loadDiff(for: nil)
        }
        .onChange(of: diffOutput) { _ in
            validateCommentsAgainstDiff()
        }
    }

    // MARK: - Right Panel

    @ViewBuilder
    private var rightPanel: some View {
        switch selectedTab {
        case .prs:
            EmptyView()
        case .workflows:
            workflowDetailPanel
        default:
            diffPanel
        }
    }

    private var workflowDetailPanel: some View {
        Group {
            if let workflow = workflowService.selectedWorkflow {
                WorkflowFileView(workflow: workflow, worktreePath: worktreePath)
                    .id(workflow.id)
            } else if workflowService.selectedRun != nil {
                WorkflowRunDetailView(service: workflowService)
            } else {
                workflowEmptyState
            }
        }
    }

    private var workflowEmptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bolt.circle")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text(String(localized: "git.workflow.selectRun"))
                .font(.headline)
                .foregroundStyle(.secondary)

            Text(String(localized: "git.workflow.selectRunHint"))
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Divider

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
                                let newWidth = leftPanelWidth + value.translation.width
                                leftPanelWidth = min(max(newWidth, minLeftPanelWidth), maxLeftPanelWidth)
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

    // MARK: - Helper Methods

    private func setupGitWatcher() {
        guard gitIndexWatchToken == nil else { return }
        Task {
            let service = gitRepositoryService
            let token = await GitIndexWatchCenter.shared.addSubscriber(worktreePath: worktreePath) { [weak service] in
                Task { @MainActor in
                    service?.reloadStatus(lightweight: true)
                }
            }
            await MainActor.run {
                gitIndexWatchToken = token
            }
        }
    }

    private func updateChangedFilesCache() -> Bool {
        var files = Set<String>()
        files.formUnion(gitStatus.stagedFiles)
        files.formUnion(gitStatus.modifiedFiles)
        files.formUnion(gitStatus.untrackedFiles)
        files.formUnion(gitStatus.conflictedFiles)

        let sortedFiles = files.sorted()
        if sortedFiles != cachedChangedFiles {
            cachedChangedFiles = sortedFiles
            return true
        }
        return false
    }

    private func validateCommentsAgainstDiff() {
        guard selectedHistoryCommit == nil else { return }

        let filesInDiff = Set(allChangedFiles)
        let commentsToRemove = reviewManager.comments.filter { !filesInDiff.contains($0.filePath) }

        for comment in commentsToRemove {
            reviewManager.deleteComment(id: comment.id)
        }
    }

    private func loadDiff(for commit: GitCommit?) async {
        let path = worktreePath

        guard !path.isEmpty else { return }

        if let commit = commit {
            // Load diff for specific commit using async ProcessExecutor
            do {
                let result = try await ProcessExecutor.shared.executeWithOutput(
                    executable: "/usr/bin/git",
                    arguments: ["show", "--format=", commit.id],
                    workingDirectory: path
                )
                diffOutput = result.stdout
            } catch {
                logger.error("Failed to load commit diff: \(error.localizedDescription)")
            }
        } else {
            // Load working changes diff
            await loadWorkingDiff()
        }
    }

    private func loadWorkingDiff() async {
        let path = worktreePath

        guard !path.isEmpty else { return }

        // Use libgit2 for working directory diff
        let result = await Task.detached {
            do {
                let repo = try Libgit2Repository(path: path)

                // Try combined diff (HEAD to workdir with index)
                let headDiff = try repo.diffUnified()
                if !headDiff.isEmpty {
                    return headDiff
                }

                // Fallback: staged diff
                let stagedDiff = try repo.diffStagedUnified()
                if !stagedDiff.isEmpty {
                    return stagedDiff
                }

                // Fallback: unstaged diff
                let unstagedDiff = try repo.diffUnstagedUnified()
                if !unstagedDiff.isEmpty {
                    return unstagedDiff
                }

                // Last resort: untracked files
                let status = try repo.status()
                if !status.untracked.isEmpty {
                    var output = ""
                    for entry in status.untracked.prefix(50) {
                        output += Self.buildFileDiff(file: entry.path, basePath: path)
                    }
                    return output
                }

                return ""
            } catch {
                return ""
            }
        }.value

        diffOutput = result
    }

    private func reloadDiff() {
        Task {
            await loadDiff(for: selectedHistoryCommit)
        }
    }

    private func reloadDiffDebounced() {
        // Cancel any pending reload
        diffReloadTask?.cancel()

        // Debounce by 300ms to avoid rapid reloads
        diffReloadTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(300))
            } catch {
                return  // Cancelled
            }
            guard !Task.isCancelled else { return }
            await loadDiff(for: selectedHistoryCommit)
        }
    }

    private static func buildFileDiff(file: String, basePath: String) -> String {
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
