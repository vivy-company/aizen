//
//  CommandPaletteWindowController.swift
//  aizen
//
//  Command palette for fast navigation between worktrees, tabs, and sessions.
//

import AppKit
import CoreData
import SwiftUI

class CommandPaletteWindowController: NSWindowController {
    private var appDeactivationObserver: NSObjectProtocol?
    private var windowResignKeyObserver: NSObjectProtocol?
    private var eventMonitor: Any?

    convenience init(
        managedObjectContext: NSManagedObjectContext,
        currentRepositoryId: String?,
        currentWorkspaceId: String?,
        onNavigate: @escaping (CommandPaletteNavigationAction) -> Void
    ) {
        let viewModel = WorktreeSearchViewModel(
            currentRepositoryId: currentRepositoryId,
            currentWorkspaceId: currentWorkspaceId
        )
        let panel = CommandPalettePanel(
            managedObjectContext: managedObjectContext,
            viewModel: viewModel,
            onNavigate: onNavigate
        )
        self.init(window: panel)
        panel.requestClose = { [weak self] in
            self?.closeWindow()
        }
        panel.requestScopeCycle = {
            viewModel.cycleScopeForward()
        }
        setupAppObservers()
    }

    deinit {
        cleanup()
    }

    private func setupAppObservers() {
        appDeactivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.closeWindow()
        }

        windowResignKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.closeWindow()
        }
    }

    private func cleanup() {
        if let observer = appDeactivationObserver {
            NotificationCenter.default.removeObserver(observer)
            appDeactivationObserver = nil
        }
        if let observer = windowResignKeyObserver {
            NotificationCenter.default.removeObserver(observer)
            windowResignKeyObserver = nil
        }
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    override func showWindow(_ sender: Any?) {
        guard let panel = window as? CommandPalettePanel else { return }
        positionPanel(panel)
        panel.makeKeyAndOrderFront(nil)
        setupEventMonitor(for: panel)
        DispatchQueue.main.async {
            panel.makeKey()
        }
    }

    private func setupEventMonitor(for panel: CommandPalettePanel) {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }

        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .mouseMoved, .keyDown]
        ) { [weak self, weak panel] event in
            guard let self, let panel else { return event }
            guard panel.isVisible else { return event }

            if event.type == .keyDown {
                if event.keyCode == 48 { // Tab
                    panel.requestScopeCycle?()
                    return nil
                }
                return event
            }

            if event.type == .mouseMoved {
                panel.interaction.didMoveMouse()
                return event
            }

            let mouseLocation = NSEvent.mouseLocation
            if !panel.frame.contains(mouseLocation) {
                self.closeWindow()
            }
            return event
        }
    }

    private func positionPanel(_ panel: CommandPalettePanel) {
        let mouseLocation = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first { screen in
            NSMouseInRect(mouseLocation, screen.frame, false)
        } ?? NSScreen.main

        guard let screen = targetScreen else { return }

        let screenFrame = screen.visibleFrame
        let panelFrame = panel.frame

        let x = screenFrame.midX - panelFrame.width / 2
        let y = screenFrame.maxY - panelFrame.height - 100

        let adjustedX = max(screenFrame.minX, min(x, screenFrame.maxX - panelFrame.width))
        let adjustedY = max(screenFrame.minY, min(y, screenFrame.maxY - panelFrame.height))

        panel.setFrameOrigin(NSPoint(x: adjustedX, y: adjustedY))
    }

    func closeWindow() {
        cleanup()
        window?.close()
    }
}

class CommandPalettePanel: NSPanel {
    let interaction = PaletteInteractionState()
    var requestClose: (() -> Void)?
    var requestScopeCycle: (() -> Void)?

    init(
        managedObjectContext: NSManagedObjectContext,
        viewModel: WorktreeSearchViewModel,
        onNavigate: @escaping (CommandPaletteNavigationAction) -> Void
    ) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        self.isOpaque = false
        self.backgroundColor = NSColor.clear
        self.hasShadow = true
        self.level = .floating
        self.isMovableByWindowBackground = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.becomesKeyOnlyIfNeeded = true
        self.isFloatingPanel = true
        self.acceptsMouseMovedEvents = true

        let hostingView = NSHostingView(
            rootView: CommandPaletteContent(
                onNavigate: onNavigate,
                onClose: { [weak self] in
                    if let close = self?.requestClose {
                        close()
                    } else {
                        self?.close()
                    }
                },
                viewModel: viewModel
            )
            .environment(\.managedObjectContext, managedObjectContext)
            .environmentObject(interaction)
        )

        hostingView.wantsLayer = true
        hostingView.layer?.isOpaque = false
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor

        self.contentView = hostingView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC key
            requestClose?()
        } else if event.keyCode == 48 { // Tab
            requestScopeCycle?()
        } else {
            super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        requestClose?()
    }
}

