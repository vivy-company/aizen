//
//  WorktreeSearchViewModel.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 20.12.25.
//

import Foundation
import Combine
import CoreData

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

@MainActor
final class WorktreeSearchViewModel: ObservableObject {
    @Published var searchQuery = ""
    @Published var selectedIndex = 0
    @Published var scope: CommandPaletteScope = .all
    @Published private(set) var sections: [CommandPaletteSection] = []

    private var allWorktrees: [Worktree] = []
    private var allWorkspaces: [Workspace] = []
    private var currentWorktreeId: String?
    private var currentRepositoryId: String?
    private var currentWorkspaceId: String?
    private var cancellables = Set<AnyCancellable>()
    private var ignoreExplicitScope = false
    private var flattenedItems: [CommandPaletteItem] = []
    private let crossProjectRepositoryMarker = "__aizen.cross_project.workspace_repo__"
    private let defaults = UserDefaults.standard

    init(currentRepositoryId: String? = nil, currentWorkspaceId: String? = nil) {
        self.currentRepositoryId = currentRepositoryId
        self.currentWorkspaceId = currentWorkspaceId
        setupSearchDebounce()
    }

    func updateSnapshot(_ worktrees: [Worktree], currentWorktreeId: String?) {
        allWorktrees = worktrees
        self.currentWorktreeId = currentWorktreeId
        performSearch()
    }

    func updateCurrentRepository(_ repositoryId: String?) {
        if currentRepositoryId == repositoryId {
            return
        }
        currentRepositoryId = repositoryId
        performSearch()
    }

    func updateCurrentWorkspace(_ workspaceId: String?) {
        if currentWorkspaceId == workspaceId {
            return
        }
        currentWorkspaceId = workspaceId
        performSearch()
    }

    func updateWorkspaceSnapshot(_ workspaces: [Workspace]) {
        allWorkspaces = workspaces
        performSearch()
    }

    private func setupSearchDebounce() {
        $searchQuery
            .debounce(for: .milliseconds(120), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.ignoreExplicitScope = false
                self?.performSearch()
            }
            .store(in: &cancellables)
    }

    func performSearch() {
        let query = searchQuery
        let worktreeSnapshot = allWorktrees
        let workspaceSnapshot = allWorkspaces
        let currentWorktreeId = currentWorktreeId
        let currentRepositoryId = currentRepositoryId
        let currentWorkspaceId = currentWorkspaceId
        let parsed = parseQuery(query, fallbackScope: scope)
        let effectiveScope = (parsed.isExplicit && !ignoreExplicitScope) ? parsed.scope : scope

        if !ignoreExplicitScope,
           parsed.isExplicit,
           parsed.scope != scope {
            scope = parsed.scope
        }

        let resolved = buildSections(
            scope: effectiveScope,
            query: parsed.query,
            worktrees: worktreeSnapshot,
            workspaces: workspaceSnapshot,
            currentWorktreeId: currentWorktreeId,
            currentRepositoryId: currentRepositoryId,
            currentWorkspaceId: currentWorkspaceId
        )

        guard query == searchQuery else { return }

        sections = resolved
        flattenedItems = resolved.flatMap(\.items)
        selectedIndex = 0
    }

    func setScope(_ newScope: CommandPaletteScope, ignoreQueryPrefix: Bool = true) {
        if scope != newScope {
            scope = newScope
        }
        if ignoreQueryPrefix {
            ignoreExplicitScope = true
        }
        performSearch()
    }

    func cycleScopeForward() {
        ignoreExplicitScope = true
        switch scope {
        case .all:
            scope = .currentProject
        case .currentProject:
            scope = .workspace
        case .workspace:
            scope = .tabs
        case .tabs:
            scope = .all
        }
        performSearch()
    }

    func moveSelectionUp() {
        if selectedIndex > 0 {
            selectedIndex -= 1
        }
    }

    func moveSelectionDown() {
        if selectedIndex < flattenedItems.count - 1 {
            selectedIndex += 1
        }
    }

    func selectedItem() -> CommandPaletteItem? {
        guard selectedIndex >= 0, selectedIndex < flattenedItems.count else { return nil }
        return flattenedItems[selectedIndex]
    }

