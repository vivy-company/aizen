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
    @AppStorage("zenModeEnabled") private var zenModeEnabled = false

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
        if searchText.isEmpty {
            return sortedWorktrees
        } else {
            return sortedWorktrees.filter { worktree in
                (worktree.branch ?? "").localizedCaseInsensitiveContains(searchText) ||
                (worktree.path ?? "").localizedCaseInsensitiveContains(searchText)
            }
        }
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
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

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
