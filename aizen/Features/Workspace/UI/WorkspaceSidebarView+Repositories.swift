import SwiftUI

extension WorkspaceSidebarView {
    var repositoriesContent: some View {
        Group {
            crossProjectRow
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .padding(.bottom, 6)

            projectsSectionTitle

            if filteredRepositories.isEmpty {
                emptyRepositoriesView
            } else {
                repositoriesList
            }

            if !isLicenseActive {
                supportAizenButton
            }

            footerButtons
        }
    }

    var emptyRepositoriesView: some View {
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
    }

    var repositoriesList: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(filteredRepositories, id: \.id) { repository in
                    RepositoryRow(
                        repository: repository,
                        activeSessionCount: repository.id.flatMap { repositoryActiveSessionCounts[$0] } ?? 0,
                        isSelected: selectedRepository?.id == repository.id,
                        repositoryManager: repositoryManager,
                        onSelect: {
                            isCrossProjectSelected = false
                            selectedRepository = repository
                            if selectedWorktree == nil {
                                selectedWorktree = workspaceGraphQueryController.primaryOrFirstWorktree(in: repository)
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

    var supportAizenButton: some View {
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

    var footerButtons: some View {
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
}
