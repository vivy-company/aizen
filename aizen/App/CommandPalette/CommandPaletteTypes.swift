import Foundation

enum CommandPaletteScope: String, CaseIterable {
    case all
    case currentProject
    case workspace
    case tabs

    var title: String {
        switch self {
        case .all: return "All"
        case .currentProject: return "Current Project"
        case .workspace: return "Workspace"
        case .tabs: return "Tabs"
        }
    }
}

enum CommandPaletteNavigationAction {
    case worktree(workspaceId: UUID, repoId: UUID, worktreeId: UUID)
    case tab(workspaceId: UUID, repoId: UUID, worktreeId: UUID, tabId: String)
    case chatSession(workspaceId: UUID, repoId: UUID, worktreeId: UUID, sessionId: UUID)
    case terminalSession(workspaceId: UUID, repoId: UUID, worktreeId: UUID, sessionId: UUID)
    case browserSession(workspaceId: UUID, repoId: UUID, worktreeId: UUID, sessionId: UUID)
}

enum CommandPaletteItemKind {
    case worktree
    case workspace
    case tab
    case chatSession
    case terminalSession
    case browserSession
}

struct CommandPaletteItem: Identifiable {
    let id: String
    let kind: CommandPaletteItemKind
    let title: String
    let subtitle: String
    let icon: String
    let badgeText: String?
    let score: Double
    let lastAccessed: Date?
    let workspaceId: UUID?
    let repoId: UUID?
    let worktreeId: UUID?
    let tabId: String?
    let sessionId: UUID?
}

struct CommandPaletteSection: Identifiable {
    let id: String
    let title: String
    let items: [CommandPaletteItem]
}
