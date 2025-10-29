//
//  WorkspaceSidebarView.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import SwiftUI
import CoreData

struct WorkspaceSidebarView: View {
    let workspaces: [Workspace]
    @Binding var selectedWorkspace: Workspace?
    @Binding var selectedRepository: Repository?
    @Binding var selectedWorktree: Worktree?
    @Binding var searchText: String
    @Binding var showingAddRepository: Bool

    @ObservedObject var repositoryManager: RepositoryManager
    @State private var showingWorkspaceSheet = false
    @State private var showingEditWorkspace = false
    @State private var workspaceToEdit: Workspace?

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

        if searchText.isEmpty {
            return repos.sorted { ($0.name ?? "") < ($1.name ?? "") }
        } else {
            return repos
                .filter { ($0.name ?? "").localizedCaseInsensitiveContains(searchText) }
                .sorted { ($0.name ?? "") < ($1.name ?? "") }
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

                Menu {
                    ForEach(workspaces, id: \.id) { workspace in
                        Menu {
                            Button {
                                selectedWorkspace = workspace
                            } label: {
                                Label("workspace.switchTo", systemImage: "arrow.right.circle")
                            }

                            Button {
                                workspaceToEdit = workspace
                                showingEditWorkspace = true
                            } label: {
                                Label("workspace.edit", systemImage: "pencil")
                            }
                        } label: {
                            HStack {
                                Circle()
                                    .fill(colorFromHex(workspace.colorHex ?? "#0000FF"))
                                    .frame(width: 10, height: 10)

                                Text(workspace.name ?? String(localized: "workspace.untitled"))

                                Spacer()

                                let repoCount = (workspace.repositories as? Set<Repository>)?.count ?? 0
                                Text("\(repoCount)")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                        }
                    }

                    Divider()

                    Button {
                        showingWorkspaceSheet = true
                    } label: {
                        Label("workspace.new", systemImage: "plus.circle")
                    }
                } label: {
                    HStack {
                        if let workspace = selectedWorkspace {
                            Circle()
                                .fill(colorFromHex(workspace.colorHex ?? "#0000FF"))
                                .frame(width: 8, height: 8)

                            Text(workspace.name ?? String(localized: "workspace.untitled"))
                                .font(.title3)
                                .fontWeight(.semibold)

                            Spacer()

                            let repoCount = (workspace.repositories as? Set<Repository>)?.count ?? 0
                            Text("\(repoCount)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.quaternary, in: Capsule())
                        }

                        Image(systemName: "chevron.down.circle.fill")
                            .foregroundStyle(.secondary)
                            .imageScale(.medium)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                    .contentShape(RoundedRectangle(cornerRadius: 8))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(maxWidth: .infinity, alignment: .leading)
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
                        selectedWorktree: $selectedWorktree,
                        repositoryManager: repositoryManager,
                        onSelect: {
                            selectedRepository = repository
                        },
                        onWorktreeSelect: { worktree in
                            selectedRepository = repository
                            selectedWorktree = worktree
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
        .sheet(isPresented: $showingEditWorkspace) {
            if let workspace = workspaceToEdit {
                WorkspaceEditSheet(workspace: workspace, repositoryManager: repositoryManager)
            }
        }
    }
}

struct RepositoryRow: View {
    @ObservedObject var repository: Repository
    let isSelected: Bool
    @Binding var selectedWorktree: Worktree?
    @ObservedObject var repositoryManager: RepositoryManager
    let onSelect: () -> Void
    let onWorktreeSelect: (Worktree) -> Void

    @State private var isExpanded = true
    @State private var isRefreshing = false

    var worktrees: [Worktree] {
        let wts = (repository.worktrees as? Set<Worktree>) ?? []
        return wts.sorted { wt1, wt2 in
            if wt1.isPrimary != wt2.isPrimary {
                return wt1.isPrimary
            }
            return (wt1.branch ?? "") < (wt2.branch ?? "")
        }
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(worktrees, id: \.id) { worktree in
                WorktreeRowView(
                    worktree: worktree,
                    isSelected: selectedWorktree?.id == worktree.id
                )
                .onTapGesture {
                    onWorktreeSelect(worktree)
                }
            }
        } label: {
            repositoryLabel
        }
        .background(selectionBackground)
        .disclosureGroupStyle(SidebarDisclosureStyle())
        .contextMenu {
            Button {
                if let path = repository.path {
                    repositoryManager.openInFinder(path)
                }
            } label: {
                Label("workspace.repository.openFinder", systemImage: "folder")
            }

            Button(role: .destructive) {
                deleteRepository()
            } label: {
                Label("workspace.repository.remove", systemImage: "trash")
            }
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

            if isRefreshing {
                ProgressView()
                    .controlSize(.small)
                    .padding(.trailing, 4)
            } else {
                Button {
                    refreshRepository()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 4)
            }
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

    private func deleteRepository() {
        Task {
            do {
                try repositoryManager.deleteRepository(repository)
            } catch {
                print("Failed to delete repository: \(error)")
            }
        }
    }

    private func refreshRepository() {
        isRefreshing = true
        Task {
            do {
                try await repositoryManager.refreshRepository(repository)
            } catch {
                print("Failed to refresh repository: \(error)")
            }
            isRefreshing = false
        }
    }
}

struct WorktreeRowView: View {
    @ObservedObject var worktree: Worktree
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: worktree.isPrimary ? "arrow.triangle.branch" : "arrow.triangle.2.circlepath")
                .font(.caption)
                .foregroundStyle(isSelected ? .blue : .secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(worktree.branch ?? String(localized: "workspace.worktree.unknown"))
                    .font(.callout)
                    .lineLimit(1)

                Text(worktree.path ?? "")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 4)

            if worktree.isPrimary {
                Text("workspace.worktree.main")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.blue, in: Capsule())
            }
        }
        .padding(.leading, 48)
        .padding(.trailing, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

struct SidebarDisclosureStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Button {
                    withAnimation {
                        configuration.isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
                        .frame(width: 16, height: 16)
                        .animation(.easeInOut(duration: 0.2), value: configuration.isExpanded)
                }
                .buttonStyle(.plain)
                .padding(.leading, 8)

                configuration.label
            }

            if configuration.isExpanded {
                configuration.content
                    .padding(.top, 4)
            }
        }
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
