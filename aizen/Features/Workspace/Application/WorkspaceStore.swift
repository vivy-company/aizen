//
//  WorkspaceStore.swift
//  aizen
//
//  Owns the layout tabs and split tree of a worktree's working area.
//  The tree is the source of truth: pane runtime (terminal surfaces, chat
//  agents) is created when panes enter it and torn down when they leave.
//

import AppKit
import Combine
import CoreData
import Foundation
import os

@MainActor
final class WorkspaceStore: ObservableObject {
    let worktree: Worktree
    let viewContext: NSManagedObjectContext
    let splitActions = TerminalSplitActions()
    let logger = Logger(subsystem: "com.aizen.app", category: "workspace")

    @Published private(set) var layouts: [WorktreeLayout] = []
    @Published private(set) var activeLayoutId: UUID?
    @Published private(set) var tree: WorkspaceSplitNode = .leaf(WorkspacePane(kind: .empty))
    @Published var focusedPaneId: String = ""
    @Published var voiceAction: (paneId: String, action: VoiceAction)?
    @Published var focusRequestVersion = 0
    @Published var pendingCloseConfirmationPaneId: String?

    var isActive = false
    var paneVoiceRecordingStates: [String: Bool] = [:]
    var closingPaneIds: Set<String> = []
    private var treeSaveTask: Task<Void, Never>?
    private var keyMonitor: Any?

    init(worktree: Worktree, viewContext: NSManagedObjectContext) {
        self.worktree = worktree
        self.viewContext = viewContext

        splitActions.configure(
            splitRight: { [weak self] in self?.splitFocusedPane(direction: .horizontal, insertion: .after) },
            splitLeft: { [weak self] in self?.splitFocusedPane(direction: .horizontal, insertion: .before) },
            splitDown: { [weak self] in self?.splitFocusedPane(direction: .vertical, insertion: .after) },
            splitUp: { [weak self] in self?.splitFocusedPane(direction: .vertical, insertion: .before) },
            closePane: { [weak self] in self?.requestCloseFocusedPane() }
        )

        loadLayouts()
    }

    var activeLayout: WorktreeLayout? {
        layouts.first { $0.id == activeLayoutId }
    }

    var focusedPane: WorkspacePane? {
        tree.pane(withId: focusedPaneId) ?? tree.allPanes().first
    }

    // MARK: - Loading & layout tabs

    func loadLayouts() {
        migrateLegacyStateIfNeeded()
        reloadLayoutList()

        let storedActiveId = worktree.selectedTab.flatMap(UUID.init(uuidString:))
        let target = layouts.first { $0.id == storedActiveId } ?? layouts.first
        if let target {
            activateLayout(target)
        }
    }

