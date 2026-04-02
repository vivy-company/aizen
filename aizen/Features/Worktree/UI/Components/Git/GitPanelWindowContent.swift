//
//  GitPanelWindowContent.swift
//  aizen
//
//  Main content view for the git panel window with toolbar tabs
//

import AppKit
import SwiftUI
import os.log
import VVCode

enum GitPanelTheme {
    static func effectiveThemeName(
        colorScheme: ColorScheme? = nil,
        defaults: UserDefaults = .standard
    ) -> String {
        AppearanceSettings.effectiveThemeName(colorScheme: colorScheme, defaults: defaults)
    }

    static func backgroundColor(
        colorScheme: ColorScheme? = nil,
        defaults: UserDefaults = .standard
    ) -> NSColor {
        GhosttyThemeParser.loadBackgroundColor(named: effectiveThemeName(colorScheme: colorScheme, defaults: defaults))
    }
}

enum GitWindowDividerStyle {
    static func color(opacity: CGFloat = 1.0) -> Color {
        let base = contrastedBackgroundColor(strength: 0.06)
        return Color(nsColor: base.withAlphaComponent(0.5 * opacity))
    }

    static func splitterColor(opacity: CGFloat = 1.0) -> Color {
        Color(nsColor: .separatorColor).opacity(0.85 * opacity)
    }

    private static func contrastedBackgroundColor(strength: CGFloat) -> NSColor {
        let themeBackground = GitPanelTheme.backgroundColor()
        let background = themeBackground.usingColorSpace(.extendedSRGB) ?? themeBackground

        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        background.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        let luminance = (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)
        let delta = luminance < 0.5 ? strength : -strength

        let adjustedRed = min(max(red + delta, 0), 1)
        let adjustedGreen = min(max(green + delta, 0), 1)
        let adjustedBlue = min(max(blue + delta, 0), 1)

        return NSColor(
            red: adjustedRed,
            green: adjustedGreen,
            blue: adjustedBlue,
            alpha: 1
        )
    }
}

struct GitWindowDivider: View {
    var opacity: CGFloat = 1.0

    var body: some View {
        Rectangle()
            .fill(GitWindowDividerStyle.color(opacity: opacity))
            .frame(height: 0.5)
            .accessibilityHidden(true)
    }
}