    func selectedNavigationAction() -> CommandPaletteNavigationAction? {
        guard let item = selectedItem(),
              let workspaceId = item.workspaceId,
              let repoId = item.repoId,
              let worktreeId = item.worktreeId else {
            return nil
        }

        switch item.kind {
        case .workspace, .worktree:
            return .worktree(workspaceId: workspaceId, repoId: repoId, worktreeId: worktreeId)
        case .tab:
            guard let tabId = item.tabId else { return nil }
            return .tab(workspaceId: workspaceId, repoId: repoId, worktreeId: worktreeId, tabId: tabId)
        case .chatSession:
            guard let sessionId = item.sessionId else { return nil }
            return .chatSession(
                workspaceId: workspaceId,
                repoId: repoId,
                worktreeId: worktreeId,
                sessionId: sessionId
            )
        case .terminalSession:
            guard let sessionId = item.sessionId else { return nil }
            return .terminalSession(
                workspaceId: workspaceId,
                repoId: repoId,
                worktreeId: worktreeId,
                sessionId: sessionId
            )
        case .browserSession:
            guard let sessionId = item.sessionId else { return nil }
            return .browserSession(
                workspaceId: workspaceId,
                repoId: repoId,
                worktreeId: worktreeId,
                sessionId: sessionId
            )
        }
    }

    private func buildSections(
        scope: CommandPaletteScope,
        query: String,
        worktrees: [Worktree],
        workspaces: [Workspace],
        currentWorktreeId: String?,
        currentRepositoryId: String?,
        currentWorkspaceId: String?
    ) -> [CommandPaletteSection] {
        switch scope {
        case .all:
            return buildAllSections(
                query: query,
                worktrees: worktrees,
                workspaces: workspaces,
                currentWorktreeId: currentWorktreeId,
                currentRepositoryId: currentRepositoryId,
                currentWorkspaceId: currentWorkspaceId
            )
        case .currentProject:
            return buildCurrentProjectSections(
                query: query,
                worktrees: worktrees,
                currentWorktreeId: currentWorktreeId,
                currentRepositoryId: currentRepositoryId,
                currentWorkspaceId: currentWorkspaceId
            )
        case .workspace:
            return buildWorkspaceSections(
                query: query,
                workspaces: workspaces,
                worktrees: worktrees,
                currentWorktreeId: currentWorktreeId,
                currentRepositoryId: currentRepositoryId,
                currentWorkspaceId: currentWorkspaceId
            )
        case .tabs:
            return buildTabsSections(
                query: query,
                worktrees: worktrees,
                currentWorktreeId: currentWorktreeId,
                currentRepositoryId: currentRepositoryId,
                currentWorkspaceId: currentWorkspaceId,
                includeAllWorktrees: true
            )
        }
    }

    private func buildAllSections(
        query: String,
        worktrees: [Worktree],
        workspaces: [Workspace],
        currentWorktreeId: String?,
        currentRepositoryId: String?,
        currentWorkspaceId: String?
    ) -> [CommandPaletteSection] {
        let worktreeItems = buildWorktreeItems(
            query: query,
            worktrees: worktrees,
            currentWorktreeId: currentWorktreeId,
            currentRepositoryId: currentRepositoryId,
            currentWorkspaceId: currentWorkspaceId,
            includeCurrentWorktree: false
        )

        var sections: [CommandPaletteSection] = []

        sections.append(
            contentsOf: buildTabsSections(
                query: query,
                worktrees: worktrees,
                currentWorktreeId: currentWorktreeId,
                currentRepositoryId: currentRepositoryId,
                currentWorkspaceId: currentWorkspaceId,
                includeAllWorktrees: !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
        )

        if !worktreeItems.isEmpty {
            var consumedIds = Set<String>()

            let recentCandidates: [CommandPaletteItem]
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                recentCandidates = worktreeItems
                    .sorted { ($0.lastAccessed ?? .distantPast) > ($1.lastAccessed ?? .distantPast) }
            } else {
                recentCandidates = worktreeItems
                    .filter { isRecent($0.lastAccessed) }
                    .sorted { $0.score > $1.score }
            }

            let recent = uniqueSlice(from: recentCandidates, taking: 8, consumedIds: &consumedIds)
            if !recent.isEmpty {
                sections.append(CommandPaletteSection(id: "recent", title: "Recent", items: recent))
            }

            let currentProject = uniqueSlice(
                from: worktreeItems.filter { item in
                    guard let repoId = item.repoId?.uuidString, let currentRepositoryId else {
                        return false
                    }
                    return repoId == currentRepositoryId
                },
                taking: 12,
                consumedIds: &consumedIds
            )
            if !currentProject.isEmpty {
                sections.append(CommandPaletteSection(id: "current-project", title: "Current Project", items: currentProject))
            }

            let others = uniqueSlice(
                from: worktreeItems,
                taking: 24,
                consumedIds: &consumedIds
            )
            if !others.isEmpty {
                sections.append(CommandPaletteSection(id: "other-workspaces", title: "Other Workspaces", items: others))
            }
        }

        let workspaceItems = buildWorkspaceItems(query: query, workspaces: workspaces)
        if !workspaceItems.isEmpty {
            sections.append(
                CommandPaletteSection(
                    id: "workspaces",
                    title: "Workspaces",
                    items: Array(workspaceItems.prefix(8))
                )
            )
        }

        return sections
    }

