//
//  WorkspaceSidebarView.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import SwiftUI
import CoreData
import UniformTypeIdentifiers
import os.log

struct WorkspaceSidebarView: View {
    let logger = Logger.workspace
    let workspaces: [Workspace]
    @Binding var selectedWorkspace: Workspace?
    @Binding var isCrossProjectSelected: Bool
    @Binding var selectedRepository: Repository?
    @Binding var selectedWorktree: Worktree?
    @Binding var searchText: String
    @Binding var showingAddRepository: Bool

    @ObservedObject var repositoryManager: WorkspaceRepositoryStore
    @ObservedObject var workspaceGraphQueryController: WorkspaceGraphQueryController
    @Environment(\.controlActiveState) var controlActiveState
    @StateObject var licenseManager = LicenseStateStore.shared
    @State var showingWorkspaceSheet = false
    @State var showingWorkspaceSwitcher = false
    @State var showingSupportSheet = false
    @State var showingRepositorySearch = false
    @State var showingRepositoryFilters = false
    @State var workspaceToEdit: Workspace?
    @State var refreshTask: Task<Void, Never>?
    @State var missingRepository: WorkspaceRepositoryStore.MissingRepository?
    @AppStorage("repositoryStatusFilters") var storedStatusFilters: String = ""

    let refreshInterval: TimeInterval = 30.0
    let crossProjectRepositoryMarker = "__aizen.cross_project.workspace_repo__"

    var body: some View {
        sidebarShell
        .navigationTitle(LocalizedStringKey("workspace.repositories.title"))
        .workspaceSidebarPresentation(view: self)
        .onAppear {
            startPeriodicRefresh()
        }
        .onDisappear {
            stopPeriodicRefresh()
        }
    }
}

#Preview {
    WorkspaceSidebarView(
        workspaces: [],
        selectedWorkspace: .constant(nil),
        isCrossProjectSelected: .constant(false),
        selectedRepository: .constant(nil),
        selectedWorktree: .constant(nil),
        searchText: .constant(""),
        showingAddRepository: .constant(false),
        repositoryManager: WorkspaceRepositoryStore(viewContext: PersistenceController.preview.container.viewContext),
        workspaceGraphQueryController: WorkspaceGraphQueryController(
            viewContext: PersistenceController.preview.container.viewContext
        )
    )
}
