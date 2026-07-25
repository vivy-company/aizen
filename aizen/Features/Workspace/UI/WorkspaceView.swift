//
//  WorkspaceView.swift
//  aizen
//
//  The worktree working area: a split tree of typed panes. Layout tabs are
//  rendered in the window toolbar (WorkspaceTabStripView).
//

import SwiftUI

struct WorkspaceView: View {
    @ObservedObject var scene: WorktreeSceneStore
    @ObservedObject var workspace: WorkspaceStore
    @ObservedObject var worktree: Worktree
    @Binding var searchOpenRequest: SearchOpenRequest?

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppearanceSettings.themeNameKey) private var terminalThemeName = AppearanceSettings.defaultDarkTheme
    @AppStorage(AppearanceSettings.usePerAppearanceThemeKey) private var usePerAppearanceTheme = false

    init(scene: WorktreeSceneStore, searchOpenRequest: Binding<SearchOpenRequest?>) {
        self.scene = scene
        self.workspace = scene.workspace
        self.worktree = scene.worktree
        _searchOpenRequest = searchOpenRequest
    }

    private var effectiveThemeName: String {
        guard usePerAppearanceTheme else { return terminalThemeName }
        return AppearanceSettings.effectiveThemeName(colorScheme: colorScheme)
    }

    private var paneSessionSignature: String {
        WorkspaceLayoutCodec.encode(workspace.tree) ?? ""
    }

    var body: some View {
        WorkspaceSplitTreeView(
            tree: workspace.tree,
            dividerColor: Color(nsColor: GhosttyThemeParser.loadDividerColor(named: effectiveThemeName)),
            onResize: { workspace.resizeSplit(at: $0, to: $1) },
            onEqualize: { workspace.equalize() }
        ) { pane in
            WorkspacePaneView(
                pane: pane,
                scene: scene,
                workspace: workspace,
                worktree: worktree,
                effectiveThemeName: effectiveThemeName,
                isSplit: workspace.tree.leafCount() > 1,
                searchOpenRequest: $searchOpenRequest
            )
        }
        .onAppear {
            workspace.handleAppear()
        }
        .onDisappear {
            workspace.handleDisappear()
        }
        .task(id: paneSessionSignature) {
            scene.synchronizePaneStores(with: workspace.tree.allPanes())
        }
        .background {
            keyboardShortcutButtons
        }
        .alert(
            String(localized: "workspace.close.confirmTitle", defaultValue: "Close Pane?"),
            isPresented: Binding(
                get: { workspace.pendingCloseConfirmationPaneId != nil },
                set: { if !$0 { workspace.pendingCloseConfirmationPaneId = nil } }
            )
        ) {
            Button(String(localized: "workspace.close.cancel", defaultValue: "Cancel"), role: .cancel) {}
            Button(String(localized: "workspace.close.confirm", defaultValue: "Close"), role: .destructive) {
                workspace.confirmPendingClose()
            }
            .keyboardShortcut(.defaultAction)
        } message: {
            Text(String(
                localized: "workspace.close.confirmMessage",
                defaultValue: "A process is still running in this pane. Are you sure you want to close it?"
            ))
        }
    }

    private var keyboardShortcutButtons: some View {
        Group {
            // Layout tabs: cmd+1..9 direct, ctrl+tab cycles, cmd+T new.
            ForEach(1...9, id: \.self) { index in
                Button("") { workspace.selectLayout(at: index - 1) }
                    .keyboardShortcut(KeyEquivalent(Character("\(index)")), modifiers: .command)
            }
            Button("") { workspace.cycleLayout(step: 1) }
                .keyboardShortcut(.tab, modifiers: [.control])
            Button("") { workspace.cycleLayout(step: -1) }
                .keyboardShortcut(.tab, modifiers: [.control, .shift])
            Button("") { workspace.addLayout() }
                .keyboardShortcut("t", modifiers: .command)

            // Directional pane focus: cmd+option+arrows.
            Button("") { workspace.moveFocus(.left) }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
            Button("") { workspace.moveFocus(.right) }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            Button("") { workspace.moveFocus(.up) }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
            Button("") { workspace.moveFocus(.down) }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])

            // Empty pane: plain number keys pick a kind for the focused pane.
            if let focusedPane = workspace.focusedPane, focusedPane.kind == .empty {
                ForEach(Array(PaneKindPresentation.selectableKinds.enumerated()), id: \.offset) { index, kind in
                    Button("") { workspace.replacePane(focusedPane.id, with: kind) }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [])
                }
            }
        }
        .hidden()
    }
}

