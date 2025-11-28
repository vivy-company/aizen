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

    convenience init(
        managedObjectContext: NSManagedObjectContext,
        onNavigate: @escaping (UUID, UUID, UUID) -> Void
    ) {
        let panel = CommandPalettePanel(
            managedObjectContext: managedObjectContext,
            onNavigate: onNavigate
        )
        self.init(window: panel)
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
    }

    override func showWindow(_ sender: Any?) {
        guard let panel = window as? CommandPalettePanel else { return }
        positionPanel(panel)
        panel.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async {
            panel.makeKey()
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
    init(
        managedObjectContext: NSManagedObjectContext,
        onNavigate: @escaping (UUID, UUID, UUID) -> Void
    ) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 70),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        self.isOpaque = false
        self.backgroundColor = NSColor.clear
        self.hasShadow = false
        self.level = .floating
        self.isMovableByWindowBackground = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.becomesKeyOnlyIfNeeded = true
        self.isFloatingPanel = true
        self.appearance = NSAppearance(named: .darkAqua)

        let hostingView = NSHostingView(
            rootView: CommandPaletteContent(
                onNavigate: onNavigate,
                onClose: { [weak self] in
                    self?.close()
                }
            )
            .environment(\.managedObjectContext, managedObjectContext)
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
    @FocusState private var isSearchFocused: Bool

    private var sortedWorktrees: [Worktree] {
        let filtered = allWorktrees.filter { worktree in
            guard !worktree.isDeleted else { return false }
            guard worktree.repository?.workspace != nil else { return false }
            if searchQuery.isEmpty { return true }
            let branch = worktree.branch ?? ""
            let repoName = worktree.repository?.name ?? ""
            let workspaceName = worktree.repository?.workspace?.name ?? ""
            return branch.localizedCaseInsensitiveContains(searchQuery) ||
                   repoName.localizedCaseInsensitiveContains(searchQuery) ||
                   workspaceName.localizedCaseInsensitiveContains(searchQuery)
        }

        return filtered.sorted { a, b in
            let aActive = hasActiveSessions(a)
            let bActive = hasActiveSessions(b)
            if aActive != bActive { return aActive }
            return (a.lastAccessed ?? .distantPast) > (b.lastAccessed ?? .distantPast)
        }
    }

    private func hasActiveSessions(_ worktree: Worktree) -> Bool {
        let chats = (worktree.chatSessions as? Set<ChatSession>)?.count ?? 0
        let terminals = (worktree.terminalSessions as? Set<TerminalSession>)?.count ?? 0
        return chats > 0 || terminals > 0
    }

    var body: some View {
        VStack(spacing: 12) {
            searchBar
            if !sortedWorktrees.isEmpty {
                resultsCard
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }
        }
        .frame(width: 700)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color.clear)
        .compositingGroup()
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isSearchFocused = true
            }
        }
        .onChange(of: sortedWorktrees.count) { _ in
            updateWindowHeight()
            // Reset selection if out of bounds
            if selectedIndex >= sortedWorktrees.count {
                selectedIndex = max(0, sortedWorktrees.count - 1)
            }
        }
        .onChange(of: searchQuery) { _ in
            selectedIndex = 0
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

    private var searchBar: some View {
        HStack(spacing: 14) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 16, weight: .medium))

            TextField("Switch to worktree...", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .focused($isSearchFocused)

            if !searchQuery.isEmpty {
                Button(action: { searchQuery = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
            }

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .foregroundColor(.secondary)
                    .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(.plain)
            .help("Close (Esc)")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(Capsule().fill(.ultraThinMaterial))
        .shadow(color: .black.opacity(0.3), radius: 30, x: 0, y: 15)
    }

    private var resultsCard: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(sortedWorktrees.enumerated()), id: \.element.objectID) { index, worktree in
                        worktreeRow(worktree: worktree, index: index, isSelected: index == selectedIndex)
                            .id(index)
                    }
                }
                .padding(.vertical, 8)
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .frame(maxHeight: 450)
            .onChange(of: selectedIndex) { newIndex in
                proxy.scrollTo(newIndex, anchor: .top)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.regularMaterial)
        )
        .shadow(color: .black.opacity(0.25), radius: 25, x: 0, y: 15)
        .compositingGroup()
    }

    private func worktreeRow(worktree: Worktree, index: Int, isSelected: Bool) -> some View {
        HStack(spacing: 14) {
            Image(systemName: worktree.isPrimary ? "arrow.triangle.branch" : "arrow.triangle.2.circlepath")
                .foregroundStyle(isSelected ? .white : .secondary)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(worktree.branch ?? "Unknown")
                        .font(.system(size: 14))
                        .foregroundColor(isSelected ? .white : .primary)

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
                            .foregroundColor(isSelected ? .white.opacity(0.7) : .secondary)
                    }
                    if let repoName = worktree.repository?.name {
                        Text("›")
                            .font(.system(size: 12))
                            .foregroundColor(isSelected ? .white.opacity(0.5) : .secondary.opacity(0.6))
                        Text(repoName)
                            .font(.system(size: 12))
                            .foregroundColor(isSelected ? .white.opacity(0.7) : .secondary)
                    }
                }
            }

            Spacer()

            sessionIndicators(for: worktree, isSelected: isSelected)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selectWorktree(worktree)
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
            .foregroundColor(isSelected ? .white.opacity(0.7) : .secondary)
        }
    }

    private func moveSelectionDown() {
        if selectedIndex < sortedWorktrees.count - 1 {
            selectedIndex += 1
        }
    }

    private func moveSelectionUp() {
        if selectedIndex > 0 {
            selectedIndex -= 1
        }
    }

    private func selectCurrent() {
        guard selectedIndex < sortedWorktrees.count else { return }
        selectWorktree(sortedWorktrees[selectedIndex])
    }

    private func selectWorktree(_ worktree: Worktree) {
        guard let worktreeId = worktree.id,
              let repoId = worktree.repository?.id,
              let workspaceId = worktree.repository?.workspace?.id else {
            return
        }
        onNavigate(workspaceId, repoId, worktreeId)
        onClose()
    }

    private func updateWindowHeight() {
        guard let window = NSApp.keyWindow else { return }

        let baseHeight: CGFloat = 70
        let resultsHeight: CGFloat = sortedWorktrees.isEmpty ? 0 : min(CGFloat(sortedWorktrees.count) * 50 + 16, 450)
        let newHeight = baseHeight + resultsHeight + (sortedWorktrees.isEmpty ? 0 : 12)

        var frame = window.frame
        let oldHeight = frame.height
        frame.size.height = newHeight
        frame.origin.y += (oldHeight - newHeight)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(frame, display: true)
        }
    }
}
