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
    @Environment(\.controlActiveState) private var controlActiveState
    @StateObject private var licenseManager = LicenseStateStore.shared
    @State private var showingWorkspaceSheet = false
    @State private var showingWorkspaceSwitcher = false
    @State private var showingSupportSheet = false
    @State var showingRepositorySearch = false
    @State var showingRepositoryFilters = false
    @State private var workspaceToEdit: Workspace?
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

    private func colorFromHex(_ hex: String) -> Color {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)

        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0

        return Color(red: r, green: g, blue: b)
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

    private var workspaceRowFill: Color {
        Color.primary.opacity(0.05)
    }

    private var selectedForegroundColor: Color {
        controlActiveState == .key ? .accentColor : .accentColor.opacity(0.78)
    }

    private var selectionFillColor: Color {
        let base = NSColor.unemphasizedSelectedContentBackgroundColor
        let alpha: Double = controlActiveState == .key ? 0.26 : 0.18
        return Color(nsColor: base).opacity(alpha)
    }

    @ViewBuilder
    private var workspacePicker: some View {
        Button {
            showingWorkspaceSwitcher = true
        } label: {
            HStack(spacing: 12) {
                if let workspace = selectedWorkspace {
                    Circle()
                        .fill(colorFromHex(workspace.colorHex ?? "#0000FF"))
                        .frame(width: 10, height: 10)

                    Text(workspace.name ?? String(localized: "workspace.untitled"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .imageScale(.small)
                } else {
                    Text(String(localized: "workspace.untitled"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(workspaceRowFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    
    
    @ViewBuilder
    private var crossProjectRow: some View {
        Button {
            isCrossProjectSelected = true
            selectedRepository = nil
            selectedWorktree = nil
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "square.stack.3d.up.fill")
                    .foregroundStyle(isCrossProjectSelected ? selectedForegroundColor : .secondary)
                    .imageScale(.medium)
                    .frame(width: 18, height: 18)

                Text("Cross-Project")
                    .font(.body)
                    .foregroundStyle(isCrossProjectSelected ? selectedForegroundColor : Color.primary)
                    .lineLimit(1)

                Spacer(minLength: 8)
            }
            .padding(.leading, 8)
            .padding(.trailing, 12)
            .padding(.vertical, 8)
            .background(
                Group {
                    if isCrossProjectSelected {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(selectionFillColor)
                    }
                }
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(selectedWorkspace == nil)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    
    
    @ViewBuilder
    private var projectsSectionTitle: some View {
        if selectedWorkspace != nil {
            HStack(spacing: 8) {
                Text("Projects")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 2)
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
        .sheet(isPresented: $showingWorkspaceSheet) {
            WorkspaceCreateSheet(repositoryManager: repositoryManager)
        }
        .sheet(isPresented: $showingWorkspaceSwitcher) {
            WorkspaceSwitcherSheet(
                repositoryManager: repositoryManager,
                workspaces: workspaces,
                selectedWorkspace: $selectedWorkspace
            )
        }
        .sheet(item: $workspaceToEdit) { workspace in
            WorkspaceEditSheet(workspace: workspace, repositoryManager: repositoryManager)
        }
        .sheet(isPresented: $showingSupportSheet) {
            SupportSheet()
        }
        .sheet(item: $missingRepository) { missing in
            MissingRepositorySheet(
                missing: missing,
                repositoryManager: repositoryManager,
                selectedRepository: $selectedRepository,
                selectedWorktree: $selectedWorktree,
                onDismiss: { missingRepository = nil }
            )
        }
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
