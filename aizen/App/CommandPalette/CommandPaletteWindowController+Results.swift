//
//  CommandPaletteWindowController+Results.swift
//  aizen
//
//  Result list rendering and selection helpers for the command palette
//

import SwiftUI

extension CommandPaletteContent {
    var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(viewModel.sections.enumerated()), id: \.element.id) { sectionOffset, section in
                        sectionHeader(section.title)

                        ForEach(Array(section.items.enumerated()), id: \.element.id) { itemOffset, item in
                            let globalIndex = globalIndexFor(sectionOffset: sectionOffset, itemOffset: itemOffset)
                            resultRow(
                                item: item,
                                globalIndex: globalIndex,
                                isSelected: globalIndex == viewModel.selectedIndex,
                                isHovered: hoveredIndex == globalIndex
                            )
                            .id(globalIndex)
                        }
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 10)
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .scrollIndicators(.hidden)
            .frame(maxHeight: 360)
            .task(id: viewModel.selectedIndex) {
                proxy.scrollTo(viewModel.selectedIndex, anchor: .center)
            }
        }
        .id(viewModel.scope)
    }

    func resultRow(
        item: CommandPaletteItem,
        globalIndex: Int,
        isSelected: Bool,
        isHovered: Bool
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: item.icon)
                .foregroundStyle(itemColor(for: item, isSelected: isSelected))
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)

                    if let badgeText = item.badgeText {
                        paletteBadge(text: badgeText)
                    }
                }

                Text(item.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    isSelected ? Color.white.opacity(0.12) :
                        (isHovered ? Color.white.opacity(0.06) : Color.clear)
                )
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                    }
                }
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if let action = action(for: item) {
                handleSelection(action)
            }
        }
        .onHover { hovering in
            guard interaction.allowHoverSelection else { return }
            hoveredIndex = hovering ? globalIndex : nil
        }
    }

    func itemColor(for item: CommandPaletteItem, isSelected: Bool) -> Color {
        if isSelected {
            return .primary
        }
        if item.badgeText == "cross-project" {
            return .red
        }
        return .secondary
    }

    func action(for item: CommandPaletteItem) -> CommandPaletteNavigationAction? {
        guard let workspaceId = item.workspaceId,
              let repoId = item.repoId,
              let worktreeId = item.worktreeId else {
            return nil
        }

        switch item.kind {
        case .worktree, .workspace:
            return .worktree(workspaceId: workspaceId, repoId: repoId, worktreeId: worktreeId)
        case .tab:
            guard let tabId = item.tabId else { return nil }
            return .tab(workspaceId: workspaceId, repoId: repoId, worktreeId: worktreeId, tabId: tabId)
        case .chatSession:
            guard let sessionId = item.sessionId else { return nil }
            return .chatSession(workspaceId: workspaceId, repoId: repoId, worktreeId: worktreeId, sessionId: sessionId)
        case .terminalSession:
            guard let sessionId = item.sessionId else { return nil }
            return .terminalSession(workspaceId: workspaceId, repoId: repoId, worktreeId: worktreeId, sessionId: sessionId)
        case .browserSession:
            guard let sessionId = item.sessionId else { return nil }
            return .browserSession(workspaceId: workspaceId, repoId: repoId, worktreeId: worktreeId, sessionId: sessionId)
        }
    }

    func globalIndexFor(sectionOffset: Int, itemOffset: Int) -> Int {
        let prefixCount = viewModel.sections
            .prefix(sectionOffset)
            .reduce(0) { partial, section in
                partial + section.items.count
            }
        return prefixCount + itemOffset
    }

    var activeResultsEmpty: Bool {
        viewModel.sections.allSatisfy { $0.items.isEmpty }
    }

    func handleSelection(_ action: CommandPaletteNavigationAction) {
        switch action {
        case .worktree(_, _, let worktreeId),
             .tab(_, _, let worktreeId, _),
             .chatSession(_, _, let worktreeId, _),
             .terminalSession(_, _, let worktreeId, _),
             .browserSession(_, _, let worktreeId, _):
            if let worktree = allWorktrees.first(where: { $0.id == worktreeId }) {
                worktree.lastAccessed = Date()
                try? viewContext.save()
            }
        }

        onNavigate(action)
        onClose()
    }
}