    private func buildCurrentProjectSections(
        query: String,
        worktrees: [Worktree],
        currentWorktreeId: String?,
        currentRepositoryId: String?,
        currentWorkspaceId: String?
    ) -> [CommandPaletteSection] {
        let worktreeItems = buildWorktreeItems(
            query: query,
            worktrees: worktrees,
            currentWorktreeId: currentWorktreeId,
            currentRepositoryId: currentRepositoryId,
            currentWorkspaceId: currentWorkspaceId,
            includeCurrentWorktree: true
        ).filter { item in
            guard let repoId = item.repoId?.uuidString, let currentRepositoryId else {
                return false
            }
            return repoId == currentRepositoryId
        }

        guard !worktreeItems.isEmpty else { return [] }
        return [
            CommandPaletteSection(
                id: "current-project-environments",
                title: "Environments",
                items: Array(worktreeItems.prefix(24))
            )
        ]
    }

    private func buildWorkspaceSections(
        query: String,
        workspaces: [Workspace],
        worktrees: [Worktree],
        currentWorktreeId: String?,
        currentRepositoryId: String?,
        currentWorkspaceId: String?
    ) -> [CommandPaletteSection] {
        if let currentWorkspaceId {
            let workspaceEnvironmentItems = buildWorktreeItems(
                query: query,
                worktrees: worktrees,
                currentWorktreeId: currentWorktreeId,
                currentRepositoryId: currentRepositoryId,
                currentWorkspaceId: currentWorkspaceId,
                includeCurrentWorktree: true
            ).filter { item in
                item.workspaceId?.uuidString == currentWorkspaceId
            }

            if !workspaceEnvironmentItems.isEmpty {
                return [
                    CommandPaletteSection(
                        id: "workspace-environments",
                        title: "Environments",
                        items: Array(workspaceEnvironmentItems.prefix(24))
                    )
                ]
            }
        }

        let workspaceItems = buildWorkspaceItems(query: query, workspaces: workspaces)
        guard !workspaceItems.isEmpty else { return [] }
        return [
            CommandPaletteSection(
                id: "workspace",
                title: "Workspace",
                items: workspaceItems
            )
        ]
    }

    private func buildTabsSections(
        query: String,
        worktrees: [Worktree],
        currentWorktreeId: String?,
        currentRepositoryId: String?,
        currentWorkspaceId: String?,
        includeAllWorktrees: Bool
    ) -> [CommandPaletteSection] {
        let tabItems = buildTabAndSessionItems(
            query: query,
            worktrees: worktrees,
            currentWorktreeId: currentWorktreeId,
            currentRepositoryId: currentRepositoryId,
            currentWorkspaceId: currentWorkspaceId,
            includeAllWorktrees: includeAllWorktrees
        )
        guard !tabItems.isEmpty else { return [] }

        let grouped = Dictionary(grouping: tabItems, by: \.kind)
        var sections: [CommandPaletteSection] = []

        let directTabs = grouped[.tab] ?? []
        if !directTabs.isEmpty {
            sections.append(CommandPaletteSection(id: "tabs", title: "Tabs", items: directTabs))
        }

        let sessionKinds: [CommandPaletteItemKind] = [.chatSession, .terminalSession, .browserSession]
        let sessions = sessionKinds.flatMap { grouped[$0] ?? [] }
            .sorted { $0.score > $1.score }
        if !sessions.isEmpty {
            sections.append(CommandPaletteSection(id: "sessions", title: "Sessions", items: sessions))
        }

        return sections
    }

