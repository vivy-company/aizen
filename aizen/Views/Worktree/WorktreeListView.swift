//
//  WorktreeListView.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import SwiftUI

struct WorktreeListView: View {
    @ObservedObject var repository: Repository
    @Binding var selectedWorktree: Worktree?
    @ObservedObject var repositoryManager: RepositoryManager
    @ObservedObject var tabStateManager: WorktreeTabStateManager

    @State private var showingCreateWorktree = false
    @State private var searchText = ""
    @AppStorage("worktreeStatusFilters") private var storedStatusFilters: String = ""
    @AppStorage("zenModeEnabled") private var zenModeEnabled = false

    private var selectedStatusFilters: Set<ItemStatus> {
        ItemStatus.decode(storedStatusFilters)
    }

    private var selectedStatusFiltersBinding: Binding<Set<ItemStatus>> {
        Binding(
            get: { ItemStatus.decode(storedStatusFilters) },
            set: { storedStatusFilters = ItemStatus.encode($0) }
        )
    }

    private var sortedWorktrees: [Worktree] {
        let wts = (repository.worktrees as? Set<Worktree>) ?? []
        return wts.sorted { wt1, wt2 in
            if wt1.isPrimary != wt2.isPrimary {
                return wt1.isPrimary
            }
            return (wt1.branch ?? "") < (wt2.branch ?? "")
        }
    }

    private var worktrees: [Worktree] {
        var result = sortedWorktrees

        // Apply status filter
        if !selectedStatusFilters.isEmpty && selectedStatusFilters.count < ItemStatus.allCases.count {
            result = result.filter { worktree in
                let status = ItemStatus(rawValue: worktree.status ?? "active") ?? .active
                return selectedStatusFilters.contains(status)
            }
        }

        // Apply search filter
        if !searchText.isEmpty {
            result = result.filter { worktree in
                (worktree.branch ?? "").localizedCaseInsensitiveContains(searchText) ||
                (worktree.path ?? "").localizedCaseInsensitiveContains(searchText)
            }
        }

        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(String(localized: "worktree.list.search"), text: $searchText)
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

                StatusFilterDropdown(selectedStatuses: selectedStatusFiltersBinding)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if worktrees.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    if selectedStatusFilters.count < ItemStatus.allCases.count && !selectedStatusFilters.isEmpty {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.system(size: 32))
                            .foregroundStyle(.tertiary)
                        Text("worktree.list.empty.filtered")
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
                        Text("worktree.list.empty.search")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 32))
                            .foregroundStyle(.tertiary)
                        Text("worktree.list.empty.noWorktrees")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button {
                            showingCreateWorktree = true
                        } label: {
                            Text("worktree.list.add")
                        }
                        .buttonStyle(.bordered)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List {
                    ForEach(worktrees, id: \.id) { worktree in
                        WorktreeListItemView(
                            worktree: worktree,
                            isSelected: selectedWorktree?.id == worktree.id,
                            repositoryManager: repositoryManager,
                            allWorktrees: worktrees,
                            selectedWorktree: $selectedWorktree,
                            tabStateManager: tabStateManager
                        )
                        .onTapGesture {
                            selectedWorktree = worktree
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle(repository.name ?? "Unknown")
        .toolbar {
            if !zenModeEnabled {
                ToolbarItem(placement: .automatic) {
                    Spacer()
                }
                ToolbarItem(placement: .automatic) {
                    Button {
                        showingCreateWorktree = true
                    } label: {
                        Label(String(localized: "worktree.list.add"), systemImage: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showingCreateWorktree) {
            WorktreeCreateSheet(
                repository: repository,
                repositoryManager: repositoryManager
            )
        }
    }
}

#Preview {
    WorktreeListView(
        repository: Repository(),
        selectedWorktree: .constant(nil),
        repositoryManager: RepositoryManager(viewContext: PersistenceController.preview.container.viewContext),
        tabStateManager: WorktreeTabStateManager()
    )
}