struct GitResizableDivider: View {
    let onDragChanged: (DragGesture.Value) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppearanceSettings.themeNameKey) private var terminalThemeName = AppearanceSettings.defaultDarkTheme
    @AppStorage(AppearanceSettings.lightThemeNameKey) private var terminalThemeNameLight = AppearanceSettings.defaultLightTheme
    @AppStorage(AppearanceSettings.usePerAppearanceThemeKey) private var usePerAppearanceTheme = false

    @State private var didPushCursor = false
    private let lineWidth: CGFloat = 1
    private let hitWidth: CGFloat = 14

    private var effectiveThemeName: String {
        guard usePerAppearanceTheme else { return terminalThemeName }
        return AppearanceSettings.effectiveThemeName(colorScheme: colorScheme)
    }

    var body: some View {
        Rectangle()
            .fill(Color(nsColor: GhosttyThemeParser.loadDividerColor(named: effectiveThemeName)))
            .frame(width: lineWidth)
            .frame(width: hitWidth)
        .contentShape(Rectangle())
        .padding(.horizontal, -(hitWidth - lineWidth) / 2)
        .gesture(
            DragGesture()
                .onChanged(onDragChanged)
        )
        .onHover { hovering in
            if hovering && !didPushCursor {
                NSCursor.resizeLeftRight.push()
                didPushCursor = true
            } else if !hovering && didPushCursor {
                NSCursor.pop()
                didPushCursor = false
            }
        }
        .onDisappear {
            if didPushCursor {
                NSCursor.pop()
                didPushCursor = false
            }
        }
    }
}

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
    let repositoryManager: WorkspaceRepositoryStore
    @Binding var selectedTab: GitPanelTab
    @Binding var diffRenderStyle: VVDiffRenderStyle
    let onClose: () -> Void
    private let runtime: WorktreeRuntime

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen", category: "GitPanelWindow")
    @State private var selectedHistoryCommit: GitCommit?
    @State private var historyDiffOutput: String = ""
    @State private var leftPanelWidth: CGFloat = 350
    @State private var visibleFile: String?
    @State private var scrollToFile: String?
    @State private var commentPopoverLine: DiffLine?
    @State private var commentPopoverFilePath: String?
    @State private var showAgentPicker: Bool = false
    @State private var cachedChangedFiles: [String] = []

    @StateObject private var reviewManager = ReviewSessionStore()
    @State private var selectedWorkflowForTrigger: Workflow?
    @State private var isInitializingGit = false
    @State private var gitInitializationError: String?

    @AppStorage(AppearanceSettings.codeFontFamilyKey) private var editorFontFamily: String = AppearanceSettings.defaultCodeFontFamily
    @AppStorage(AppearanceSettings.diffFontSizeKey) private var diffFontSize: Double = AppearanceSettings.defaultDiffFontSize
    @AppStorage(AppearanceSettings.themeNameKey) private var terminalThemeName = AppearanceSettings.defaultDarkTheme
    @AppStorage(AppearanceSettings.lightThemeNameKey) private var terminalThemeNameLight = AppearanceSettings.defaultLightTheme
    @AppStorage(AppearanceSettings.usePerAppearanceThemeKey) private var usePerAppearanceTheme = false
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var gitSummaryStore: GitSummaryStore
    @ObservedObject private var gitDiffStore: GitDiffRuntimeStore
    @ObservedObject private var gitOperationService: GitOperationService
    @ObservedObject private var workflowService: WorkflowService

    private let minLeftPanelWidth: CGFloat = 280
    private let maxLeftPanelWidth: CGFloat = 500

    private var worktree: Worktree { context.worktree }
    private var worktreePath: String { worktree.path ?? "" }

    init(
        context: GitChangesContext,
        repositoryManager: WorkspaceRepositoryStore,
        selectedTab: Binding<GitPanelTab>,
        diffRenderStyle: Binding<VVDiffRenderStyle>,
        onClose: @escaping () -> Void
    ) {
        self.context = context
        self.repositoryManager = repositoryManager
        self._selectedTab = selectedTab
        self._diffRenderStyle = diffRenderStyle
        self.onClose = onClose
        self.runtime = context.runtime
        self._gitSummaryStore = ObservedObject(wrappedValue: context.runtime.summaryStore)
        self._gitDiffStore = ObservedObject(wrappedValue: context.runtime.diffStore)
        self._gitOperationService = ObservedObject(wrappedValue: context.runtime.operationService)
        self._workflowService = ObservedObject(wrappedValue: context.runtime.workflowService)
    }

    private var gitOperations: WorktreeGitOperations {
        WorktreeGitOperations(
            gitOperationService: gitOperationService,
            repositoryManager: repositoryManager,
            worktree: worktree,
            logger: logger
        )
    }

    private var gitStatus: GitStatus { gitSummaryStore.status }

    private var repositoryState: GitRepositoryState {
        gitSummaryStore.repositoryState
    }

    private var shouldShowInitializeGitView: Bool {
        repositoryState == .notRepository
    }

    private var allChangedFiles: [String] {
        cachedChangedFiles
    }

    private var effectiveThemeName: String {
        guard usePerAppearanceTheme else { return terminalThemeName }
        return AppearanceSettings.effectiveThemeName(colorScheme: colorScheme)
    }

    private struct RuntimeVisibilityKey: Equatable {
        let selectedTab: GitPanelTab
        let selectedHistoryCommitID: String?
    }

    private var runtimeVisibilityKey: RuntimeVisibilityKey {
        RuntimeVisibilityKey(
            selectedTab: selectedTab,
            selectedHistoryCommitID: selectedHistoryCommit?.id
        )
    }

    private var surfaceColor: Color {
        Color(nsColor: GhosttyThemeParser.loadBackgroundColor(named: effectiveThemeName))
    }

    var body: some View {
        Group {
            if shouldShowInitializeGitView {
                initializeGitView
            } else if selectedTab == .prs {
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
        .background(surfaceColor)
        .toolbarBackground(surfaceColor, for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
        .onAppear {
            syncRuntimeVisibility()
            reviewManager.load(for: worktreePath)
            _ = updateChangedFilesCache()
        }
        .onDisappear {
            runtime.setGitPanelVisible(false, showsWorkingDiff: false, showsWorkflow: false)
        }
        .task(id: gitStatus) {
            let changed = updateChangedFilesCache()
            guard changed, selectedHistoryCommit != nil else { return }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await synchronizeDiffOutput(for: selectedHistoryCommit)
        }
        .task(id: selectedHistoryCommit?.id) {
            await synchronizeDiffOutput(for: selectedHistoryCommit)
        }
        .task(id: runtimeVisibilityKey) {
            syncRuntimeVisibility()
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
                currentBranch: gitStatus.currentBranch.isEmpty ? "main" : gitStatus.currentBranch,
                service: workflowService,
                onDismiss: {
                    selectedWorkflowForTrigger = nil
                }
            )
        }
    }

    private var initializeGitView: some View {
        VStack(spacing: 14) {
            Image(systemName: "externaldrive.badge.plus")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)

            Text("This folder is not a Git project.")
                .font(.headline)

            Text("Initialize Git to enable commits, branches, history, and pull requests.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            if let error = gitInitializationError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            HStack(spacing: 10) {
                Button("Close") {
                    onClose()
                }
                .buttonStyle(.bordered)

                Button {
                    initializeGit()
                } label: {
                    if isInitializingGit {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 80)
                    } else {
                        Text("Initialize Git")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isInitializingGit || worktreePath.isEmpty)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
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
                    Clipboard.copy(markdown)
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
            isOperationPending: gitOperationService.isOperationPending,
            selectedDiffFile: visibleFile,
            onStageFile: { file in
                gitOperations.stageFile(file)
            },
            onUnstageFile: { file in
                gitOperations.unstageFile(file)
            },
            onStageAll: { completion in
                gitOperations.stageAll {
                    completion()
                }
            },
            onUnstageAll: {
                gitOperations.unstageAll()
            },
            onDiscardAll: {
                gitOperations.discardAll()
            },
            onCleanUntracked: {
                gitOperations.cleanUntracked()
            },
            onCommit: { message in
                gitOperations.commit(message)
            },
            onAmendCommit: { message in
                gitOperations.amendCommit(message)
            },
            onCommitWithSignoff: { message in
                gitOperations.commitWithSignoff(message)
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

    private var diffRenderStylePicker: some View {
        Picker("Diff Layout", selection: $diffRenderStyle) {
            Text("Inline").tag(VVDiffRenderStyle.inline)
            Text("Split").tag(VVDiffRenderStyle.sideBySide)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
        .frame(width: 128)
        .help("Switch between inline and side-by-side diff layouts")
    }

    private func changesDiffHeader() -> some View {
        HStack(spacing: 8) {
            Image(systemName: GitPanelTab.git.icon)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Text(GitPanelTab.git.displayName)
                .font(.system(size: 13, weight: .medium))

            Spacer()

            diffRenderStylePicker
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
    }

    private func diffPanelHeader(for commit: GitCommit) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Text(commit.shortHash)
                .font(.system(size: 13, weight: .medium, design: .monospaced))

            Text(commit.message)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            diffRenderStylePicker

            Button(String(localized: "git.panel.backToChanges")) {
                selectedHistoryCommit = nil
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
    }

    private var diffPanel: some View {
        VStack(spacing: 0) {
            if let commit = selectedHistoryCommit {
                diffPanelHeader(for: commit)
            } else {
                changesDiffHeader()
            }

            if selectedHistoryCommit == nil && allChangedFiles.isEmpty {
                AllFilesDiffEmptyView()
            } else if effectiveDiffOutput.isEmpty {
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
                    diffOutput: effectiveDiffOutput,
                    fontSize: diffFontSize,
                    fontFamily: editorFontFamily,
                    repoPath: worktreePath,
                    renderStyle: diffRenderStyle,
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
        .task(id: effectiveDiffOutput) {
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
        GitResizableDivider { value in
            let newWidth = leftPanelWidth + value.translation.width
            leftPanelWidth = min(max(newWidth, minLeftPanelWidth), maxLeftPanelWidth)
        }
    }

    // MARK: - Helper Methods

    private func initializeGit() {
        guard !isInitializingGit else { return }
        guard !worktreePath.isEmpty else { return }

        isInitializingGit = true
        gitInitializationError = nil

        Task {
            do {
                try await repositoryManager.initializeGit(at: worktreePath)
                if let repository = worktree.repository {
                    try await repositoryManager.refreshRepository(repository)
                }

                await MainActor.run {
                    runtime.refreshSummary(lightweight: false)
                    runtime.refreshWorkingDiffNow()
                    isInitializingGit = false
                }
            } catch {
                await MainActor.run {
                    gitInitializationError = error.localizedDescription
                    isInitializingGit = false
                }
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

    @MainActor
    private func synchronizeDiffOutput(for commit: GitCommit?) async {
        let path = worktreePath
        guard !path.isEmpty else {
            applyDiffOutput("")
            return
        }

        let commitID = commit?.id
        guard let commitID else {
            applyDiffOutput(gitDiffStore.diffOutput)
            return
        }

        let output = await Self.loadCommitDiff(path: path, commitID: commitID)
        guard !Task.isCancelled else { return }
        guard worktreePath == path else { return }
        guard selectedHistoryCommit?.id == commitID else { return }
        applyDiffOutput(output)
    }

    private func applyDiffOutput(_ output: String) {
        if historyDiffOutput != output {
            historyDiffOutput = output
        }
    }

    private var effectiveDiffOutput: String {
        selectedHistoryCommit == nil ? gitDiffStore.diffOutput : historyDiffOutput
    }

    private func syncRuntimeVisibility() {
        let shouldUseWorkingDiff = selectedHistoryCommit == nil && selectedTab != .workflows && selectedTab != .prs
        runtime.setGitPanelVisible(true, showsWorkingDiff: shouldUseWorkingDiff, showsWorkflow: selectedTab == .workflows)
    }

    nonisolated private static func loadCommitDiff(path: String, commitID: String) async -> String {
        do {
            let result = try await ProcessExecutor.shared.executeWithOutput(
                executable: "/usr/bin/git",
                arguments: ["show", "--format=", commitID],
                workingDirectory: path
            )
            return result.stdout
        } catch {
            return ""
        }
    }

}
