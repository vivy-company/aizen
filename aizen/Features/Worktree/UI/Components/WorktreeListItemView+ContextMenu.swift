import SwiftUI

extension WorktreeListItemView {
    @ViewBuilder
    var contextMenuContent: some View {
        Button {
            showingDetails = true
        } label: {
            Label(String(localized: "worktree.detail.showDetails"), systemImage: "info.circle")
        }

        Divider()

        Button {
            if let path = worktree.path {
                if let terminal = defaultTerminal {
                    AppDetector.shared.openPath(path, with: terminal)
                } else {
                    repositoryManager.openInTerminal(path)
                }
            }
        } label: {
            if let terminal = defaultTerminal {
                AppMenuLabel(app: terminal)
            } else {
                Label(String(localized: "worktree.detail.openTerminal"), systemImage: "terminal")
            }
        }

        Button {
            if let path = worktree.path {
                repositoryManager.openInFinder(path)
            }
        } label: {
            if let finder = finderApp {
                AppMenuLabel(app: finder)
            } else {
                Label(String(localized: "worktree.detail.openFinder"), systemImage: "folder")
            }
        }

        Button {
            if let path = worktree.path {
                if let editor = defaultEditor {
                    AppDetector.shared.openPath(path, with: editor)
                } else {
                    repositoryManager.openInEditor(path)
                }
            }
        } label: {
            if let editor = defaultEditor {
                AppMenuLabel(app: editor)
            } else {
                Label(String(localized: "worktree.detail.openEditor"), systemImage: "chevron.left.forwardslash.chevron.right")
            }
        }

        openInAppsMenu

        if isGitEnvironment {
            Button {
                if let branch = worktree.branch {
                    Clipboard.copy(branch)
                }
            } label: {
                Label(String(localized: "worktree.detail.copyBranchName"), systemImage: "doc.on.doc")
            }
        }

        Button {
            if let path = worktree.path {
                Clipboard.copy(path)
            }
        } label: {
            Label(String(localized: "worktree.detail.copyPath"), systemImage: "doc.on.clipboard")
        }

        Divider()

        if supportsMergeOperations {
            mergeOperationsMenu
            Divider()
        }

        if supportsBranchOperations {
            BranchSwitchMenu(
                worktreeBranch: worktree.branch,
                availableBranches: availableBranches,
                isLoadingBranches: isLoadingBranches,
                onLoadBranches: loadAvailableBranches,
                onSelectBranch: switchToBranch,
                onOpenSelector: { showingBranchSelector = true }
            )

            Divider()
        }

        statusMenu

        Button {
            showingNoteEditor = true
        } label: {
            Label("worktree.editNote", systemImage: "note.text")
        }

        if !worktree.isPrimary {
            Divider()

            Button(role: .destructive) {
                checkUnsavedChanges()
            } label: {
                Label(String(localized: "worktree.detail.delete"), systemImage: "trash")
            }
        }
    }
}
