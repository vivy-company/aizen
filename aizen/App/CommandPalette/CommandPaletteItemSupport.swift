import CoreData
import Foundation

enum CommandPaletteTabCatalog {
    static func visibleDefinitions(using defaults: UserDefaults) -> [(id: String, title: String, icon: String)] {
        let definitions: [(id: String, title: String, icon: String)] = [
            ("chat", "Chat", "message"),
            ("terminal", "Terminal", "terminal"),
            ("files", "Files", "folder"),
            ("browser", "Browser", "globe")
        ]
        return definitions.filter { isTabVisible($0.id, using: defaults) }
    }

    static func isTabVisible(_ tabId: String, using defaults: UserDefaults) -> Bool {
        switch tabId {
        case "chat":
            return defaults.object(forKey: "showChatTab") as? Bool ?? true
        case "terminal":
            return defaults.object(forKey: "showTerminalTab") as? Bool ?? true
        case "files":
            return defaults.object(forKey: "showFilesTab") as? Bool ?? true
        case "browser":
            return defaults.object(forKey: "showBrowserTab") as? Bool ?? true
        default:
            return false
        }
    }
}

enum CommandPaletteWorkspaceSupport {
    static func bestWorktree(for workspace: Workspace) -> Worktree? {
        let repositories = (workspace.repositories as? Set<Repository>) ?? []
        let worktrees = repositories
            .flatMap { repository -> [Worktree] in
                ((repository.worktrees as? Set<Worktree>) ?? []).filter { !$0.isDeleted }
            }
            .sorted { left, right in
                if left.isPrimary != right.isPrimary { return left.isPrimary }
                if left.lastAccessed != right.lastAccessed {
                    return (left.lastAccessed ?? .distantPast) > (right.lastAccessed ?? .distantPast)
                }
                return (left.branch ?? "") < (right.branch ?? "")
            }

        return worktrees.first
    }

    static func isCrossProjectWorktree(_ worktree: Worktree, marker: String) -> Bool {
        guard let repository = worktree.repository else {
            return false
        }
        return repository.isCrossProject || repository.note == marker
    }
}

enum CommandPaletteResultSlice {
    static func uniqueSlice(
        from source: [CommandPaletteItem],
        taking limit: Int,
        consumedIds: inout Set<String>
    ) -> [CommandPaletteItem] {
        var result: [CommandPaletteItem] = []
        result.reserveCapacity(limit)
        for item in source {
            guard !consumedIds.contains(item.id) else { continue }
            consumedIds.insert(item.id)
            result.append(item)
            if result.count >= limit {
                break
            }
        }
        return result
    }
}