// MARK: - Layout tab strip (hosted in the window toolbar)

struct WorkspaceTabStripView: View {
    @ObservedObject var workspace: WorkspaceStore

    var body: some View {
        HStack(spacing: 4) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(workspace.layouts) { layout in
                            WorkspaceLayoutTabItemView(
                                layout: layout,
                                workspace: workspace,
                                isSelected: layout.id == workspace.activeLayoutId,
                                onSelect: { workspace.selectLayout(layout) },
                                onClose: { workspace.closeLayout(layout) }
                            )
                            .id(layout.id)
                            .contextMenu {
                                Button(String(localized: "workspace.layout.close", defaultValue: "Close Tab")) {
                                    workspace.closeLayout(layout)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 6)
                }
                .frame(maxWidth: 600, maxHeight: 36)
                .onChange(of: workspace.activeLayoutId) { _, newValue in
                    if let newValue {
                        withAnimation {
                            proxy.scrollTo(newValue)
                        }
                    }
                }
            }

            WorkspaceNewTabButton(workspace: workspace)
                .padding(.trailing, 8)
        }
    }
}

struct WorkspaceLayoutTabItemView: View {
    let layout: WorktreeLayout
    @ObservedObject var workspace: WorkspaceStore
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        SessionTabButton(isSelected: isSelected, action: onSelect) {
            HStack(spacing: 6) {
                DetailCloseButton(action: onClose, size: 10)

                Image(systemName: PaneKindPresentation.icon(for: workspace.primaryKind(for: layout)))
                    .font(.system(size: 12))

                Text(workspace.displayName(for: layout))
                    .font(.callout)
            }
        }
    }
}

struct WorkspaceNewTabButton: View {
    @ObservedObject var workspace: WorkspaceStore
    @State private var isHovering = false

    var body: some View {
        Menu {
            ForEach(PaneKindPresentation.selectableKinds, id: \.self) { kind in
                Button {
                    workspace.addLayout(kind: kind)
                } label: {
                    Label(PaneKindPresentation.title(for: kind), systemImage: PaneKindPresentation.icon(for: kind))
                }
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 11))
                .frame(width: 24, height: 24)
                .background(
                    isHovering ? Color(nsColor: .separatorColor).opacity(0.5) : Color.clear,
                    in: Circle()
                )
        } primaryAction: {
            workspace.addLayout()
        }
        .menuStyle(.button)
        .menuIndicator(.visible)
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
        .help(String(localized: "workspace.layout.addHelp", defaultValue: "Click for empty tab, or click arrow for a specific pane"))
    }
}

// MARK: - Session tab button (capsule chip)

struct SessionTabButton<Content: View>: View {
    let isSelected: Bool
    let action: () -> Void
    let content: Content

    @State private var isHovering = false

    init(isSelected: Bool, action: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.isSelected = isSelected
        self.action = action
        self.content = content()
    }

    var body: some View {
        Button(action: action) {
            content
                .padding(.leading, 6)
                .padding(.trailing, 12)
                .padding(.vertical, 6)
                .background(
                    isSelected ?
                    Color(nsColor: .separatorColor) :
                    (isHovering ? Color(nsColor: .separatorColor).opacity(0.5) : Color.clear),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