    func reloadLayoutList() {
        let all = (worktree.layouts as? Set<WorktreeLayout>) ?? []
        layouts = all.sorted {
            if $0.order != $1.order { return $0.order < $1.order }
            return ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast)
        }
    }

    func selectLayout(_ layout: WorktreeLayout) {
        guard layout.id != activeLayoutId else { return }
        persistTreeNow()
        activateLayout(layout)
    }

    func selectLayout(at index: Int) {
        guard layouts.indices.contains(index) else { return }
        selectLayout(layouts[index])
    }

    func cycleLayout(step: Int) {
        guard !layouts.isEmpty else { return }
        let currentIndex = layouts.firstIndex { $0.id == activeLayoutId } ?? 0
        let nextIndex = (currentIndex + step + layouts.count) % layouts.count
        selectLayout(layouts[nextIndex])
    }

    private func activateLayout(_ layout: WorktreeLayout) {
        activeLayoutId = layout.id
        if let json = layout.treeJSON, let decoded = WorkspaceLayoutCodec.decode(json) {
            tree = decoded
        } else {
            tree = .leaf(WorkspacePane(kind: .empty))
        }
        let paneIds = tree.allPaneIds()
        if let stored = layout.focusedPaneId, paneIds.contains(stored) {
            focusedPaneId = stored
        } else {
            focusedPaneId = paneIds.first ?? ""
        }
        worktree.selectedTab = layout.id?.uuidString
        saveContext()
        syncTerminalSurfaceFocus()
        focusRequestVersion += 1
    }

    @discardableResult
    func addLayout(name: String? = nil, tree initialTree: WorkspaceSplitNode? = nil, activate: Bool = true) -> WorktreeLayout {
        let layout = WorktreeLayout(context: viewContext)
        layout.id = UUID()
        layout.name = name
        layout.createdAt = Date()
        layout.order = nextLayoutOrder()
        layout.treeJSON = WorkspaceLayoutCodec.encode(initialTree ?? .leaf(WorkspacePane(kind: .empty)))
        layout.worktree = worktree
        saveContext()
        reloadLayoutList()
        if activate {
            persistTreeNow()
            activateLayout(layout)
        }
        return layout
    }

    func closeLayout(_ layout: WorktreeLayout) {
        let layoutTree = layout.treeJSON.flatMap(WorkspaceLayoutCodec.decode)
        let wasActive = layout.id == activeLayoutId

        viewContext.delete(layout)
        saveContext()
        reloadLayoutList()

        // Teardown after removal so "referenced elsewhere" checks see the final state.
        if let layoutTree {
            for pane in layoutTree.allPanes() {
                teardownPaneRuntime(pane)
            }
        }

        if layouts.isEmpty {
            addLayout()
        } else if wasActive, let firstLayout = layouts.first {
            activateLayout(firstLayout)
        }
    }

    func layoutTree(for layout: WorktreeLayout) -> WorkspaceSplitNode {
        layout.id == activeLayoutId
            ? tree
            : (layout.treeJSON.flatMap(WorkspaceLayoutCodec.decode) ?? .leaf(WorkspacePane(kind: .empty)))
    }

    func primaryKind(for layout: WorktreeLayout) -> PaneKind {
        layoutTree(for: layout).allPanes().map(\.kind).first { $0 != .empty } ?? .empty
    }

    func displayName(for layout: WorktreeLayout) -> String {
        if let name = layout.name, !name.isEmpty { return name }
        let layoutTree = layoutTree(for: layout)
        let kinds = layoutTree.allPanes().map(\.kind).filter { $0 != .empty }
        guard let primary = kinds.first else {
            return String(localized: "workspace.layout.new", defaultValue: "New Tab")
        }
        let count = layoutTree.leafCount()
        let base = PaneKindPresentation.title(for: primary)
        return count > 1 ? "\(base) +\(count - 1)" : base
    }

    private func nextLayoutOrder() -> Int64 {
        guard let highestOrder = layouts.map(\.order).max() else { return 0 }
        guard highestOrder < Int64.max else {
            for (index, layout) in layouts.enumerated() {
                layout.order = Int64(index)
            }
            return Int64(layouts.count)
        }
        return highestOrder + 1
    }

    // MARK: - Focus

    func focusPane(_ paneId: String) {
        guard tree.allPaneIds().contains(paneId) else { return }
        activateSplitActions()
        if focusedPaneId != paneId {
            focusedPaneId = paneId
            activeLayout?.focusedPaneId = paneId
            saveContext()
        }
        syncTerminalSurfaceFocus()
    }

    enum FocusDirection {
        case left, right, up, down
    }

    /// Moves focus to the spatially nearest pane in the given direction.
    /// Uses normalized geometry, so it matches what's on screen regardless of
    /// window size.
    func moveFocus(_ direction: FocusDirection) {
        let geometry = WorkspaceTreeGeometry(tree: tree, size: CGSize(width: 1000, height: 1000))
        guard geometry.panes.count > 1,
              let current = geometry.panes.first(where: { $0.pane.id == focusedPaneId }) ?? geometry.panes.first else {
            return
        }

        let origin = CGPoint(x: current.frame.midX, y: current.frame.midY)
        var best: (paneId: String, score: CGFloat)?

        for paneFrame in geometry.panes where paneFrame.pane.id != current.pane.id {
            let center = CGPoint(x: paneFrame.frame.midX, y: paneFrame.frame.midY)
            let dx = center.x - origin.x
            let dy = center.y - origin.y

            let forward: CGFloat
            let lateral: CGFloat
            switch direction {
            case .left: forward = -dx; lateral = abs(dy)
            case .right: forward = dx; lateral = abs(dy)
            case .up: forward = -dy; lateral = abs(dx)
            case .down: forward = dy; lateral = abs(dx)
            }

            guard forward > 0.5 else { continue }
            let score = forward + lateral * 2
            if best == nil || score < best!.score {
                best = (paneFrame.pane.id, score)
            }
        }

        if let best {
            focusPane(best.paneId)
            focusRequestVersion += 1
        }
    }

    func syncTerminalSurfaceFocus() {
        guard isActive else { return }
        for pane in tree.allPanes() where pane.kind == .terminal {
            guard let sessionId = pane.sessionId,
                  let surface = TerminalRuntimeStore.shared.getTerminal(for: sessionId, paneId: pane.id) else { continue }
            surface.setGhosttyFocused(pane.id == focusedPaneId)
        }
    }

    func clearTerminalSurfaceFocus() {
        for pane in tree.allPanes() where pane.kind == .terminal {
            guard let sessionId = pane.sessionId,
                  let surface = TerminalRuntimeStore.shared.getTerminal(for: sessionId, paneId: pane.id) else { continue }
            surface.setGhosttyFocused(false)
        }
    }

    // MARK: - Activation

    func handleAppear() {
        isActive = true
        activateSplitActions()
        ensureKeyMonitor()
        syncTerminalSurfaceFocus()
    }

    func handleDisappear() {
        isActive = false
        persistTreeNow()
        deactivateSplitActions()
        clearTerminalSurfaceFocus()
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    func activateSplitActions() {
        TerminalSplitActionRouter.shared.activate(splitActions)
    }

    func deactivateSplitActions() {
        TerminalSplitActionRouter.shared.clear(splitActions)
    }

    // MARK: - Tree persistence

    func setTree(_ newTree: WorkspaceSplitNode) {
        tree = newTree
        scheduleTreeSave()
    }

    func scheduleTreeSave() {
        treeSaveTask?.cancel()
        let current = tree
        treeSaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.persistTree(current)
        }
    }

    func persistTreeNow() {
        treeSaveTask?.cancel()
        persistTree(tree)
    }

    private func persistTree(_ node: WorkspaceSplitNode) {
        guard let layout = activeLayout, !layout.isDeleted else { return }
        if let json = WorkspaceLayoutCodec.encode(node), layout.treeJSON != json {
            layout.treeJSON = json
            layout.focusedPaneId = focusedPaneId
            saveContext()
        }
    }

    func saveContext() {
        guard viewContext.hasChanges else { return }
        do {
            try viewContext.save()
        } catch {
            logger.error("Workspace save failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Voice shortcut routing

    func ensureKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleVoiceShortcut(event) ?? event
        }
    }

    func handleVoiceRecordingChanged(for paneId: String, isRecording: Bool) {
        paneVoiceRecordingStates[paneId] = isRecording
    }

    private func handleVoiceShortcut(_ event: NSEvent) -> NSEvent? {
        guard isActive else { return event }
        guard let pane = focusedPane, pane.kind == .terminal else { return event }

        if paneVoiceRecordingStates[pane.id] == true {
            if event.keyCode == 53 {
                voiceAction = (pane.id, .cancel)
                return nil
            }
            if event.keyCode == 36 {
                voiceAction = (pane.id, .accept)
                return nil
            }
        }

        guard event.modifierFlags.contains(.command),
              event.modifierFlags.contains(.shift),
              event.charactersIgnoringModifiers?.lowercased() == "m" else {
            return event
        }

        voiceAction = (pane.id, .toggle)
        return nil
    }
}

// MARK: - Pane kind presentation

enum PaneKindPresentation {
    static func title(for kind: PaneKind) -> String {
        switch kind {
        case .terminal: return String(localized: "workspace.pane.terminal", defaultValue: "Terminal")
        case .chat: return String(localized: "workspace.pane.chat", defaultValue: "Chat")
        case .files: return String(localized: "workspace.pane.files", defaultValue: "Files")
        case .browser: return String(localized: "workspace.pane.browser", defaultValue: "Browser")
        case .gitDiff: return String(localized: "workspace.pane.gitDiff", defaultValue: "Git Diff")
        case .empty: return String(localized: "workspace.pane.empty", defaultValue: "Empty")
        }
    }

    static func icon(for kind: PaneKind) -> String {
        switch kind {
        case .terminal: return "terminal"
        case .chat: return "message"
        case .files: return "folder"
        case .browser: return "globe"
        case .gitDiff: return "plus.forwardslash.minus"
        case .empty: return "square.dashed"
        }
    }

    /// Kinds offered in the empty-state picker and replace menu.
    static let selectableKinds: [PaneKind] = [.terminal, .chat, .files, .browser, .gitDiff]
}
