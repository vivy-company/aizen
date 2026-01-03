//
//  DeepLinkHandler.swift
//  aizen
//
//  Handles app deep links without spawning extra windows
//

import AppKit
import Foundation
import CoreData

@MainActor
final class DeepLinkHandler {
    static let shared = DeepLinkHandler()

    private init() {}

    func handle(_ url: URL) {
        guard url.scheme == "aizen" else { return }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let host = url.host ?? ""
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let queryItems = components?.queryItems ?? []

        let token = queryItems.first(where: { $0.name == "token" })?.value
        let activateFlag = queryItems.first(where: { $0.name == "activate" })?.value?.lowercased()
        let openPath = queryItems.first(where: { $0.name == "path" })?.value
        let autoActivate = host == "activate" || path == "activate" || activateFlag == "1" || activateFlag == "true"

        if token != nil || autoActivate {
            LicenseManager.shared.setPendingDeepLink(token: token, autoActivate: autoActivate)
        }

        NSApp.activate(ignoringOtherApps: true)

        collapseDuplicateMainWindows { [weak self] in
            self?.dispatchDeepLink(host: host, path: path, token: token, autoActivate: autoActivate, openPath: openPath)
        }
    }

    private func dispatchDeepLink(host: String, path: String, token: String?, autoActivate: Bool, openPath: String?) {
        if token != nil || autoActivate {
            NotificationCenter.default.post(name: .openLicenseDeepLink, object: nil)
            return
        }

        if host == "open" || path == "open" {
            if let openPath = openPath {
                handleOpenPath(openPath)
            }
            return
        }

        let shouldOpenSettings = host == "settings" || path == "settings"
        guard shouldOpenSettings else { return }

        SettingsWindowManager.shared.show()
        NotificationCenter.default.post(name: .openSettingsPro, object: nil)
    }

    private func handleOpenPath(_ path: String) {
        let normalized = normalizedPath(path)

        Task { @MainActor in
            let context = PersistenceController.shared.container.viewContext
            guard let target = await resolveWorktreeTarget(for: normalized, in: context) else { return }

            NotificationCenter.default.post(
                name: .navigateToWorktree,
                object: nil,
                userInfo: [
                    "workspaceId": target.workspaceId,
                    "repoId": target.repoId,
                    "worktreeId": target.worktreeId
                ]
            )
        }
    }

    private func normalizedPath(_ path: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") {
            return URL(fileURLWithPath: expanded).standardizedFileURL.path
        }
        let cwd = FileManager.default.currentDirectoryPath
        let combined = URL(fileURLWithPath: cwd).appendingPathComponent(expanded)
        return combined.standardizedFileURL.path
    }

    private func resolveWorktreeTarget(
        for path: String,
        in context: NSManagedObjectContext
    ) async -> (workspaceId: UUID, repoId: UUID, worktreeId: UUID)? {
        let discovered = await GitUtils.discoverRepository(from: path)
        var repositoryPath = discovered ?? path
        if repositoryPath.hasSuffix("/.git") {
            repositoryPath = URL(fileURLWithPath: repositoryPath).deletingLastPathComponent().path
        }
        let mainRepoPath = await GitUtils.getMainRepositoryPath(at: repositoryPath)

        let repoRequest: NSFetchRequest<Repository> = Repository.fetchRequest()
        repoRequest.predicate = NSPredicate(format: "path == %@", mainRepoPath)
        repoRequest.fetchLimit = 1
        guard let repository = try? context.fetch(repoRequest).first else { return nil }
        guard let repoId = repository.id,
              let workspaceId = repository.workspace?.id else { return nil }

        let worktrees = (repository.worktrees as? Set<Worktree>) ?? []

        let matchingWorktree = worktrees
            .filter { worktree in
                guard let wtPath = worktree.path else { return false }
                return path == wtPath || path.hasPrefix(wtPath + "/")
            }
            .sorted { ($0.path ?? "").count > ($1.path ?? "").count }
            .first

        let targetWorktree = matchingWorktree ?? worktrees.first(where: { $0.isPrimary }) ?? worktrees.first
        guard let worktreeId = targetWorktree?.id else { return nil }

        return (workspaceId: workspaceId, repoId: repoId, worktreeId: worktreeId)
    }

    private func collapseDuplicateMainWindows(completion: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let windows = NSApp.windows.filter { window in
                window.identifier != NSUserInterfaceItemIdentifier("GitPanelWindow") &&
                window.isVisible &&
                !window.isMiniaturized
            }

            if windows.count > 1 {
                let keepWindow = NSApp.mainWindow ?? windows.first
                for window in windows {
                    if window != keepWindow {
                        window.close()
                    }
                }
                keepWindow?.makeKeyAndOrderFront(nil)
            }

            completion()
        }
    }
}
