//
//  WorkspaceSidebarView.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import SwiftUI
import CoreData
import os.log

struct WorkspaceSidebarView: View {
    private let logger = Logger.workspace
    let workspaces: [Workspace]
    @Binding var selectedWorkspace: Workspace?
    @Binding var selectedRepository: Repository?
    @Binding var selectedWorktree: Worktree?
    @Binding var searchText: String
    @Binding var showingAddRepository: Bool

    @ObservedObject var repositoryManager: RepositoryManager
    @State private var showingWorkspaceSheet = false
    @State private var showingWorkspaceSwitcher = false
    @State private var workspaceToEdit: Workspace?
    @State private var refreshTimer: Timer?

    private let refreshInterval: TimeInterval = 30.0

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
        let validRepos = repos.filter { !$0.isDeleted }


        if searchText.isEmpty {
            return validRepos.sorted { ($0.name ?? "") < ($1.name ?? "") }
        } else {
            return validRepos
                .filter { ($0.name ?? "").localizedCaseInsensitiveContains(searchText) }
                .sorted { ($0.name ?? "") < ($1.name ?? "") }
        }
    }

    private func startPeriodicRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { _ in
            refreshAllRepositories()
        }
    }

    private func stopPeriodicRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func refreshAllRepositories() {
        Task {
            // Prioritize selected repository for immediate refresh
            if let selected = selectedRepository {
                do {
                    try await repositoryManager.refreshRepository(selected)
                } catch {
                    logger.error("Failed to refresh selected repository \(selected.name ?? "unknown"): \(error.localizedDescription)")
                }
            }

            // Background refresh other repos with stagger to reduce I/O contention
            for repository in filteredRepositories where repository.id != selectedRepository?.id {
                do {
                    try await repositoryManager.refreshRepository(repository)
                    try await Task.sleep(for: .milliseconds(100))
                } catch {
                    logger.error("Failed to refresh repository \(repository.name ?? "unknown"): \(error.localizedDescription)")
                }
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Workspace section
            VStack(alignment: .leading, spacing: 8) {
                Text("workspace.sidebar.title")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .padding(.horizontal, 12)

                // Current workspace button
                Button {
                    showingWorkspaceSwitcher = true
                } label: {
                    HStack(spacing: 12) {
                        if let workspace = selectedWorkspace {
                            Circle()
                                .fill(colorFromHex(workspace.colorHex ?? "#0000FF"))
                                .frame(width: 8, height: 8)

                            Text(workspace.name ?? String(localized: "workspace.untitled"))
                                .font(.body)
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.primary)
                                .lineLimit(1)

                            Spacer(minLength: 8)

                            let repoCount = (workspace.repositories as? Set<Repository>)?.count ?? 0
                            Text("\(repoCount)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.quaternary, in: Capsule())

                            Image(systemName: "chevron.up.chevron.down")
                                .foregroundStyle(.secondary)
                                .imageScale(.small)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
            }
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(LocalizedStringKey("workspace.search.placeholder"), text: $searchText)
                    .textFieldStyle(.plain)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Repository list
            List {
                ForEach(filteredRepositories, id: \.id) { repository in
                    RepositoryRow(
                        repository: repository,
                        isSelected: selectedRepository?.id == repository.id,
                        repositoryManager: repositoryManager,
                        onSelect: {
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
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .padding(.top, 12)

            Divider()

            // Add repository button
            HStack {
                Button {
                    showingAddRepository = true
                } label: {
                    Label("workspace.addRepository", systemImage: "plus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Spacer()
            }
            .background(.background)
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
        .onAppear {
            startPeriodicRefresh()
        }
        .onDisappear {
            stopPeriodicRefresh()
        }
    }
}

struct RepositoryRow: View {
    private let logger = Logger.workspace
    @ObservedObject var repository: Repository
    let isSelected: Bool
    @ObservedObject var repositoryManager: RepositoryManager
    let onSelect: () -> Void
    let onRemove: () -> Void

    @State private var showingRemoveConfirmation = false
    @State private var alsoDeleteFromFilesystem = false

    var body: some View {
        repositoryLabel
            .background(selectionBackground)
            .contextMenu {
                Button {
                    if let path = repository.path {
                        repositoryManager.openInTerminal(path)
                    }
                } label: {
                    Label("workspace.repository.openTerminal", systemImage: "terminal")
                }

                Button {
                    if let path = repository.path {
                        repositoryManager.openInFinder(path)
                    }
                } label: {
                    Label("workspace.repository.openFinder", systemImage: "folder")
                }

                Button {
                    if let path = repository.path {
                        repositoryManager.openInEditor(path)
                    }
                } label: {
                    Label("workspace.repository.openEditor", systemImage: "chevron.left.forwardslash.chevron.right")
                }

                Button {
                    if let path = repository.path {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(path, forType: .string)
                    }
                } label: {
                    Label("workspace.repository.copyPath", systemImage: "doc.on.doc")
                }

                Divider()

                Button(role: .destructive) {
                    showingRemoveConfirmation = true
                } label: {
                    Label("workspace.repository.remove", systemImage: "trash")
                }
            }
            .sheet(isPresented: $showingRemoveConfirmation) {
                RepositoryRemoveSheet(
                    repositoryName: repository.name ?? String(localized: "workspace.repository.unknown"),
                    alsoDeleteFromFilesystem: $alsoDeleteFromFilesystem,
                    onCancel: {
                        showingRemoveConfirmation = false
                        alsoDeleteFromFilesystem = false
                    },
                    onRemove: {
                        showingRemoveConfirmation = false
                        removeRepository()
                    }
                )
            }
    }

    private var repositoryLabel: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "folder.badge.gearshape")
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .imageScale(.medium)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(repository.name ?? String(localized: "workspace.repository.unknown"))
                    .font(.body)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                    .lineLimit(1)

                if let path = repository.path {
                    Text(path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 8)
        }
        .padding(.leading, 8)
        .padding(.trailing, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
    }

    @ViewBuilder
    private var selectionBackground: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor.opacity(0.15))
        }
    }

    private func removeRepository() {
        Task {
            do {
                // Delete from filesystem if checkbox was checked
                if alsoDeleteFromFilesystem, let path = repository.path {
                    let fileURL = URL(fileURLWithPath: path)
                    try FileManager.default.removeItem(at: fileURL)
                }

                // Clear selection before deleting
                onRemove()

                // Unlink from Core Data
                try repositoryManager.deleteRepository(repository)

                // Reset state
                alsoDeleteFromFilesystem = false
            } catch {
                logger.error("Failed to remove repository: \(error.localizedDescription)")
                alsoDeleteFromFilesystem = false
            }
        }
    }
}

struct WorkspaceRow: View {
    let workspace: Workspace
    let isSelected: Bool
    let isHovered: Bool
    let colorFromHex: (String) -> Color
    let onSelect: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(colorFromHex(workspace.colorHex ?? "#0000FF"))
                .frame(width: 8, height: 8)

            Text(workspace.name ?? String(localized: "workspace.untitled"))
                .font(.body)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                .lineLimit(1)

            Spacer(minLength: 8)

            let repoCount = (workspace.repositories as? Set<Repository>)?.count ?? 0
            Text("\(repoCount)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: Capsule())

            if isHovered || isSelected {
                Button {
                    onEdit()
                } label: {
                    Image(systemName: "pencil.circle.fill")
                        .foregroundStyle(.secondary)
                        .imageScale(.medium)
                }
                .buttonStyle(.plain)
                .help("workspace.edit")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
    }
}

struct RepositoryRemoveSheet: View {
    let repositoryName: String
    @Binding var alsoDeleteFromFilesystem: Bool
    let onCancel: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.minus")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text("workspace.repository.removeTitle")
                .font(.headline)

            Text("workspace.repository.removeMessage")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Toggle(isOn: $alsoDeleteFromFilesystem) {
                Label("workspace.repository.alsoDelete", systemImage: "trash")
                    .foregroundStyle(alsoDeleteFromFilesystem ? .red : .primary)
            }
            .toggleStyle(.checkbox)
            .padding(.top, 8)

            HStack(spacing: 12) {
                Button(String(localized: "worktree.create.cancel")) {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button(String(localized: "workspace.repository.removeButton"), role: .destructive) {
                    onRemove()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 8)
        }
        .padding(24)
        .frame(width: 340)
    }
}

#Preview {
    WorkspaceSidebarView(
        workspaces: [],
        selectedWorkspace: .constant(nil),
        selectedRepository: .constant(nil),
        selectedWorktree: .constant(nil),
        searchText: .constant(""),
        showingAddRepository: .constant(false),
        repositoryManager: RepositoryManager(viewContext: PersistenceController.preview.container.viewContext)
    )
}
