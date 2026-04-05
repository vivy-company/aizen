import SwiftUI

extension WorktreeListView {
    @ViewBuilder
    var searchBar: some View {
        SearchField(
            placeholder: "worktree.list.search",
            text: $searchText,
            spacing: 10,
            iconSize: 18,
            iconWeight: .medium,
            iconColor: .secondary,
            textFont: .system(size: 14, weight: .medium),
            clearButtonSize: 13,
            clearButtonWeight: .semibold,
            trailing: {
                StatusFilterDropdown(selectedStatuses: selectedStatusFiltersBinding)
            }
        )
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(searchFieldBackground)
        .overlay {
            Capsule()
                .strokeBorder(searchFieldStroke, lineWidth: 1)
                .allowsHitTesting(false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

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
                ScrollView {
                    LazyVStack(spacing: 4) {
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
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
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
