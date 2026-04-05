//
//  WorktreeListItemView.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import SwiftUI
import os.log

struct WorktreeListItemView: View {
    @ObservedObject var worktree: Worktree
    let isSelected: Bool
    @ObservedObject var repositoryManager: WorkspaceRepositoryStore
    let allWorktrees: [Worktree]
    @Binding var selectedWorktree: Worktree?
    @ObservedObject var tabStateManager: WorktreeTabStateStore
    @Environment(\.controlActiveState) var controlActiveState

    let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen.app", category: "WorktreeListItemView")

    @AppStorage("defaultTerminalBundleId") var defaultTerminalBundleId: String?
    @AppStorage("defaultEditorBundleId") var defaultEditorBundleId: String?

    @State var showingDetails = false
    @State var showingDeleteConfirmation = false
    @State var hasUnsavedChanges = false
    @State var errorMessage: String?
    @State var worktreeStatuses: [WorktreeStatusInfo] = []
    @State var isLoadingStatuses = false
    @State var mergeErrorMessage: String?
    @State var mergeConflictFiles: [String] = []
    @State var showingMergeConflict = false
    @State var showingMergeSuccess = false
    @State var mergeSuccessMessage = ""
    @State var availableBranches: [BranchInfo] = []
    @State var isLoadingBranches = false
    @State var showingBranchSelector = false
    @State var branchSwitchError: String?
    @State var showingNoteEditor = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                if worktree.isPrimary {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 14, height: 14)
                        .foregroundStyle(
                            isSelected
                                ? selectedForegroundColor
                                : Color(nsColor: .systemOrange).opacity(0.88)
                        )
                        .help(String(localized: "worktree.detail.main"))
                }

                Text(worktree.branch ?? String(localized: "worktree.list.unknown"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(primaryTextColor)
                    .lineLimit(1)

                Spacer(minLength: 8)

                sessionIcons
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let note = worktree.note, !note.isEmpty {
                Text(note)
                    .font(.subheadline)
                    .foregroundStyle(secondaryTextColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isSelected
                ? RoundedRectangle(cornerRadius: 6)
                    .fill(selectionFillColor)
                : nil
        )
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                showingDetails = true
            } label: {
                Label(String(localized: "worktree.detail.showDetails"), systemImage: "info.circle")
            }

            Divider()

            // Open in Terminal (with real name and icon)
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

            // Open in Finder (with real icon)
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

            // Open in Editor (with real name and icon)
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

            // Open in... submenu
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

            // Status submenu
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
        .worktreeListItemPresentation(view: self)
    }

}
