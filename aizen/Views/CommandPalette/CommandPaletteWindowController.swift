//
//  CommandPaletteWindowController.swift
//  aizen
//
//  Command palette for fast navigation between worktrees
//

import AppKit
import CoreData
import SwiftUI

class CommandPaletteWindowController: NSWindowController {
    private var appDeactivationObserver: NSObjectProtocol?
    private var eventMonitor: Any?

    convenience init(
        managedObjectContext: NSManagedObjectContext,
        onNavigate: @escaping (UUID, UUID, UUID) -> Void
    ) {
        let panel = CommandPalettePanel(
            managedObjectContext: managedObjectContext,
            onNavigate: onNavigate
        )
        self.init(window: panel)
        panel.requestClose = { [weak self] in
            self?.closeWindow()
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
    }

    private func cleanup() {
        if let observer = appDeactivationObserver {
            NotificationCenter.default.removeObserver(observer)
            appDeactivationObserver = nil
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
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .mouseMoved]
        ) { [weak self, weak panel] event in
            guard let self, let panel else { return event }
            guard panel.isVisible else { return event }

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

    init(
        managedObjectContext: NSManagedObjectContext,
        onNavigate: @escaping (UUID, UUID, UUID) -> Void
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
                }
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
}

struct CommandPaletteContent: View {
    let onNavigate: (UUID, UUID, UUID) -> Void
    let onClose: () -> Void

    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Worktree.lastAccessed, ascending: false)],
        animation: .default
    )
    private var allWorktrees: FetchedResults<Worktree>

    @State private var searchQuery = ""
    @State private var selectedIndex = 0
    @State private var displayedWorktrees: [Worktree] = []
    @FocusState private var isSearchFocused: Bool
    @EnvironmentObject private var interaction: PaletteInteractionState
    @State private var hoveredIndex: Int?

    private func refreshDisplayedWorktrees() {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        let base = allWorktrees.filter { worktree in
            guard !worktree.isDeleted else { return false }
            guard worktree.repository?.workspace != nil else { return false }
            return true
        }

        if query.isEmpty {
            let sorted = base.sorted { a, b in
                let aLast = a.lastAccessed ?? .distantPast
                let bLast = b.lastAccessed ?? .distantPast
                if aLast != bLast { return aLast > bLast }

                let aActive = hasActiveSessions(a)
                let bActive = hasActiveSessions(b)
                if aActive != bActive { return aActive }
                return (a.branch ?? "") < (b.branch ?? "")
            }

            displayedWorktrees = Array(sorted.prefix(50))
        } else {
            let scored = base.compactMap { worktree -> (worktree: Worktree, score: Int)? in
                guard let score = matchScore(for: worktree, query: query) else { return nil }
                return (worktree, score)
            }

            let sorted = scored.sorted { a, b in
                if a.score != b.score { return a.score > b.score }

                let aLast = a.worktree.lastAccessed ?? .distantPast
                let bLast = b.worktree.lastAccessed ?? .distantPast
                if aLast != bLast { return aLast > bLast }

                let aActive = hasActiveSessions(a.worktree)
                let bActive = hasActiveSessions(b.worktree)
                if aActive != bActive { return aActive }
                return (a.worktree.branch ?? "") < (b.worktree.branch ?? "")
            }

            displayedWorktrees = Array(sorted.prefix(50)).map { $0.worktree }
        }

        if selectedIndex >= displayedWorktrees.count {
            selectedIndex = max(0, displayedWorktrees.count - 1)
        }
    }

    private func searchFields(for worktree: Worktree) -> [String] {
        var fields: [String] = []

        if let branch = worktree.branch, !branch.isEmpty {
            fields.append(branch)
        }
        if let repoName = worktree.repository?.name, !repoName.isEmpty {
            fields.append(repoName)
        }
        if let workspaceName = worktree.repository?.workspace?.name, !workspaceName.isEmpty {
            fields.append(workspaceName)
        }
        if let path = worktree.path, !path.isEmpty {
            fields.append(path)
            let name = URL(fileURLWithPath: path).lastPathComponent
            if !name.isEmpty && name != path {
                fields.append(name)
            }
        }
        if let note = worktree.note, !note.isEmpty {
            fields.append(note)
        }

        return fields
    }

    private func matchScore(for worktree: Worktree, query: String) -> Int? {
        let normalizedQuery = query.lowercased()
        let tokens = normalizedQuery.split(whereSeparator: { $0.isWhitespace }).map(String.init)

        let fields = searchFields(for: worktree).map { $0.lowercased() }
        if fields.isEmpty { return nil }

        let combined = fields.joined(separator: " ")
        guard tokens.allSatisfy({ combined.contains($0) }) else { return nil }

        var score = 0
        for field in fields {
            if field == normalizedQuery {
                score += 400
            } else if field.hasPrefix(normalizedQuery) {
                score += 300
            } else if field.contains(normalizedQuery) {
                score += 200
            }

            for token in tokens where token != normalizedQuery {
                if field.hasPrefix(token) {
                    score += 40
                } else if field.contains(token) {
                    score += 20
                }
            }
        }

        return score
    }

    private func hasActiveSessions(_ worktree: Worktree) -> Bool {
        let chats = (worktree.chatSessions as? Set<ChatSession>)?.count ?? 0
        let terminals = (worktree.terminalSessions as? Set<TerminalSession>)?.count ?? 0
        return chats > 0 || terminals > 0
    }

    var body: some View {
        LiquidGlassCard(
            shadowOpacity: 0,
            tint: .black.opacity(0.30),
            sheenOpacity: 0.28,
            scrimOpacity: 0.14
        ) {
            VStack(spacing: 0) {
                SpotlightSearchField(
                    placeholder: "Switch to worktree…",
                    text: $searchQuery,
                    isFocused: $isSearchFocused,
                    onSubmit: { selectCurrent() },
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
                .padding(.bottom, 14)

                Divider().opacity(0.25)

                if displayedWorktrees.isEmpty {
                    emptyResultsView
                } else {
                    resultsList
                }

                footer
            }
        }
        .frame(width: 760, height: 520)
        .onAppear {
            refreshDisplayedWorktrees()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isSearchFocused = true
            }
        }
        .onChange(of: allWorktrees.count) { _ in
            refreshDisplayedWorktrees()
        }
        .onChange(of: searchQuery) { _ in
            selectedIndex = 0
            refreshDisplayedWorktrees()
        }
        .background {
            Group {
                Button("") { moveSelectionDown() }
                    .keyboardShortcut(.downArrow, modifiers: [])
                Button("") { moveSelectionUp() }
                    .keyboardShortcut(.upArrow, modifiers: [])
                Button("") { selectCurrent() }
                    .keyboardShortcut(.return, modifiers: [])
                Button("") { onClose() }
                    .keyboardShortcut(.escape, modifiers: [])
            }
            .hidden()
        }
    }

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(displayedWorktrees.enumerated()), id: \.element.objectID) { index, worktree in
                        worktreeRow(
                            worktree: worktree,
                            index: index,
                            isSelected: index == selectedIndex,
                            isHovered: hoveredIndex == index
                        )
                            .id(index)
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 10)
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .scrollIndicators(.hidden)
            .frame(maxHeight: 380)
            .onChange(of: selectedIndex) { newIndex in
                proxy.scrollTo(newIndex, anchor: .center)
            }
        }
    }

    private func worktreeRow(worktree: Worktree, index: Int, isSelected: Bool, isHovered: Bool) -> some View {
        HStack(spacing: 14) {
            Image(systemName: worktree.isPrimary ? "arrow.triangle.branch" : "arrow.triangle.2.circlepath")
                .foregroundStyle(isSelected ? .primary : .secondary)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(worktree.branch ?? "Unknown")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)

                    if worktree.isPrimary {
                        Text("main")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.blue, in: Capsule())
                    }
                }

                HStack(spacing: 4) {
                    if let workspaceName = worktree.repository?.workspace?.name {
                        Text(workspaceName)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    if let repoName = worktree.repository?.name {
                        Text("›")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary.opacity(0.7))
                        Text(repoName)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            sessionIndicators(for: worktree, isSelected: isSelected)
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
            selectWorktree(worktree)
        }
        .onHover { hovering in
            guard interaction.allowHoverSelection else { return }
            hoveredIndex = hovering ? index : nil
        }
    }

    @ViewBuilder
    private func sessionIndicators(for worktree: Worktree, isSelected: Bool) -> some View {
        let chatCount = (worktree.chatSessions as? Set<ChatSession>)?.count ?? 0
        let terminalCount = (worktree.terminalSessions as? Set<TerminalSession>)?.count ?? 0

        if chatCount > 0 || terminalCount > 0 {
            HStack(spacing: 6) {
                if chatCount > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "message")
                            .font(.system(size: 10))
                        if chatCount > 1 {
                            Text("\(chatCount)")
                                .font(.system(size: 10))
                        }
                    }
                }
                if terminalCount > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "terminal")
                            .font(.system(size: 10))
                        if terminalCount > 1 {
                            Text("\(terminalCount)")
                                .font(.system(size: 10))
                        }
                    }
                }
            }
            .foregroundStyle(.secondary)
        }
    }

    private func moveSelectionDown() {
        interaction.didUseKeyboard()
        if selectedIndex < displayedWorktrees.count - 1 {
            selectedIndex += 1
        }
    }

    private func moveSelectionUp() {
        interaction.didUseKeyboard()
        if selectedIndex > 0 {
            selectedIndex -= 1
        }
    }

    private func selectCurrent() {
        interaction.didUseKeyboard()
        guard selectedIndex < displayedWorktrees.count else { return }
        selectWorktree(displayedWorktrees[selectedIndex])
    }

    private func selectWorktree(_ worktree: Worktree) {
        guard let worktreeId = worktree.id,
              let repoId = worktree.repository?.id,
              let workspaceId = worktree.repository?.workspace?.id else {
            return
        }
        worktree.lastAccessed = Date()
        try? viewContext.save()
        onNavigate(workspaceId, repoId, worktreeId)
        onClose()
    }

    private var emptyResultsView: some View {
        VStack(spacing: 10) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.secondary.opacity(0.5))
            Text("No worktrees found")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 90)
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
                KeyCap(text: "↩")
                Text("Open")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.clear)
    }
}
