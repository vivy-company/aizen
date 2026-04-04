//
//  RepositoryRow+ContextMenu.swift
//  aizen
//

import SwiftUI

extension RepositoryRow {
    @ViewBuilder
    var repositoryContextMenu: some View {
        Button {
            if let path = repository.path {
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
                Label("workspace.repository.openTerminal", systemImage: "terminal")
            }
        }

        Button {
            if let path = repository.path {
                repositoryManager.openInFinder(path)
            }
        } label: {
            if let finder = finderApp {
                AppMenuLabel(app: finder)
            } else {
                Label("workspace.repository.openFinder", systemImage: "folder")
            }
        }

        Button {
            if let path = repository.path {
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
                Label("workspace.repository.openEditor", systemImage: "chevron.left.forwardslash.chevron.right")
            }
        }

        Menu {
            Text("Terminals")
                .font(.caption)

            ForEach(sortedApps(AppDetector.shared.getTerminals(), defaultBundleId: defaultTerminalBundleId)) { terminal in
                Button {
                    if let path = repository.path {
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

            Divider()

            Text("Editors")
                .font(.caption)

            ForEach(sortedApps(AppDetector.shared.getEditors(), defaultBundleId: defaultEditorBundleId)) { editor in
                Button {
                    if let path = repository.path {
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
        } label: {
            Label("Open in...", systemImage: "arrow.up.forward.app")
        }

        Button {
            if let path = repository.path {
                Clipboard.copy(path)
            }
        } label: {
            Label("workspace.repository.copyPath", systemImage: "doc.on.doc")
        }

        Divider()

        Menu {
            ForEach(ItemStatus.allCases) { status in
                Button {
                    setStatus(status)
                } label: {
                    HStack {
                        Circle()
                            .fill(status.color)
                            .frame(width: 8, height: 8)
                        Text(status.title)
                        if repositoryStatus == status {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Label("repository.setStatus", systemImage: "circle.fill")
        }

        Button {
            showingNoteEditor = true
        } label: {
            Label("repository.editNote", systemImage: "note.text")
        }

        Button {
            showingPostCreateActions = true
        } label: {
            Label("Post-Create Actions", systemImage: "gearshape.2")
        }

        Divider()

        Button(role: .destructive) {
            showingRemoveConfirmation = true
        } label: {
            Label("workspace.repository.remove", systemImage: "trash")
        }
    }
}
