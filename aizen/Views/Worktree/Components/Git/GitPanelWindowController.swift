//
//  GitPanelWindowController.swift
//  aizen
//
//  Window controller for the git panel
//

import AppKit
import SwiftUI
import os.log

class GitPanelWindowController: NSWindowController {
    private var windowDelegate: GitPanelWindowDelegate?

    convenience init(context: GitChangesContext, repositoryManager: RepositoryManager, onClose: @escaping () -> Void) {
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
        let repoName = context.worktree.repository?.name ?? "Repository"
        let worktreePath = context.worktree.path ?? ""
        window.title = repoName
        window.minSize = NSSize(width: 900, height: 600)

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
    let repositoryManager: RepositoryManager
    let onClose: () -> Void

    @State private var selectedTab: GitPanelTab = .git
    @State private var selectedBranchInfo: BranchInfo?
    @State private var showingBranchPicker: Bool = false
    @State private var currentOperation: GitToolbarOperation?

    // PR/MR state
    @State private var prStatus: PRStatus = .unknown
    @State private var hostingInfo: GitHostingInfo?
    @State private var showCLIInstallAlert: Bool = false
    @State private var prOperationInProgress: Bool = false

    @ObservedObject private var gitRepositoryService: GitRepositoryService

    private let gitHostingService = GitHostingService()

    private var worktree: Worktree { context.worktree }
    private var gitStatus: GitStatus { gitRepositoryService.currentStatus }
    private var isOperationPending: Bool { gitRepositoryService.isOperationPending }

    init(context: GitChangesContext, repositoryManager: RepositoryManager, onClose: @escaping () -> Void) {
        self.context = context
        self.repositoryManager = repositoryManager
        self.onClose = onClose
        self._gitRepositoryService = ObservedObject(wrappedValue: context.service)
    }

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen", category: "GitPanelToolbar")

    private var gitOperations: WorktreeGitOperations {
        WorktreeGitOperations(
            gitRepositoryService: gitRepositoryService,
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
            onClose: onClose
        )
        .toolbar {
             ToolbarItem(placement: .navigation) {
                    Picker("", selection: $selectedTab) {
                        ForEach(GitPanelTab.allCases, id: \.self) { tab in
                            Label(tab.displayName, systemImage: tab.icon).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
            }
            
            
            ToolbarItem(placement: .navigation) {
                 Spacer().frame(width: 12)
            }
            
          
            
             ToolbarItem(placement: .navigation) {
                 branchSelector
            }
            

            ToolbarItem(placement: .primaryAction) {
                prActionButton
            }

            ToolbarItem(placement: .primaryAction) {
                Spacer().frame(width: 16)
            }

            ToolbarItem(placement: .primaryAction) {
                gitActionsToolbar
            }
        }
        .onAppear {
            Task {
                await loadHostingInfo()
            }
        }
        .onChange(of: gitStatus.currentBranch) { _ in
            Task {
                await refreshPRStatus()
            }
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
                selectedBranch: $selectedBranchInfo,
                allowCreation: true,
                onCreateBranch: { branchName in
                    gitOperations.createBranch(branchName)
                }
            )
        }
        .onChange(of: selectedBranchInfo) { newBranch in
            if let branch = newBranch {
                gitOperations.switchBranch(branch.name)
            }
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
        .onChange(of: gitRepositoryService.isOperationPending) { pending in
            if !pending {
                currentOperation = nil
            }
        }
    }

    private func performOperation(_ operation: GitToolbarOperation, action: () -> Void) {
        currentOperation = operation
        action()
    }

    // MARK: - PR Actions

    private var isOnMainBranch: Bool {
        let branch = gitStatus.currentBranch.lowercased()
        return branch == "main" || branch == "master"
    }

    @ViewBuilder
    private var prActionButton: some View {
        if let info = hostingInfo, info.provider != .unknown, !isOnMainBranch {
            if prOperationInProgress {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text(info.provider == .gitlab ? "MR..." : "PR...")
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            } else {
                switch prStatus {
                case .unknown, .noPR:
                    Button {
                        createPR()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.pull")
                            Text(info.provider == .gitlab ? "Create MR" : "Create PR")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isOperationPending || gitStatus.currentBranch == nil)

                case .open(let number, let url, let mergeable, let title):
                    HStack(spacing: 4) {
                        Button {
                            if let prURL = URL(string: url) {
                                NSWorkspace.shared.open(prURL)
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "number")
                                Text("\(number)")
                            }
                        }
                        .buttonStyle(.bordered)
                        .help(title)

                        Button {
                            mergePR(number: number)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.triangle.merge")
                                Text("Merge")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(!mergeable || isOperationPending)
                        .help(mergeable ? "Merge this PR" : "PR cannot be merged (conflicts or checks failing)")
                    }

                case .merged, .closed:
                    Button {
                        createPR()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.pull")
                            Text(info.provider == .gitlab ? "Create MR" : "Create PR")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isOperationPending || gitStatus.currentBranch == nil)
                }
            }
        }
    }

    private func loadHostingInfo() async {
        guard let path = worktree.path else { return }
        hostingInfo = await gitHostingService.getHostingInfo(for: path)
        await refreshPRStatus()
    }

    private func refreshPRStatus() async {
        guard let path = worktree.path,
              let info = hostingInfo,
              info.cliInstalled && info.cliAuthenticated else {
            prStatus = .unknown
            return
        }

        let branch = gitStatus.currentBranch
        guard !branch.isEmpty else {
            prStatus = .unknown
            return
        }

        prStatus = await gitHostingService.getPRStatus(repoPath: path, branch: branch)
    }

    private func createPR() {
        guard let info = hostingInfo else { return }
        let branch = gitStatus.currentBranch
        guard !branch.isEmpty else { return }

        // Check if CLI is available
        if !info.cliInstalled || !info.cliAuthenticated {
            // For providers without CLI support, open browser directly
            if info.provider == .bitbucket || info.provider.cliName == nil {
                Task {
                    await gitHostingService.openInBrowser(
                        info: info,
                        action: .createPR(sourceBranch: branch, targetBranch: nil)
                    )
                }
            } else {
                showCLIInstallAlert = true
            }
            return
        }

        prOperationInProgress = true
        Task {
            do {
                guard let path = worktree.path else { return }
                try await gitHostingService.createPR(repoPath: path, sourceBranch: branch)
                await refreshPRStatus()
            } catch {
                logger.error("Failed to create PR: \(error.localizedDescription)")
                // Fallback to browser
                await gitHostingService.openInBrowser(
                    info: info,
                    action: .createPR(sourceBranch: branch, targetBranch: nil)
                )
            }
            prOperationInProgress = false
        }
    }

    private func mergePR(number: Int) {
        guard let info = hostingInfo else { return }

        if !info.cliInstalled || !info.cliAuthenticated {
            // Open PR in browser for manual merge
            if let url = gitHostingService.buildURL(info: info, action: .viewPR(number: number)) {
                NSWorkspace.shared.open(url)
            }
            return
        }

        prOperationInProgress = true
        Task {
            do {
                guard let path = worktree.path else { return }
                try await gitHostingService.mergePR(repoPath: path, prNumber: number)
                await refreshPRStatus()
                // Refresh git status after merge
                gitRepositoryService.reloadStatus()
            } catch {
                logger.error("Failed to merge PR: \(error.localizedDescription)")
            }
            prOperationInProgress = false
        }
    }
}
