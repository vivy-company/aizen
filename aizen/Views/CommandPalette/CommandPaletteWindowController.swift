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
    @EnvironmentObject private var interaction: PaletteInteractionState
    @State private var hoveredIndex: Int?
    @AppStorage("selectedWorktreeId") private var currentWorktreeId: String?

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
            viewModel.updateSnapshot(Array(allWorktrees), currentWorktreeId: currentWorktreeId)
            viewModel.updateWorkspaceSnapshot(Array(allWorkspaces))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isSearchFocused = true
            }
        }
        .onChange(of: allWorktrees.count) { _, _ in
            viewModel.updateSnapshot(Array(allWorktrees), currentWorktreeId: currentWorktreeId)
        }
        .onChange(of: allWorkspaces.count) { _, _ in
            viewModel.updateWorkspaceSnapshot(Array(allWorkspaces))
        }
        .onChange(of: currentWorktreeId) { _, _ in
            viewModel.updateSnapshot(Array(allWorktrees), currentWorktreeId: currentWorktreeId)
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .NSManagedObjectContextObjectsDidChange,
                object: viewContext
            )
        ) { _ in
            viewModel.updateSnapshot(Array(allWorktrees), currentWorktreeId: currentWorktreeId)
            viewModel.updateWorkspaceSnapshot(Array(allWorkspaces))
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

    private func placeholderText(for scope: CommandPaletteScope) -> LocalizedStringKey {
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

    private var scopeChips: some View {
        HStack(spacing: 8) {
            scopeChip(.all, shortcut: "⌘1")
            scopeChip(.currentProject, shortcut: "⌘2")
            scopeChip(.workspace, shortcut: "⌘3")
            scopeChip(.tabs, shortcut: "⌘4")
            Spacer(minLength: 0)
        }
    }

    private func scopeChip(_ scope: CommandPaletteScope, shortcut: String) -> some View {
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
            .onChange(of: viewModel.selectedIndex) { _, newIndex in
                proxy.scrollTo(newIndex, anchor: .center)
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
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

    @ViewBuilder
    private func paletteBadge(text: String) -> some View {
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

    private var emptyResultsView: some View {
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

    private func emptyStateText(for scope: CommandPaletteScope) -> String {
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

    private var footer: some View {
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
