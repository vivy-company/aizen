//
//  WorkspacePaneView.swift
//  aizen
//
//  A single workspace pane: chrome (header, focus ring) plus content
//  dispatched by pane kind.
//

import SwiftUI

struct WorkspacePaneView: View {
    let pane: WorkspacePane
    @ObservedObject var scene: WorktreeSceneStore
    @ObservedObject var workspace: WorkspaceStore
    @ObservedObject var worktree: Worktree
    let effectiveThemeName: String
    let isSplit: Bool
    @Binding var searchOpenRequest: SearchOpenRequest?

    @State private var browserSelectionId: UUID?

    private var isFocused: Bool {
        workspace.focusedPaneId == pane.id
    }

    var body: some View {
        VStack(spacing: 0) {
            if pane.kind != .empty {
                WorkspacePaneHeaderView(pane: pane, workspace: workspace, isFocused: isFocused, isSplit: isSplit)
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .simultaneousGesture(
            TapGesture().onEnded {
                workspace.focusPane(pane.id)
            }
        )
        .task(id: pane.kind) {
            scene.ensureStore(for: pane.kind)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch pane.kind {
        case .terminal:
            terminalContent

        case .chat:
            if let sessionId = pane.sessionId,
               let session = workspace.chatSession(withId: sessionId) {
                ChatSessionView(
                    worktree: worktree,
                    viewModel: scene.chatStore(for: session),
                    isSelected: isFocused
                )
            } else {
                missingSessionFallback
            }

        case .files:
            FileTabView(
                worktree: worktree,
                searchOpenRequest: $searchOpenRequest,
                showPathHeader: false,
                store: scene.fileBrowserStore
            )

        case .browser:
            if let browserSessionStore = scene.browserSessionStore {
                BrowserTabView(
                    manager: browserSessionStore,
                    selectedSessionId: $browserSelectionId,
                    isSelected: isFocused
                )
                .id(ObjectIdentifier(browserSessionStore))
            } else {
                BrowserTabView(
                    worktree: worktree,
                    selectedSessionId: $browserSelectionId,
                    isSelected: isFocused
                )
                .id(worktree.objectID)
            }

        case .gitDiff:
            CompanionGitDiffView(worktree: worktree)

        case .empty:
            WorkspaceEmptyPaneView { kind in
                workspace.replacePane(pane.id, with: kind)
            }
        }
    }

    @ViewBuilder
    private var terminalContent: some View {
        if let sessionId = pane.sessionId,
           let session = workspace.terminalSession(withId: sessionId) {
            let voiceActionBinding = Binding<VoiceAction?>(
                get: { workspace.voiceAction?.paneId == pane.id ? workspace.voiceAction?.action : nil },
                set: { _ in workspace.voiceAction = nil }
            )

            AizenTerminalRootContainer(identity: pane.id) {
                TerminalPaneView(
                    worktree: worktree,
                    session: session,
                    paneId: pane.id,
                    effectiveThemeName: effectiveThemeName,
                    isSplit: isSplit,
                    isFocused: isFocused,
                    sessionManager: TerminalRuntimeStore.shared,
                    voiceAction: voiceActionBinding,
                    focusRequestVersion: workspace.focusRequestVersion,
                    onFocus: { workspace.focusPane(pane.id) },
                    onProcessExit: { workspace.handleTerminalProcessExit(paneId: pane.id) },
                    onTitleChange: { _ in },
                    onVoiceRecordingChanged: { workspace.handleVoiceRecordingChanged(for: pane.id, isRecording: $0) }
                )
            }
        } else {
            missingSessionFallback
        }
    }

    private var missingSessionFallback: some View {
        WorkspaceEmptyPaneView { kind in
            workspace.replacePane(pane.id, with: kind)
        }
    }
}

// MARK: - Header

struct WorkspacePaneHeaderView: View {
    let pane: WorkspacePane
    @ObservedObject var workspace: WorkspaceStore
    let isFocused: Bool
    let isSplit: Bool

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            Menu {
                Section(String(localized: "workspace.pane.replaceWith", defaultValue: "Replace With")) {
                    ForEach(PaneKindPresentation.selectableKinds, id: \.self) { kind in
                        Button {
                            workspace.replacePane(pane.id, with: kind)
                        } label: {
                            Label(PaneKindPresentation.title(for: kind), systemImage: PaneKindPresentation.icon(for: kind))
                        }
                        .disabled(kind == pane.kind)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: PaneKindPresentation.icon(for: pane.kind))
                        .foregroundStyle(isFocused && isSplit ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                    Text(PaneKindPresentation.title(for: pane.kind))
                        .foregroundStyle(isFocused ? .primary : .secondary)
                }
                .font(.caption)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Spacer(minLength: 0)

            if isHovering {
                Button {
                    workspace.focusPane(pane.id)
                    workspace.splitFocusedPane(direction: .horizontal, insertion: .after)
                } label: {
                    Image(systemName: "rectangle.split.2x1")
                }
                .buttonStyle(.borderless)
                .help(String(localized: "workspace.pane.splitRight", defaultValue: "Split Right (⌘D)"))

                Button {
                    workspace.focusPane(pane.id)
                    workspace.splitFocusedPane(direction: .vertical, insertion: .after)
                } label: {
                    Image(systemName: "rectangle.split.1x2")
                }
                .buttonStyle(.borderless)
                .help(String(localized: "workspace.pane.splitDown", defaultValue: "Split Down (⇧⌘D)"))

                Button {
                    workspace.requestClosePane(pane.id)
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help(String(localized: "workspace.pane.close", defaultValue: "Close Pane (⌘W)"))
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Divider()
        }
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// MARK: - Empty pane picker

struct WorkspaceEmptyPaneView: View {
    let onSelect: (PaneKind) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(String(localized: "workspace.empty.title", defaultValue: "What goes here?"))
                .font(.headline)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                ForEach(Array(PaneKindPresentation.selectableKinds.enumerated()), id: \.element) { index, kind in
                    kindButton(kind, shortcut: index + 1)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func kindButton(_ kind: PaneKind, shortcut: Int) -> some View {
        let button = Button {
            onSelect(kind)
        } label: {
            VStack(spacing: 6) {
                Image(systemName: PaneKindPresentation.icon(for: kind))
                    .font(.title3)
                Text(PaneKindPresentation.title(for: kind))
                    .font(.caption)
                Text(verbatim: "\(shortcut)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 76, height: 68)
        }

        if #available(macOS 26.0, *) {
            button.buttonStyle(.glass)
        } else {
            button.buttonStyle(.bordered)
        }
    }
}
