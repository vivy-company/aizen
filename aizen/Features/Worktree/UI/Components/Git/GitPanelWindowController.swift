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

    @State private var selectedTab: GitPanelTab = .git
    @State private var showingBranchPicker: Bool = false
    @State private var currentOperation: GitToolbarOperation?

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
    @ObservedObject private var gitOperationService: GitOperationService

    let gitHostingService = GitHostingService.shared

    var worktree: Worktree { context.worktree }
    var gitStatus: GitStatus { gitSummaryStore.status }
    var isOperationPending: Bool { gitOperationService.isOperationPending }
    private var gitFeaturesAvailable: Bool { gitSummaryStore.repositoryState == .ready }

    private var diffRenderStyleBinding: Binding<VVDiffRenderStyle> {
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

    private var gitOperations: WorktreeGitOperations {
        WorktreeGitOperations(
            gitOperationService: gitOperationService,
            repositoryManager: repositoryManager,
            worktree: worktree,
            logger: logger
        )
    }

    private enum GitToolbarOperation: String {
        case fetch = "Fetching..."
        case pull = "Pulling..."
        case push = "Pushing..."
        case createPR = "Creating PR..."
        case mergePR = "Merging..."
    }

    var body: some View {
        GitPanelWindowContent(
            context: context,
            repositoryManager: repositoryManager,
            selectedTab: $selectedTab,
            diffRenderStyle: diffRenderStyleBinding,
            onClose: onClose
        )
        .toolbar {
            // Group 1: Stash (git), Comments
            ToolbarItem(placement: .navigation) {
                Picker("", selection: $selectedTab) {
                    Label(GitPanelTab.git.displayName, systemImage: GitPanelTab.git.icon).tag(GitPanelTab.git)
                    Label(GitPanelTab.comments.displayName, systemImage: GitPanelTab.comments.icon).tag(GitPanelTab.comments)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            // Fixed spacer
            ToolbarItem(placement: .navigation) {
                Spacer().frame(width: 24)
            }

            // Group 2: History, PRs, Workflows
            ToolbarItem(placement: .navigation) {
                Picker("", selection: $selectedTab) {
                    Label(GitPanelTab.history.displayName, systemImage: GitPanelTab.history.icon).tag(GitPanelTab.history)
                    Label(GitPanelTab.prs.displayName, systemImage: GitPanelTab.prs.icon).tag(GitPanelTab.prs)
                    Label(GitPanelTab.workflows.displayName, systemImage: GitPanelTab.workflows.icon).tag(GitPanelTab.workflows)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            ToolbarItem(placement: .navigation) {
                Spacer().frame(width: 12)
            }

            ToolbarItem(placement: .navigation) {
                if gitFeaturesAvailable {
                    branchSelector
                }
            }
            

            ToolbarItem(placement: .primaryAction) {
                if gitFeaturesAvailable {
                    prActionButton
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Spacer().frame(width: 16)
            }

            ToolbarItem(placement: .primaryAction) {
                if gitFeaturesAvailable {
                    gitActionsToolbar
                }
            }
        }
        .task(id: selectedTab) {
            guard selectedTab == .prs else { return }
            loadHostingInfoIfNeeded()
        }
        .task(id: gitStatus.currentBranch) {
            await refreshPRStatus()
        }
        .alert("CLI Not Installed", isPresented: $showCLIInstallAlert) {
            if let info = hostingInfo {
                Button("Install Instructions") {
                    if let url = URL(string: "https://\(info.provider == .github ? "cli.github.com" : info.provider == .gitlab ? "gitlab.com/gitlab-org/cli" : "")") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Button("Open in Browser") {
                    let branch = gitStatus.currentBranch
                    guard !branch.isEmpty else { return }
                    Task {
                        await gitHostingService.openInBrowser(
                            info: info,
                            action: .createPR(sourceBranch: branch, targetBranch: nil)
                        )
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
        } message: {
            if let info = hostingInfo {
                Text("The \(info.provider.displayName) CLI (\(info.provider.cliName ?? "")) is not installed or not authenticated.\n\nInstall with: \(info.provider.installInstructions)")
            }
        }
        .sheet(isPresented: $showingBranchPicker) {
            BranchSelectorView(
                repository: worktree.repository!,
                repositoryManager: repositoryManager,
                selectedBranch: .constant(nil),
                onSelectBranch: { branch in
                    gitOperations.switchBranch(branch.name)
                },
                allowCreation: true,
                onCreateBranch: { branchName in
                    gitOperations.createBranch(branchName)
                }
            )
        }
    }

    private var branchSelector: some View {
        Button {
            showingBranchPicker = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.branch")
                Text(gitStatus.currentBranch.isEmpty ? "HEAD" : gitStatus.currentBranch)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.bordered)
    }

    private var gitActionsToolbar: some View {
        HStack(spacing: 4) {
            if let operation = currentOperation {
                // Show loading state
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text(operation.rawValue)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            } else if gitStatus.aheadCount > 0 && gitStatus.behindCount > 0 {
                Button {
                    performOperation(.pull) { gitOperations.pull() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down")
                        Text("Pull (\(gitStatus.behindCount))")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isOperationPending)

                Button {
                    performOperation(.push) { gitOperations.push() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up")
                        Text("Push (\(gitStatus.aheadCount))")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isOperationPending)
            } else if gitStatus.aheadCount > 0 {
                Button {
                    performOperation(.push) { gitOperations.push() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up")
                        Text("Push (\(gitStatus.aheadCount))")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isOperationPending)
            } else {
                Button {
                    performOperation(.fetch) { gitOperations.fetch() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("Fetch")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isOperationPending)
            }

            if currentOperation == nil {
                Menu {
                    Button {
                        performOperation(.fetch) { gitOperations.fetch() }
                    } label: {
                        Label("Fetch", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(isOperationPending)

                    Button {
                        performOperation(.pull) { gitOperations.pull() }
                    } label: {
                        Label("Pull", systemImage: "arrow.down")
                    }
                    .disabled(isOperationPending)

                    Button {
                        performOperation(.push) { gitOperations.push() }
                    } label: {
                        Label("Push", systemImage: "arrow.up")
                    }
                    .disabled(isOperationPending)
                } label: {
                    Image(systemName: "chevron.down")
                }
                .menuIndicator(.hidden)
                .buttonStyle(.bordered)
                .disabled(isOperationPending)
            }
        }
        .task(id: gitOperationService.isOperationPending) {
            guard !gitOperationService.isOperationPending else { return }
            currentOperation = nil
        }
    }

    private func performOperation(_ operation: GitToolbarOperation, action: () -> Void) {
        currentOperation = operation
        action()
    }

}
