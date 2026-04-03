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
    @State var selectedHistoryCommit: GitCommit?
    @State private var historyDiffOutput: String = ""
    @State private var leftPanelWidth: CGFloat = 350
    @State var visibleFile: String?
    @State var scrollToFile: String?
    @State var commentPopoverLine: DiffLine?
    @State var commentPopoverFilePath: String?
    @State var showAgentPicker: Bool = false
    @State private var cachedChangedFiles: [String] = []

    @StateObject var reviewManager = ReviewSessionStore()
    @State var selectedWorkflowForTrigger: Workflow?
    @State var isInitializingGit = false
    @State var gitInitializationError: String?

    @AppStorage(AppearanceSettings.codeFontFamilyKey) var editorFontFamily: String = AppearanceSettings.defaultCodeFontFamily
    @AppStorage(AppearanceSettings.diffFontSizeKey) var diffFontSize: Double = AppearanceSettings.defaultDiffFontSize
    @AppStorage(AppearanceSettings.themeNameKey) private var terminalThemeName = AppearanceSettings.defaultDarkTheme
    @AppStorage(AppearanceSettings.lightThemeNameKey) private var terminalThemeNameLight = AppearanceSettings.defaultLightTheme
    @AppStorage(AppearanceSettings.usePerAppearanceThemeKey) private var usePerAppearanceTheme = false
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var gitSummaryStore: GitSummaryStore
    @ObservedObject private var gitDiffStore: GitDiffRuntimeStore
    @ObservedObject var gitOperationService: GitOperationService
    @ObservedObject var workflowService: WorkflowService

    private let minLeftPanelWidth: CGFloat = 280
    private let maxLeftPanelWidth: CGFloat = 500

    private var worktree: Worktree { context.worktree }
    var worktreePath: String { worktree.path ?? "" }

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

    var gitOperations: WorktreeGitOperations {
        WorktreeGitOperations(
            gitOperationService: gitOperationService,
            repositoryManager: repositoryManager,
            worktree: worktree,
            logger: logger
        )
    }

    var gitStatus: GitStatus { gitSummaryStore.status }

    private var repositoryState: GitRepositoryState {
        gitSummaryStore.repositoryState
    }

    private var shouldShowInitializeGitView: Bool {
        repositoryState == .notRepository
    }

    var allChangedFiles: [String] {
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

    // MARK: - Diff Panel

    // MARK: - Right Panel

    // MARK: - Divider

    private var resizableDivider: some View {
        GitResizableDivider { value in
            let newWidth = leftPanelWidth + value.translation.width
            leftPanelWidth = min(max(newWidth, minLeftPanelWidth), maxLeftPanelWidth)
        }
    }

    // MARK: - Helper Methods

    func initializeGit() {
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

    func validateCommentsAgainstDiff() {
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

    var effectiveDiffOutput: String {
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
