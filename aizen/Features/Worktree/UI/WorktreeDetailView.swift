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
    @ObservedObject var scene: WorktreeSceneStore
    @ObservedObject var worktree: Worktree
    @ObservedObject var repositoryManager: WorkspaceRepositoryStore
    @ObservedObject var navigationSelectionStore: AppNavigationSelectionStore
    @ObservedObject var appDetector = AppDetector.shared
    @Binding var gitChangesContext: GitChangesContext?
    var onWorktreeDeleted: ((Worktree?) -> Void)?
    let showZenModeButton: Bool
    let isActive: Bool

    let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen", category: "WorktreeDetailView")

    @ObservedObject var viewModel: WorktreeDetailStore

    @AppStorage("showOpenInApp") var showOpenInApp = true
    @AppStorage("showGitStatus") var showGitStatus = true
    @AppStorage("showXcodeBuild") var showXcodeBuild = true
    @AppStorage("zenModeEnabled") var zenModeEnabled = false
    let worktreeRuntime: WorktreeRuntime
    @ObservedObject var gitSummaryStore: GitSummaryStore
    @ObservedObject var xcodeBuildManager: XcodeBuildStore
    @State var projectSearchWindowController: ProjectSearchWindowController?
    @State var searchOpenRequest: SearchOpenRequest?
    @Environment(\.colorScheme) var colorScheme

    init(
        scene: WorktreeSceneStore,
        navigationSelectionStore: AppNavigationSelectionStore,
        gitChangesContext: Binding<GitChangesContext?>,
        onWorktreeDeleted: ((Worktree?) -> Void)? = nil,
        showZenModeButton: Bool = true,
        isActive: Bool
    ) {
        self.scene = scene
        self.worktree = scene.worktree
        self.repositoryManager = scene.repositoryManager
        self.navigationSelectionStore = navigationSelectionStore
        _gitChangesContext = gitChangesContext
        self.onWorktreeDeleted = onWorktreeDeleted
        self.showZenModeButton = showZenModeButton
        self.isActive = isActive
        let runtime = scene.runtime
        self.worktreeRuntime = runtime
        _viewModel = ObservedObject(wrappedValue: scene.detailStore)
        _gitSummaryStore = ObservedObject(wrappedValue: runtime.summaryStore)
        _xcodeBuildManager = ObservedObject(wrappedValue: runtime.xcodeBuildManager)
    }

    var lastOpenedApp: DetectedApp? {
        get { scene.lastOpenedApp }
        nonmutating set { scene.lastOpenedApp = newValue }
    }

    var body: some View {
        NavigationStack {
            navigationContent
        }
    }

}

#Preview {
    WorktreeDetailView(
        scene: WorktreeSceneStore(
            worktree: Worktree(),
            repositoryManager: WorkspaceRepositoryStore(viewContext: PersistenceController.preview.container.viewContext),
            viewContext: PersistenceController.preview.container.viewContext
        ),
        navigationSelectionStore: AppNavigationSelectionStore(),
        gitChangesContext: .constant(nil),
        isActive: true
    )
}