    private func buildWorktreeItems(
        query: String,
        worktrees: [Worktree],
        currentWorktreeId: String?,
        currentRepositoryId: String?,
        currentWorkspaceId: String?,
        includeCurrentWorktree: Bool
    ) -> [CommandPaletteItem] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowerQuery = trimmedQuery.lowercased()

        let base = worktrees.filter { worktree in
            guard !worktree.isDeleted else { return false }
            guard worktree.repository?.workspace != nil else { return false }
            if !includeCurrentWorktree,
               let currentId = currentWorktreeId,
               let worktreeId = worktree.id?.uuidString,
               currentId == worktreeId {
                return false
            }
            return true
        }

        let ranked = base.compactMap { worktree -> CommandPaletteItem? in
            guard let workspaceId = worktree.repository?.workspace?.id,
                  let repoId = worktree.repository?.id,
                  let worktreeId = worktree.id else {
                return nil
            }

            let workspaceName = worktree.repository?.workspace?.name ?? "Workspace"
            let repoName = worktree.repository?.name ?? "Repository"
            let branchName = worktree.branch ?? "Unknown"
            let subtitle = "\(workspaceName) › \(repoName)"
            let fields = [branchName, repoName, workspaceName, worktree.note ?? ""]

            let queryScore: Double
            if lowerQuery.isEmpty {
                queryScore = 1
            } else {
                queryScore = matchScore(query: lowerQuery, fields: fields)
            }
            guard queryScore > 0 else { return nil }

            var score = queryScore
            score += recencyBoost(for: worktree.lastAccessed)

            if repoId.uuidString == currentRepositoryId {
                score += 120
            }
            if workspaceId.uuidString == currentWorkspaceId {
                score += 40
            }
            if worktree.isPrimary {
                score += 12
            }
            if isCrossProjectWorktree(worktree) {
                score -= 18
            }

            return CommandPaletteItem(
                id: "worktree-\(worktreeId.uuidString)",
                kind: .worktree,
                title: isCrossProjectWorktree(worktree) ? workspaceName : branchName,
                subtitle: isCrossProjectWorktree(worktree) ? "All Projects" : subtitle,
                icon: isCrossProjectWorktree(worktree) ? "square.stack.3d.up.fill" : (worktree.isPrimary ? "arrow.triangle.branch" : "arrow.triangle.2.circlepath"),
                badgeText: isCrossProjectWorktree(worktree) ? "cross-project" : (worktree.isPrimary ? "main" : nil),
                score: score,
                lastAccessed: worktree.lastAccessed,
                workspaceId: workspaceId,
                repoId: repoId,
                worktreeId: worktreeId,
                tabId: nil,
                sessionId: nil
            )
        }

