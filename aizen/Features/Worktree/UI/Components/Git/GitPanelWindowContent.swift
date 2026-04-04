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

struct GitPanelWindowContent: View {
    let context: GitChangesContext
    let repositoryManager: WorkspaceRepositoryStore
    @Binding var selectedTab: GitPanelTab
    @Binding var diffRenderStyle: VVDiffRenderStyle
    let onClose: () -> Void
    let runtime: WorktreeRuntime

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen", category: "GitPanelWindow")
    @State var selectedHistoryCommit: GitCommit?
    @State var historyDiffOutput: String = ""
    @State private var leftPanelWidth: CGFloat = 350
    @State var visibleFile: String?
    @State var scrollToFile: String?
    @State var commentPopoverLine: DiffLine?
    @State var commentPopoverFilePath: String?
    @State var showAgentPicker: Bool = false
    @State var cachedChangedFiles: [String] = []

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
    @ObservedObject var gitDiffStore: GitDiffRuntimeStore
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

    var effectiveDiffOutput: String {
        selectedHistoryCommit == nil ? gitDiffStore.diffOutput : historyDiffOutput
    }

}
