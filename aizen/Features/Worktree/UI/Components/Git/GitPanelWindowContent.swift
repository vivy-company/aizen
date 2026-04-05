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
    @State var leftPanelWidth: CGFloat = 350
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
    @AppStorage(AppearanceSettings.themeNameKey) var terminalThemeName = AppearanceSettings.defaultDarkTheme
    @AppStorage(AppearanceSettings.lightThemeNameKey) var terminalThemeNameLight = AppearanceSettings.defaultLightTheme
    @AppStorage(AppearanceSettings.usePerAppearanceThemeKey) var usePerAppearanceTheme = false
    @Environment(\.colorScheme) var colorScheme
    @ObservedObject var gitSummaryStore: GitSummaryStore
    @ObservedObject var gitDiffStore: GitDiffRuntimeStore
    @ObservedObject var gitOperationService: GitOperationService
    @ObservedObject var workflowService: WorkflowService

    let minLeftPanelWidth: CGFloat = 280
    let maxLeftPanelWidth: CGFloat = 500

    var worktree: Worktree { context.worktree }
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

    var allChangedFiles: [String] {
        cachedChangedFiles
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