        return ranked.sorted { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }
            let lhsLast = lhs.lastAccessed ?? .distantPast
            let rhsLast = rhs.lastAccessed ?? .distantPast
            if lhsLast != rhsLast {
                return lhsLast > rhsLast
            }
            return lhs.title.lowercased() < rhs.title.lowercased()
        }
    }

    private func buildWorkspaceItems(query: String, workspaces: [Workspace]) -> [CommandPaletteItem] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowerQuery = trimmedQuery.lowercased()

        let base = workspaces.filter { workspace in
            guard workspace.id != nil else { return false }
            return true
        }

        let ranked = base.compactMap { workspace -> CommandPaletteItem? in
            guard let workspaceId = workspace.id else { return nil }
            let workspaceName = workspace.name ?? "Workspace"
            let fallbackWorktree = bestWorkspaceWorktree(workspace)

            guard let worktreeId = fallbackWorktree?.id,
                  let repoId = fallbackWorktree?.repository?.id else {
                return nil
            }

            let fields = [workspaceName]
            let queryScore: Double
            if lowerQuery.isEmpty {
                queryScore = 1
            } else {
                queryScore = matchScore(query: lowerQuery, fields: fields)
            }
            guard queryScore > 0 else { return nil }

            var score = queryScore
            score += workspaceId.uuidString == currentWorkspaceId ? 120 : 0
            score += recencyBoost(for: fallbackWorktree?.lastAccessed)

            return CommandPaletteItem(
                id: "workspace-\(workspaceId.uuidString)",
                kind: .workspace,
                title: workspaceName,
                subtitle: "Open most recent environment",
                icon: "folder.badge.gearshape",
                badgeText: nil,
                score: score,
                lastAccessed: fallbackWorktree?.lastAccessed,
                workspaceId: workspaceId,
                repoId: repoId,
                worktreeId: worktreeId,
                tabId: nil,
                sessionId: nil
            )
        }

        return ranked.sorted { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }
            return lhs.title.lowercased() < rhs.title.lowercased()
        }
    }

    private func buildTabAndSessionItems(
        query: String,
        worktrees: [Worktree],
        currentWorktreeId: String?,
        currentRepositoryId: String?,
        currentWorkspaceId: String?,
        includeAllWorktrees: Bool
    ) -> [CommandPaletteItem] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowerQuery = trimmedQuery.lowercased()
        let isEmptyQuery = lowerQuery.isEmpty

        let eligible: [Worktree]
        if includeAllWorktrees {
            eligible = worktrees.filter { !$0.isDeleted && $0.repository?.workspace != nil }
        } else {
            eligible = worktrees.filter { worktree in
                guard !worktree.isDeleted else { return false }
                guard worktree.repository?.workspace != nil else { return false }
                guard let repoId = worktree.repository?.id?.uuidString else { return false }
                return repoId == currentRepositoryId
            }
        }

        guard !eligible.isEmpty else { return [] }

        let currentWorktree = eligible.first(where: { $0.id?.uuidString == currentWorktreeId })
        let prioritized: [Worktree]
        if isEmptyQuery, let currentWorktree {
            prioritized = [currentWorktree]
        } else {
            prioritized = eligible
        }

        let tabDefs = visibleTabDefinitions()
        let includeChatSessions = isTabVisible("chat")
        let includeTerminalSessions = isTabVisible("terminal")
        let includeBrowserSessions = isTabVisible("browser")

        if tabDefs.isEmpty && !includeChatSessions && !includeTerminalSessions && !includeBrowserSessions {
            return []
        }

        var items: [CommandPaletteItem] = []
        items.reserveCapacity(96)

        for worktree in prioritized {
            guard let workspaceId = worktree.repository?.workspace?.id,
                  let repoId = worktree.repository?.id,
                  let worktreeId = worktree.id else {
                continue
            }

            let workspaceName = worktree.repository?.workspace?.name ?? "Workspace"
            let repoName = worktree.repository?.name ?? "Repository"
            let branchName = worktree.branch ?? "Unknown"
            let context = "\(workspaceName) › \(repoName) › \(branchName)"

            for tab in tabDefs {
                let fields = [tab.title, branchName, repoName, workspaceName]
                let queryScore: Double
                if isEmptyQuery {
                    queryScore = worktree.id?.uuidString == currentWorktreeId ? 260 : 0
                } else {
                    queryScore = matchScore(query: lowerQuery, fields: fields)
                }
                guard queryScore > 0 else { continue }

                var score = queryScore
                score += recencyBoost(for: worktree.lastAccessed)
                if repoId.uuidString == currentRepositoryId {
                    score += 44
                }
                if workspaceId.uuidString == currentWorkspaceId {
                    score += 18
                }
                if worktree.id?.uuidString == currentWorktreeId {
                    score += 70
                }

                items.append(
                    CommandPaletteItem(
                        id: "tab-\(worktreeId.uuidString)-\(tab.id)",
                        kind: .tab,
                        title: tab.title,
                        subtitle: context,
                        icon: tab.icon,
                        badgeText: nil,
                        score: score,
                        lastAccessed: worktree.lastAccessed,
                        workspaceId: workspaceId,
                        repoId: repoId,
                        worktreeId: worktreeId,
                        tabId: tab.id,
                        sessionId: nil
                    )
                )
            }

            if includeChatSessions {
                let chatSessions = ((worktree.chatSessions as? Set<ChatSession>) ?? [])
                    .filter { !$0.isDeleted && !$0.archived }
                    .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
                for session in chatSessions {
                    guard let sessionId = session.id else { continue }
                    let title = session.title ?? session.agentName?.capitalized ?? "Chat Session"
                    let fields = [title, branchName, repoName, workspaceName, "chat", session.agentName ?? ""]
                    let queryScore = isEmptyQuery
                        ? (worktree.id?.uuidString == currentWorktreeId ? 220 : 0)
                        : matchScore(query: lowerQuery, fields: fields)
                    guard queryScore > 0 else { continue }

                    var score = queryScore
                    score += recencyBoost(for: worktree.lastAccessed)
                    if worktree.id?.uuidString == currentWorktreeId { score += 58 }

                    items.append(
                        CommandPaletteItem(
                            id: "chat-session-\(sessionId.uuidString)",
                            kind: .chatSession,
                            title: title,
                            subtitle: context,
                            icon: "message",
                            badgeText: nil,
                            score: score,
                            lastAccessed: worktree.lastAccessed,
                            workspaceId: workspaceId,
                            repoId: repoId,
                            worktreeId: worktreeId,
                            tabId: "chat",
                            sessionId: sessionId
                        )
                    )
                }
            }

            if includeTerminalSessions {
                let terminalSessions = ((worktree.terminalSessions as? Set<TerminalSession>) ?? [])
                    .filter { !$0.isDeleted }
                    .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
                for session in terminalSessions {
                    guard let sessionId = session.id else { continue }
                    let title = session.title ?? "Terminal Session"
                    let fields = [title, branchName, repoName, workspaceName, "terminal", "shell"]
                    let queryScore = isEmptyQuery
                        ? (worktree.id?.uuidString == currentWorktreeId ? 200 : 0)
                        : matchScore(query: lowerQuery, fields: fields)
                    guard queryScore > 0 else { continue }

                    var score = queryScore
                    score += recencyBoost(for: worktree.lastAccessed)
                    if worktree.id?.uuidString == currentWorktreeId { score += 48 }

                    items.append(
                        CommandPaletteItem(
                            id: "terminal-session-\(sessionId.uuidString)",
                            kind: .terminalSession,
                            title: title,
                            subtitle: context,
                            icon: "terminal",
                            badgeText: nil,
                            score: score,
                            lastAccessed: worktree.lastAccessed,
                            workspaceId: workspaceId,
                            repoId: repoId,
                            worktreeId: worktreeId,
                            tabId: "terminal",
                            sessionId: sessionId
                        )
                    )
                }
            }

            if includeBrowserSessions {
                let browserSessions = ((worktree.browserSessions as? Set<BrowserSession>) ?? [])
                    .filter { !$0.isDeleted }
                    .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
                for session in browserSessions {
                    guard let sessionId = session.id else { continue }
                    let title = session.title ?? session.url ?? "Browser Session"
                    let fields = [title, branchName, repoName, workspaceName, "browser", session.url ?? ""]
                    let queryScore = isEmptyQuery
                        ? (worktree.id?.uuidString == currentWorktreeId ? 180 : 0)
                        : matchScore(query: lowerQuery, fields: fields)
                    guard queryScore > 0 else { continue }

                    var score = queryScore
                    score += recencyBoost(for: worktree.lastAccessed)
                    if worktree.id?.uuidString == currentWorktreeId { score += 40 }

                    items.append(
                        CommandPaletteItem(
                            id: "browser-session-\(sessionId.uuidString)",
                            kind: .browserSession,
                            title: title,
                            subtitle: context,
                            icon: "globe",
                            badgeText: nil,
                            score: score,
                            lastAccessed: worktree.lastAccessed,
                            workspaceId: workspaceId,
                            repoId: repoId,
                            worktreeId: worktreeId,
                            tabId: "browser",
                            sessionId: sessionId
                        )
                    )
                }
            }
        }

        return items.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            let lhsLast = lhs.lastAccessed ?? .distantPast
            let rhsLast = rhs.lastAccessed ?? .distantPast
            if lhsLast != rhsLast {
                return lhsLast > rhsLast
            }
            return lhs.title.lowercased() < rhs.title.lowercased()
        }
        .prefix(isEmptyQuery ? 40 : 80)
        .map { $0 }
    }

    private func visibleTabDefinitions() -> [(id: String, title: String, icon: String)] {
        let definitions: [(id: String, title: String, icon: String)] = [
            ("chat", "Chat", "message"),
            ("terminal", "Terminal", "terminal"),
            ("files", "Files", "folder"),
            ("browser", "Browser", "globe")
        ]
        return definitions.filter { isTabVisible($0.id) }
    }

    private func isTabVisible(_ tabId: String) -> Bool {
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

    private func parseQuery(
        _ query: String,
        fallbackScope: CommandPaletteScope
    ) -> (scope: CommandPaletteScope, query: String, isExplicit: Bool) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (fallbackScope, "", false) }

        let lower = trimmed.lowercased()
        let commandPairs: [(String, CommandPaletteScope)] = [
            ("all:", .all),
            ("all ", .all),
            ("a:", .all),
            ("a ", .all),
            ("workspace:", .workspace),
            ("workspace ", .workspace),
            ("w:", .workspace),
            ("w ", .workspace),
            ("ws:", .workspace),
            ("ws ", .workspace),
            ("tabs:", .tabs),
            ("tabs ", .tabs),
            ("tab:", .tabs),
            ("tab ", .tabs),
            ("t:", .tabs),
            ("t ", .tabs),
            ("project:", .currentProject),
            ("project ", .currentProject),
            ("repo:", .currentProject),
            ("repo ", .currentProject),
            ("current:", .currentProject),
            ("current ", .currentProject),
            ("local:", .currentProject),
            ("local ", .currentProject),
            ("cp:", .currentProject),
            ("cp ", .currentProject),
            ("env:", .all),
            ("env ", .all),
            ("environment:", .all),
            ("environment ", .all),
            ("e:", .all),
            ("e ", .all)
        ]

        for (prefix, parsedScope) in commandPairs where lower.hasPrefix(prefix) {
            let stripped = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            return (parsedScope, stripped, true)
        }

        return (fallbackScope, trimmed, false)
    }

    private func bestWorkspaceWorktree(_ workspace: Workspace) -> Worktree? {
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

    private func isCrossProjectWorktree(_ worktree: Worktree) -> Bool {
        guard let repository = worktree.repository else {
            return false
        }
        return repository.isCrossProject || repository.note == crossProjectRepositoryMarker
    }

    private func uniqueSlice(
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

    private func isRecent(_ date: Date?) -> Bool {
        guard let date else { return false }
        return Date().timeIntervalSince(date) <= 14 * 24 * 60 * 60
    }

    private func recencyBoost(for date: Date?) -> Double {
        guard let date else { return 0 }
        let age = Date().timeIntervalSince(date)
        if age <= 60 * 10 {
            return 80
        }
        if age <= 60 * 60 {
            return 60
        }
        if age <= 60 * 60 * 24 {
            return 36
        }
        if age <= 60 * 60 * 24 * 7 {
            return 22
        }
        if age <= 60 * 60 * 24 * 30 {
            return 10
        }
        return 0
    }

    private func matchScore(query: String, fields: [String]) -> Double {
        guard !query.isEmpty else { return 0 }

        let loweredFields = fields
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        guard !loweredFields.isEmpty else { return 0 }

        var best: Double = 0
        for field in loweredFields {
            if field == query {
                best = max(best, 1200)
            } else if field.hasPrefix(query) {
                best = max(best, 720 + Double(query.count))
            } else if field.localizedCaseInsensitiveContains(query) {
                best = max(best, 420 + Double(query.count) - Double(field.count) * 0.1)
            }

            let fuzzy = fuzzyMatch(query: query, target: field)
            best = max(best, fuzzy)
        }

        if best > 0 {
            return best
        }

        let tokens = query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard tokens.count > 1 else {
            return 0
        }

        let tokenMatch = tokens.allSatisfy { token in
            loweredFields.contains { $0.localizedCaseInsensitiveContains(token) }
        }
        return tokenMatch ? 260 + Double(tokens.count) * 10 : 0
    }

    private func fuzzyMatch(query: String, target: String) -> Double {
        guard !query.isEmpty else { return 0 }

        var score: Double = 0
        var queryIndex = query.startIndex
        var lastMatchIndex: String.Index?
        var consecutiveMatches = 0

        if target == query {
            return 1000
        }

        if target.hasPrefix(query) {
            return 500 + Double(query.count)
        }

        var targetIndex = target.startIndex
        while targetIndex < target.endIndex {
            let targetChar = target[targetIndex]
            if queryIndex < query.endIndex && targetChar == query[queryIndex] {
                score += 10

                if let last = lastMatchIndex, target.index(after: last) == targetIndex {
                    consecutiveMatches += 1
                    score += Double(consecutiveMatches) * 5
                } else {
                    consecutiveMatches = 0
                }

                if targetIndex == target.startIndex {
                    score += 15
                } else {
                    let prev = target[target.index(before: targetIndex)]
                    if prev == "/" || prev == "." || prev == " " || prev == "-" {
                        score += 15
                    }
                }

                lastMatchIndex = targetIndex
                queryIndex = query.index(after: queryIndex)
            }

            targetIndex = target.index(after: targetIndex)
        }

        if queryIndex == query.endIndex {
            score -= Double(target.count) * 0.1
            return score
        }

        return 0
    }
}
