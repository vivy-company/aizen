import CoreData
import SwiftUI
import UniformTypeIdentifiers
import os.log

extension WorkspaceSidebarView {
    func startPeriodicRefresh() {
        refreshTask?.cancel()

        refreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(refreshInterval))

                guard !Task.isCancelled else { break }

                await refreshAllRepositories()
            }
        }
    }

    func stopPeriodicRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    func refreshAllRepositories() async {
        if let selected = selectedRepository {
            do {
                try await repositoryManager.refreshRepository(selected)
            } catch let error as Libgit2Error {
                if case .repositoryPathMissing(let path) = error {
                    handleMissingRepository(selected, path: path)
                } else {
                    logger.error("Failed to refresh selected repository \(selected.name ?? "unknown"): \(error.localizedDescription)")
                }
            } catch {
                logger.error("Failed to refresh selected repository \(selected.name ?? "unknown"): \(error.localizedDescription)")
            }
        }

        for repository in filteredRepositories where repository.id != selectedRepository?.id {
            guard !Task.isCancelled else { break }
            do {
                try await repositoryManager.refreshRepository(repository)
                try await Task.sleep(for: .milliseconds(100))
            } catch let error as Libgit2Error {
                if case .repositoryPathMissing(let path) = error {
                    handleMissingRepository(repository, path: path)
                } else {
                    logger.error("Failed to refresh repository \(repository.name ?? "unknown"): \(error.localizedDescription)")
                }
            } catch {
                logger.error("Failed to refresh repository \(repository.name ?? "unknown"): \(error.localizedDescription)")
            }
        }
    }

    @MainActor
    func handleMissingRepository(_ repository: Repository, path: String) {
        guard let id = repository.id else { return }
        guard missingRepository == nil else { return }
        missingRepository = WorkspaceRepositoryStore.MissingRepository(
            id: id,
            repository: repository,
            lastKnownPath: path
        )
    }
}
