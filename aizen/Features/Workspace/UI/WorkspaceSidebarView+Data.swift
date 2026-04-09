import SwiftUI

extension WorkspaceSidebarView {
    var selectedStatusFilters: Set<ItemStatus> {
        ItemStatus.decode(storedStatusFilters)
    }

    var isLicenseActive: Bool {
        switch licenseManager.status {
        case .active, .offlineGrace:
            return true
        default:
            return false
        }
    }

    func isCrossProjectRepository(_ repository: Repository) -> Bool {
        repository.isCrossProject || repository.note == crossProjectRepositoryMarker
    }

    var repositoryActiveSessionCounts: [UUID: Int] {
        Dictionary(
            uniqueKeysWithValues: filteredRepositories.compactMap { repository in
                guard let repositoryId = repository.id else { return nil }
                return (repositoryId, RepositorySessionSnapshotBuilder.activeSessionCount(for: repository))
            }
        )
    }

    var filteredRepositories: [Repository] {
        guard let workspace = selectedWorkspace else { return [] }
        var validRepos = workspaceGraphQueryController.visibleRepositories(
            in: workspace,
            crossProjectMarker: crossProjectRepositoryMarker
        )

        if !selectedStatusFilters.isEmpty && selectedStatusFilters.count < ItemStatus.allCases.count {
            validRepos = validRepos.filter { repo in
                let status = ItemStatus(rawValue: repo.status ?? "active") ?? .active
                return selectedStatusFilters.contains(status)
            }
        }

        if searchText.isEmpty {
            return validRepos
        } else {
            return validRepos
                .filter { ($0.name ?? "").localizedCaseInsensitiveContains(searchText) }
        }
    }
}
