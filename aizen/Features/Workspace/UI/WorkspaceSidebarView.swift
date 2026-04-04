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
    @StateObject private var licenseManager = LicenseStateStore.shared
    @State var showingWorkspaceSheet = false
    @State var showingWorkspaceSwitcher = false
    @State var showingSupportSheet = false
    @State var showingRepositorySearch = false
    @State var showingRepositoryFilters = false
    @State var workspaceToEdit: Workspace?
    @State var refreshTask: Task<Void, Never>?
    @State var missingRepository: WorkspaceRepositoryStore.MissingRepository?
    @AppStorage("repositoryStatusFilters") var storedStatusFilters: String = ""

    var selectedStatusFilters: Set<ItemStatus> {
        ItemStatus.decode(storedStatusFilters)
    }

    private var isLicenseActive: Bool {
        switch licenseManager.status {
        case .active, .offlineGrace:
            return true
        default:
            return false
        }
    }

    let refreshInterval: TimeInterval = 30.0
    private let crossProjectRepositoryMarker = "__aizen.cross_project.workspace_repo__"

    private func isCrossProjectRepository(_ repository: Repository) -> Bool {
        repository.isCrossProject || repository.note == crossProjectRepositoryMarker
    }

    var filteredRepositories: [Repository] {
        guard let workspace = selectedWorkspace else { return [] }
        let repos = (workspace.repositories as? Set<Repository>) ?? []

        // Filter out deleted Core Data objects
        var validRepos = repos.filter { !$0.isDeleted && !isCrossProjectRepository($0) }

        // Apply status filter
        if !selectedStatusFilters.isEmpty && selectedStatusFilters.count < ItemStatus.allCases.count {
            validRepos = validRepos.filter { repo in
                let status = ItemStatus(rawValue: repo.status ?? "active") ?? .active
                return selectedStatusFilters.contains(status)
            }
        }

        if searchText.isEmpty {
            return validRepos.sorted { ($0.name ?? "") < ($1.name ?? "") }
        } else {
            return validRepos
                .filter { ($0.name ?? "").localizedCaseInsensitiveContains(searchText) }
                .sorted { ($0.name ?? "") < ($1.name ?? "") }
        }
    }

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

            crossProjectRow
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .padding(.bottom, 6)

            projectsSectionTitle

            // Repository list
            if filteredRepositories.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    if selectedStatusFilters.count < ItemStatus.allCases.count && !selectedStatusFilters.isEmpty {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.system(size: 32))
                            .foregroundStyle(.tertiary)
                        Text("sidebar.empty.filtered")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button {
                            storedStatusFilters = ""
                        } label: {
                            Text("filter.clearAll")
                        }
                        .buttonStyle(.bordered)
                    } else if !searchText.isEmpty {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 32))
                            .foregroundStyle(.tertiary)
                        Text("sidebar.empty.search")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 32))
                            .foregroundStyle(.tertiary)
                        Text("sidebar.empty.noRepos")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button {
                            showingAddRepository = true
                        } label: {
                            Text("workspace.addRepository")
                        }
                        .buttonStyle(.bordered)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(filteredRepositories, id: \.id) { repository in
                            RepositoryRow(
                                repository: repository,
                                isSelected: selectedRepository?.id == repository.id,
                                repositoryManager: repositoryManager,
                                onSelect: {
                                    isCrossProjectSelected = false
                                    selectedRepository = repository
                                    // Auto-select primary worktree if no worktree is selected
                                    if selectedWorktree == nil {
                                        let worktrees = (repository.worktrees as? Set<Worktree>) ?? []
                                        selectedWorktree = worktrees.first(where: { $0.isPrimary })
                                    }
                                },
                                onRemove: {
                                    if selectedRepository?.id == repository.id {
                                        selectedRepository = nil
                                        selectedWorktree = nil
                                    }
                                }
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                    .padding(.bottom, 2)
                }
            }

            // Support Aizen (only when not licensed)
            if !isLicenseActive {
                Button {
                    SettingsWindowController.shared.show()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        NotificationCenter.default.post(name: .openSettingsPro, object: nil)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                        Text("sidebar.supportAizen")
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .background(Color.primary.opacity(0.08))
            }

            // Footer buttons
            HStack(spacing: 0) {
                Button {
                    showingAddRepository = true
                } label: {
                    Label("workspace.addRepository", systemImage: "plus")
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Spacer()

                Button {
                    showingSupportSheet = true
                } label: {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.vertical, 8)
                .help("sidebar.support")

                Button {
                    SettingsWindowController.shared.show()
                } label: {
                    Image(systemName: "gear")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .help("settings.title")
            }
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
