//
//  WorktreeListItemView+Menus.swift
//  aizen
//
//  Context menu support views and app sorting for worktree rows.
//

import SwiftUI

extension WorktreeListItemView {
    func sortedApps(_ apps: [DetectedApp], defaultBundleId: String?) -> [DetectedApp] {
        guard let defaultId = defaultBundleId else { return apps }
        var sorted = apps.filter { $0.bundleIdentifier != defaultId }
        if let defaultApp = apps.first(where: { $0.bundleIdentifier == defaultId }) {
            sorted.insert(defaultApp, at: 0)
        }
        return sorted
    }

    func mergeSourceButton(for statusInfo: WorktreeStatusInfo) -> some View {
        Button {
            performMerge(from: statusInfo.worktree, to: worktree)
        } label: {
            HStack {
                Text(statusInfo.branch)
                if statusInfo.hasUncommittedChanges {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    var mergeOperationsMenu: some View {
        Menu {
            ForEach(mergeSourceStatuses, id: \.worktree.id) { statusInfo in
                mergeSourceButton(for: statusInfo)
            }
        } label: {
            Label(String(localized: "worktree.merge.pullFrom"), systemImage: "arrow.down.circle")
        }
    }

    func terminalOptionButton(_ terminal: DetectedApp) -> some View {
        Button {
            if let path = worktree.path {
                AppDetector.shared.openPath(path, with: terminal)
            }
        } label: {
            HStack {
                AppMenuLabel(app: terminal)
                if terminal.bundleIdentifier == defaultTerminalBundleId {
                    Spacer()
                    Image(systemName: "checkmark")
                }
            }
        }
    }

    func editorOptionButton(_ editor: DetectedApp) -> some View {
        Button {
            if let path = worktree.path {
                AppDetector.shared.openPath(path, with: editor)
            }
        } label: {
            HStack {
                AppMenuLabel(app: editor)
                if editor.bundleIdentifier == defaultEditorBundleId {
                    Spacer()
                    Image(systemName: "checkmark")
                }
            }
        }
    }

    var openInAppsMenu: some View {
        Menu {
            Text(String(localized: "worktree.openIn.terminals"))
                .font(.caption)

            ForEach(sortedApps(AppDetector.shared.getTerminals(), defaultBundleId: defaultTerminalBundleId)) { terminal in
                terminalOptionButton(terminal)
            }

            Divider()

            Text(String(localized: "worktree.openIn.editors"))
                .font(.caption)

            ForEach(sortedApps(AppDetector.shared.getEditors(), defaultBundleId: defaultEditorBundleId)) { editor in
                editorOptionButton(editor)
            }
        } label: {
            Label(String(localized: "worktree.openIn.title"), systemImage: "arrow.up.forward.app")
        }
    }

    func statusMenuButton(for status: ItemStatus) -> some View {
        Button {
            setWorktreeStatus(status)
        } label: {
            HStack {
                Circle()
                    .fill(status.color)
                    .frame(width: 8, height: 8)
                Text(status.title)
                if worktreeStatus == status {
                    Spacer()
                    Image(systemName: "checkmark")
                }
            }
        }
    }

    var statusMenu: some View {
        Menu {
            ForEach(ItemStatus.allCases) { status in
                statusMenuButton(for: status)
            }
        } label: {
            Label("worktree.setStatus", systemImage: "circle.fill")
        }
    }
}