struct CommandPaletteContent: View {
    let onNavigate: (CommandPaletteNavigationAction) -> Void
    let onClose: () -> Void
    @ObservedObject var viewModel: WorktreeSearchViewModel

    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Worktree.lastAccessed, ascending: false)],
        animation: .default
    )
    private var allWorktrees: FetchedResults<Worktree>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Workspace.order, ascending: true)],
        animation: .default
    )
    private var allWorkspaces: FetchedResults<Workspace>

    @FocusState private var isSearchFocused: Bool
    @EnvironmentObject var interaction: PaletteInteractionState
    @State private var hoveredIndex: Int?
    @AppStorage("selectedWorktreeId") private var currentWorktreeId: String?

    private struct SnapshotSyncKey: Hashable {
        let worktreeCount: Int
        let workspaceCount: Int
        let currentWorktreeId: String?
    }

    private var snapshotSyncKey: SnapshotSyncKey {
        SnapshotSyncKey(
            worktreeCount: allWorktrees.count,
            workspaceCount: allWorkspaces.count,
            currentWorktreeId: currentWorktreeId
        )
    }

    private func syncSnapshots() {
        viewModel.updateSnapshot(Array(allWorktrees), currentWorktreeId: currentWorktreeId)
        viewModel.updateWorkspaceSnapshot(Array(allWorkspaces))
    }

    var body: some View {
        LiquidGlassCard(
            shadowOpacity: 0,
            sheenOpacity: 0.28,
            scrimOpacity: 0.14
        ) {
            VStack(spacing: 0) {
                SpotlightSearchField(
                    placeholder: placeholderText(for: viewModel.scope),
                    text: $viewModel.searchQuery,
                    isFocused: $isSearchFocused,
                    onSubmit: {
                        if let action = viewModel.selectedNavigationAction() {
                            handleSelection(action)
                        }
                    },
                    onEscape: onClose,
                    trailing: {
                        Button(action: onClose) {
                            KeyCap(text: "esc")
                        }
                        .buttonStyle(.plain)
                        .help("Close")
                    }
                )
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 10)

                scopeChips
                    .padding(.horizontal, 18)
                    .padding(.bottom, 12)

                Divider().opacity(0.25)

                if activeResultsEmpty {
                    emptyResultsView
                } else {
                    resultsList
                }

                footer
            }
        }
        .frame(width: 760, height: 520)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isSearchFocused = true
            }
        }
        .task(id: snapshotSyncKey) {
            syncSnapshots()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .NSManagedObjectContextObjectsDidChange,
                object: viewContext
            )
        ) { _ in
            syncSnapshots()
        }
        .background {
            Group {
                Button("") {
                    interaction.didUseKeyboard()
                    viewModel.moveSelectionDown()
                }
                .keyboardShortcut(.downArrow, modifiers: [])

                Button("") {
                    interaction.didUseKeyboard()
                    viewModel.moveSelectionUp()
                }
                .keyboardShortcut(.upArrow, modifiers: [])

                Button("") {
                    interaction.didUseKeyboard()
                    if let action = viewModel.selectedNavigationAction() {
                        handleSelection(action)
                    }
                }
                .keyboardShortcut(.return, modifiers: [])

                Button("") { onClose() }
                    .keyboardShortcut(.escape, modifiers: [])

                Button("") {
                    interaction.didUseKeyboard()
                    viewModel.setScope(.all)
                }
                .keyboardShortcut("1", modifiers: .command)

                Button("") {
                    interaction.didUseKeyboard()
                    viewModel.setScope(.currentProject)
                }
                .keyboardShortcut("2", modifiers: .command)

                Button("") {
                    interaction.didUseKeyboard()
                    viewModel.setScope(.workspace)
                }
                .keyboardShortcut("3", modifiers: .command)

                Button("") {
                    interaction.didUseKeyboard()
                    viewModel.setScope(.tabs)
                }
                .keyboardShortcut("4", modifiers: .command)
            }
            .hidden()
        }
    }

    private var resultsList: some View {
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

    private func resultRow(
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

    private func itemColor(for item: CommandPaletteItem, isSelected: Bool) -> Color {
        if isSelected {
            return .primary
        }
        if item.badgeText == "cross-project" {
            return .red
        }
        return .secondary
    }

    private func action(for item: CommandPaletteItem) -> CommandPaletteNavigationAction? {
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

    private func globalIndexFor(sectionOffset: Int, itemOffset: Int) -> Int {
        let prefixCount = viewModel.sections
            .prefix(sectionOffset)
            .reduce(0) { partial, section in
                partial + section.items.count
            }
        return prefixCount + itemOffset
    }

    private var activeResultsEmpty: Bool {
        viewModel.sections.allSatisfy { $0.items.isEmpty }
    }

    private func handleSelection(_ action: CommandPaletteNavigationAction) {
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
