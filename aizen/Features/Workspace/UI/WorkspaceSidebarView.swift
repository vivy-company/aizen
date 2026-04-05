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
        VStack(spacing: 0) {
            // Workspace section
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("workspace.sidebar.title")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    Spacer(minLength: 8)
                    repositoryControls
                }
                    .padding(.horizontal, 12)

                // Current workspace button
                workspacePicker
                .padding(.horizontal, 12)
            }
            .padding(.top, 12)
            .padding(.bottom, 4)

            if repositoryFiltersVisible {
                repositoryFiltersInline
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
                    .padding(.bottom, 6)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if repositorySearchVisible {
                repositorySearchInline
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
                    .padding(.bottom, 6)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            repositoriesContent
        }
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
        repositoryManager: WorkspaceRepositoryStore(viewContext: PersistenceController.preview.container.viewContext)
    )
}
