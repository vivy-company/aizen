//
//  WorktreeDetailView.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import ACP
import Combine
import os.log
import SwiftUI

struct WorktreeDetailView: View {
    @ObservedObject var worktree: Worktree
    @ObservedObject var repositoryManager: WorkspaceRepositoryStore
    @ObservedObject var appDetector = AppDetector.shared
    @Binding var gitChangesContext: GitChangesContext?
    var onWorktreeDeleted: ((Worktree?) -> Void)?
    let showZenModeButton: Bool

    let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen", category: "WorktreeDetailView")

    @StateObject var viewModel: WorktreeDetailStore
    @ObservedObject var tabStateManager: WorktreeTabStateStore

    @AppStorage("showChatTab") var showChatTab = true
    @AppStorage("showTerminalTab") var showTerminalTab = true
    @AppStorage("showFilesTab") var showFilesTab = true
    @AppStorage("showBrowserTab") var showBrowserTab = true
    @AppStorage("showOpenInApp") var showOpenInApp = true
    @AppStorage("showGitStatus") var showGitStatus = true
    @AppStorage("showXcodeBuild") var showXcodeBuild = true
    @AppStorage("zenModeEnabled") var zenModeEnabled = false
    @State var selectedTab = "chat"
    @State var lastOpenedApp: DetectedApp?
    let worktreeRuntime: WorktreeRuntime
    @ObservedObject var gitSummaryStore: GitSummaryStore
    @ObservedObject var xcodeBuildManager: XcodeBuildStore
    @StateObject var tabConfig = TabConfigurationStore.shared
    @State var fileSearchWindowController: FileSearchWindowController?
    @State var fileToOpenFromSearch: String?
    @State var cachedTerminalBackgroundColor: Color?
    @State var hasLoadedTabState = false
    @Environment(\.colorScheme) var colorScheme

    init(
        worktree: Worktree,
        repositoryManager: WorkspaceRepositoryStore,
        tabStateManager: WorktreeTabStateStore,
        gitChangesContext: Binding<GitChangesContext?>,
        onWorktreeDeleted: ((Worktree?) -> Void)? = nil,
        showZenModeButton: Bool = true
    ) {
        self.worktree = worktree
        self.repositoryManager = repositoryManager
        self.tabStateManager = tabStateManager
        _gitChangesContext = gitChangesContext
        self.onWorktreeDeleted = onWorktreeDeleted
        self.showZenModeButton = showZenModeButton
        let runtime = WorktreeRuntimeCoordinator.shared.runtime(for: worktree.path ?? "")
        self.worktreeRuntime = runtime
        _viewModel = StateObject(wrappedValue: WorktreeDetailStore(worktree: worktree, repositoryManager: repositoryManager))
        _gitSummaryStore = ObservedObject(wrappedValue: runtime.summaryStore)
        _xcodeBuildManager = ObservedObject(wrappedValue: runtime.xcodeBuildManager)
    }

    var visibleTabIds: [String] {
        tabConfig.tabOrder
            .map(\.id)
            .filter { isTabVisible($0) }
    }

    func validateSelectedTab() {
        let visibleTabs = tabConfig.tabOrder.filter { isTabVisible($0.id) }
        if !visibleTabs.contains(where: { $0.id == selectedTab }) {
            selectedTab = visibleTabs.first?.id ?? "files"
        }
    }

    var body: some View {
        NavigationStack {
            navigationContent
        }
    }

}

#Preview {
    WorktreeDetailView(
        worktree: Worktree(),
        repositoryManager: WorkspaceRepositoryStore(viewContext: PersistenceController.preview.container.viewContext),
        tabStateManager: WorktreeTabStateStore(),
        gitChangesContext: .constant(nil)
    )
}
