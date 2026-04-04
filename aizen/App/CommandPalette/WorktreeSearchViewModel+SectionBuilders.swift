//
//  WorktreeSearchViewModel+SectionBuilders.swift
//  aizen
//
//  Created by OpenAI Codex on 04.04.26.
//

import CoreData
import Foundation

@MainActor
extension WorktreeSearchViewModel {
    func buildAllSections(
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
                    .filter { CommandPaletteRecency.isRecent($0.lastAccessed) }
                    .sorted { $0.score > $1.score }
            }

            let recent = CommandPaletteResultSlice.uniqueSlice(
                from: recentCandidates,
                taking: 8,
                consumedIds: &consumedIds
            )
            if !recent.isEmpty {
                sections.append(CommandPaletteSection(id: "recent", title: "Recent", items: recent))
            }

            let currentProject = CommandPaletteResultSlice.uniqueSlice(
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

            let others = CommandPaletteResultSlice.uniqueSlice(
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

    func buildCurrentProjectSections(
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

    func buildWorkspaceSections(
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

    func buildTabsSections(
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
}
