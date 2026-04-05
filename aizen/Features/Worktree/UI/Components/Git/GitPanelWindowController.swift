//
//  GitPanelWindowController.swift
//  aizen
//
//  Window controller for the git panel
//

import AppKit
import SwiftUI
import os.log
import VVCode

class GitPanelWindowController: NSWindowController {
    private var windowDelegate: GitPanelWindowDelegate?

    convenience init(context: GitChangesContext, repositoryManager: WorkspaceRepositoryStore, onClose: @escaping () -> Void) {
        // Calculate 80% of main window size, with fallback defaults
        let mainWindowFrame = NSApp.mainWindow?.frame ?? NSRect(x: 0, y: 0, width: 1400, height: 900)
        let width = max(900, mainWindowFrame.width * 0.8)
        let height = max(600, mainWindowFrame.height * 0.8)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        // Exclude from macOS window restoration - we handle restoration ourselves
        window.isRestorable = false
        window.identifier = NSUserInterfaceItemIdentifier("GitPanelWindow")
        window.isExcludedFromWindowsMenu = false

        // Set title to repository name, subtitle to worktree path
        let repoName = context.worktree.repository?.name ?? "Project"
        let worktreePath = context.worktree.path ?? ""
        window.title = repoName
        window.minSize = NSSize(width: 900, height: 600)
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.titlebarSeparatorStyle = .none
        window.backgroundColor = GitPanelTheme.backgroundColor()

        let toolbar = NSToolbar(identifier: "GitPanelToolbar")
        toolbar.showsBaselineSeparator = false
        window.toolbar = toolbar

        self.init(window: window)

        // Create content with SwiftUI toolbar
        let content = GitPanelWindowContentWithToolbar(
            context: context,
            repositoryManager: repositoryManager,
            onClose: {
                window.close()
                onClose()
            }
        )
        .navigationSubtitle(worktreePath)
        .modifier(AppearanceModifier())

        window.contentView = NSHostingView(rootView: content)
        window.center()

        // Set up delegate to handle window close
        windowDelegate = GitPanelWindowDelegate(onClose: onClose)
        window.delegate = windowDelegate
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(nil)
    }
}

private class GitPanelWindowDelegate: NSObject, NSWindowDelegate {
    let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}

// MARK: - SwiftUI Wrapper with Toolbar

struct GitPanelWindowContentWithToolbar: View {
    let context: GitChangesContext
    let repositoryManager: WorkspaceRepositoryStore
    let onClose: () -> Void

    @State var selectedTab: GitPanelTab = .git
    @State var showingBranchPicker: Bool = false
    @State var currentOperation: GitToolbarOperation?

    // PR/MR state
    @State var prStatus: PRStatus = .unknown
    @State var hostingInfo: GitHostingInfo?
    @State var showCLIInstallAlert: Bool = false
    @State var prOperationInProgress: Bool = false
    @State var hostingInfoTask: Task<Void, Never>?
    @AppStorage(AppearanceSettings.gitDiffRenderStyleKey)
    private var diffRenderStyleRawValue: String = AppearanceSettings.defaultGitDiffRenderStyleRawValue

    let runtime: WorktreeRuntime
    @ObservedObject private var gitSummaryStore: GitSummaryStore
    @ObservedObject var gitOperationService: GitOperationService

    let gitHostingService = GitHostingService.shared

    var worktree: Worktree { context.worktree }
    var gitStatus: GitStatus { gitSummaryStore.status }
    var isOperationPending: Bool { gitOperationService.isOperationPending }
    var gitFeaturesAvailable: Bool { gitSummaryStore.repositoryState == .ready }

    var diffRenderStyleBinding: Binding<VVDiffRenderStyle> {
        Binding(
            get: {
                AppearanceSettings.gitDiffRenderStyle(from: diffRenderStyleRawValue)
            },
            set: { newValue in
                diffRenderStyleRawValue = AppearanceSettings.gitDiffRenderStyleRawValue(for: newValue)
            }
        )
    }

    init(context: GitChangesContext, repositoryManager: WorkspaceRepositoryStore, onClose: @escaping () -> Void) {
        self.context = context
        self.repositoryManager = repositoryManager
        self.onClose = onClose
        self.runtime = context.runtime
        self._gitSummaryStore = ObservedObject(wrappedValue: context.runtime.summaryStore)
        self._gitOperationService = ObservedObject(wrappedValue: context.runtime.operationService)
    }

    let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen", category: "GitPanelToolbar")

    var gitOperations: WorktreeGitOperations {
        WorktreeGitOperations(
            gitOperationService: gitOperationService,
            repositoryManager: repositoryManager,
            worktree: worktree,
            logger: logger
        )
    }

    enum GitToolbarOperation: String {
        case fetch = "Fetching..."
        case pull = "Pulling..."
        case push = "Pushing..."
        case createPR = "Creating PR..."
        case mergePR = "Merging..."
    }

}
