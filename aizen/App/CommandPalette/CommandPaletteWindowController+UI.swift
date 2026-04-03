//
//  CommandPaletteWindowController+UI.swift
//  aizen
//
//  Presentation helpers for command palette content
//

import SwiftUI

extension CommandPaletteContent {
    func placeholderText(for scope: CommandPaletteScope) -> LocalizedStringKey {
        switch scope {
        case .all:
            return "Search everything…"
        case .currentProject:
            return "Search in current project…"
        case .workspace:
            return "Search workspaces…"
        case .tabs:
            return "Search tabs and sessions…"
        }
    }

    var scopeChips: some View {
        HStack(spacing: 8) {
            scopeChip(.all, shortcut: "⌘1")
            scopeChip(.currentProject, shortcut: "⌘2")
            scopeChip(.workspace, shortcut: "⌘3")
            scopeChip(.tabs, shortcut: "⌘4")
            Spacer(minLength: 0)
        }
    }

    func scopeChip(_ scope: CommandPaletteScope, shortcut: String) -> some View {
        let isSelected = viewModel.scope == scope

        return Button {
            interaction.didUseKeyboard()
            viewModel.setScope(scope)
        } label: {
            HStack(spacing: 6) {
                Text(scope.title)
                    .font(.system(size: 12, weight: .semibold))
                Text(shortcut)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(isSelected ? .primary : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.12) : Color.white.opacity(0.04))
                    .overlay {
                        if isSelected {
                            Capsule(style: .continuous)
                                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                        }
                    }
            )
        }
        .buttonStyle(.plain)
    }

    func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    func paletteBadge(text: String) -> some View {
        if text == "main" {
            PillBadge(
                text: text,
                color: .blue,
                textColor: .white,
                font: .caption2,
                fontWeight: .semibold,
                horizontalPadding: 6,
                verticalPadding: 2,
                backgroundOpacity: 1
            )
        } else if text == "cross-project" {
            PillBadge(
                text: text,
                color: .red,
                textColor: .white,
                font: .caption2,
                fontWeight: .semibold,
                horizontalPadding: 6,
                verticalPadding: 2,
                backgroundOpacity: 1
            )
        }
    }

    var emptyResultsView: some View {
        VStack(spacing: 10) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.secondary.opacity(0.5))
            Text(emptyStateText(for: viewModel.scope))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 90)
    }

    func emptyStateText(for scope: CommandPaletteScope) -> String {
        switch scope {
        case .all:
            return "No results found"
        case .currentProject:
            return "No project results found"
        case .workspace:
            return "No workspaces found"
        case .tabs:
            return "No tabs or sessions found"
        }
    }

    var footer: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                KeyCap(text: "↑")
                KeyCap(text: "↓")
                Text("Navigate")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 6) {
                KeyCap(text: "⌘1-4")
                Text("Scope")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                KeyCap(text: "↩")
                Text("Open")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                KeyCap(text: "Tab")
                Text("Next Scope")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.clear)
    }
}
