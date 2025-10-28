//
//  TerminalTabView.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import SwiftUI
import AppKit
import Combine

class TerminalSessionManager {
    static let shared = TerminalSessionManager()

    private var terminals: [String: GhosttyTerminalView] = [:]

    private init() {}

    func getTerminal(for sessionId: UUID, paneId: String) -> GhosttyTerminalView? {
        let key = "\(sessionId.uuidString)-\(paneId)"
        return terminals[key]
    }

    func setTerminal(_ terminal: GhosttyTerminalView, for sessionId: UUID, paneId: String) {
        let key = "\(sessionId.uuidString)-\(paneId)"
        terminals[key] = terminal
    }

    func removeTerminal(for sessionId: UUID, paneId: String) {
        let key = "\(sessionId.uuidString)-\(paneId)"
        terminals.removeValue(forKey: key)
    }

    func removeAllTerminals(for sessionId: UUID) {
        let prefix = sessionId.uuidString
        terminals = terminals.filter { !$0.key.hasPrefix(prefix) }
    }
}

struct TerminalTabView: View {
    @ObservedObject var worktree: Worktree
    @Binding var selectedSessionId: UUID?
    @ObservedObject var repositoryManager: RepositoryManager

    private let sessionManager = TerminalSessionManager.shared

    var sessions: [TerminalSession] {
        let sessions = (worktree.terminalSessions as? Set<TerminalSession>) ?? []
        return sessions.sorted { ($0.createdAt ?? Date()) < ($1.createdAt ?? Date()) }
    }

    var body: some View {
        if sessions.isEmpty {
            terminalEmptyState
        } else {
            ZStack {
                ForEach(sessions) { session in
                    if selectedSessionId == session.id {
                        SplitTerminalView(
                            worktree: worktree,
                            session: session,
                            sessionManager: sessionManager,
                            isSelected: true
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.identity)
                    }
                }
            }
            .onAppear {
                if selectedSessionId == nil {
                    selectedSessionId = sessions.first?.id
                }
            }
        }
    }

    private var terminalEmptyState: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.secondary)

                VStack(spacing: 8) {
                    Text("No Terminal Sessions")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("Open a terminal in this worktree")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                createNewSession()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                    Text("New Terminal")
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.blue, in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func createNewSession() {
        guard let context = worktree.managedObjectContext else { return }

        let session = TerminalSession(context: context)
        session.id = UUID()
        session.title = "Terminal \(sessions.count + 1)"
        session.createdAt = Date()
        session.worktree = worktree

        do {
            try context.save()
            selectedSessionId = session.id
        } catch {
            print("Failed to create terminal session: \(error)")
        }
    }
}

// MARK: - Split Terminal View

struct SplitTerminalView: View {
    @ObservedObject var worktree: Worktree
    @ObservedObject var session: TerminalSession
    let sessionManager: TerminalSessionManager
    let isSelected: Bool

    @State private var layout: SplitNode
    @State private var focusedPaneId: String
    @State private var layoutVersion: Int = 0  // Increment when layout changes to force refresh

    init(worktree: Worktree, session: TerminalSession, sessionManager: TerminalSessionManager, isSelected: Bool = false) {
        self.worktree = worktree
        self.session = session
        self.sessionManager = sessionManager
        self.isSelected = isSelected

        // Load layout from session or create default
        if let layoutJSON = session.splitLayout,
           let decoded = SplitLayoutHelper.decode(layoutJSON) {
            _layout = State(initialValue: decoded)
            _focusedPaneId = State(initialValue: session.focusedPaneId ?? decoded.allPaneIds().first ?? "")
        } else {
            let defaultLayout = SplitLayoutHelper.createDefault()
            _layout = State(initialValue: defaultLayout)
            _focusedPaneId = State(initialValue: defaultLayout.allPaneIds().first ?? "")
        }
    }

    var body: some View {
        renderNode(layout)
            .padding(.top, 1)
            .onAppear {
                saveLayout()
            }
            .onChange(of: layout) { _, _ in
                saveLayout()
            }
            .onChange(of: focusedPaneId) { _, newValue in
                session.focusedPaneId = newValue
                saveContext()
            }
            .onChange(of: isSelected) { oldValue, newValue in
                if newValue && !oldValue {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        let currentPane = focusedPaneId
                        focusedPaneId = ""
                        focusedPaneId = currentPane
                    }
                }
            }
            // Only set split actions for the currently selected/visible session
            .focusedSceneValue(\.terminalSplitActions, isSelected ? TerminalSplitActions(
                splitHorizontal: splitHorizontal,
                splitVertical: splitVertical,
                closePane: closePane
            ) : nil)
    }

    private func renderNode(_ node: SplitNode) -> AnyView {
        switch node {
        case .leaf(let paneId):
            return AnyView(
                TerminalPaneView(
                    worktree: worktree,
                    session: session,
                    paneId: paneId,
                    isFocused: focusedPaneId == paneId,
                    sessionManager: sessionManager,
                    onFocus: { focusedPaneId = paneId },
                    onProcessExit: { handleProcessExit(for: paneId) }
                )
                .id("\(paneId)-\(layoutVersion)")  // Force refresh when layout changes
            )

        case .split(let split):
            // Capture the current split node
            let currentSplitNode = node

            // Create computed binding (Ghostty pattern)
            let ratioBinding = Binding<CGFloat>(
                get: { CGFloat(split.ratio) },
                set: { newRatio in
                    // Update this specific split's ratio
                    let updatedSplit = currentSplitNode.withUpdatedRatio(Double(newRatio))
                    layout = layout.replacingNode(currentSplitNode, with: updatedSplit)
                }
            )

            return AnyView(
                SplitView(
                    split.direction == .horizontal ? .horizontal : .vertical,
                    ratioBinding,
                    dividerColor: Color(nsColor: .separatorColor),
                    left: { renderNode(split.left) },
                    right: { renderNode(split.right) }
                )
            )
        }
    }

    private func splitHorizontal() {
        let newPaneId = UUID().uuidString
        let newSplit = SplitNode.split(SplitNode.Split(
            direction: .horizontal,
            ratio: 0.5,
            left: .leaf(paneId: focusedPaneId),
            right: .leaf(paneId: newPaneId)
        ))
        layout = layout.replacingPane(focusedPaneId, with: newSplit).equalized()
        layoutVersion += 1
        focusedPaneId = newPaneId
    }

    private func splitVertical() {
        let newPaneId = UUID().uuidString
        let newSplit = SplitNode.split(SplitNode.Split(
            direction: .vertical,
            ratio: 0.5,
            left: .leaf(paneId: focusedPaneId),
            right: .leaf(paneId: newPaneId)
        ))
        layout = layout.replacingPane(focusedPaneId, with: newSplit).equalized()
        layoutVersion += 1
        focusedPaneId = newPaneId
    }

    private func handleProcessExit(for paneId: String) {
        // Remove terminal from manager
        if let sessionId = session.id {
            sessionManager.removeTerminal(for: sessionId, paneId: paneId)
        }

        let paneCount = layout.allPaneIds().count

        if paneCount == 1 {
            // Only one pane - delete the entire terminal session
            // Use a small delay to allow SwiftUI to process the deletion gracefully
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak session] in
                guard let session = session,
                      let context = session.managedObjectContext else { return }
                context.delete(session)
                do {
                    try context.save()
                } catch {
                    print("Failed to delete terminal session: \(error)")
                }
            }
        } else {
            // Multiple panes - just close this one
            if let newLayout = layout.removingPane(paneId) {
                layout = newLayout
                // If we closed the focused pane, focus another one
                if focusedPaneId == paneId {
                    if let firstPane = layout.allPaneIds().first {
                        focusedPaneId = firstPane
                    }
                }
            }
        }
    }

    private func closePane() {
        guard layout.allPaneIds().count > 1 else { return }

        // Remove terminal from manager
        if let sessionId = session.id {
            sessionManager.removeTerminal(for: sessionId, paneId: focusedPaneId)
        }

        if let newLayout = layout.removingPane(focusedPaneId) {
            layout = newLayout.equalized()
            // Focus first available pane
            if let firstPane = layout.allPaneIds().first {
                focusedPaneId = firstPane
            }
        }
    }

    private func saveLayout() {
        if let json = SplitLayoutHelper.encode(layout) {
            session.splitLayout = json
            saveContext()
        }
    }

    private func saveContext() {
        guard let context = session.managedObjectContext else { return }
        do {
            try context.save()
        } catch {
            print("Failed to save split layout: \(error)")
        }
    }
}

// MARK: - Terminal Pane View

struct TerminalPaneView: View {
    @ObservedObject var worktree: Worktree
    @ObservedObject var session: TerminalSession
    let paneId: String
    let isFocused: Bool
    let sessionManager: TerminalSessionManager
    let onFocus: () -> Void
    let onProcessExit: () -> Void

    @State private var shouldFocus: Bool = false
    @State private var focusVersion: Int = 0  // Increment to force updateNSView
    @State private var terminalView: GhosttyTerminalView?  // Store reference to resign directly

    var body: some View {
        TerminalViewWrapper(
            worktree: worktree,
            session: session,
            paneId: paneId,
            sessionManager: sessionManager,
            onProcessExit: onProcessExit,
            shouldFocus: shouldFocus,  // Pass value directly, not binding
            isFocused: isFocused,      // Pass focused state to manage resignation
            focusVersion: focusVersion // Version counter to force updateNSView
        )
        .opacity(isFocused ? 1.0 : 0.6)
        .onTapGesture {
            onFocus()
        }
        .onChange(of: isFocused) { oldValue, newValue in
            if newValue && !oldValue {
                shouldFocus = true
                focusVersion += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    shouldFocus = false
                }
            } else if !newValue && oldValue {
                focusVersion += 1
            }
        }
        .onAppear {
            if isFocused {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    shouldFocus = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        shouldFocus = false
                    }
                }
            }
        }
    }
}

// MARK: - Terminal Split Actions (for keyboard shortcuts)

struct TerminalSplitActions {
    let splitHorizontal: () -> Void
    let splitVertical: () -> Void
    let closePane: () -> Void
}

private struct TerminalSplitActionsKey: FocusedValueKey {
    typealias Value = TerminalSplitActions
}

extension FocusedValues {
    var terminalSplitActions: TerminalSplitActions? {
        get { self[TerminalSplitActionsKey.self] }
        set { self[TerminalSplitActionsKey.self] = newValue }
    }
}


// MARK: - Terminal View Coordinator

class TerminalViewCoordinator {
    let session: TerminalSession
    let onProcessExit: () -> Void
    private var exitCheckTimer: Timer?

    init(session: TerminalSession, onProcessExit: @escaping () -> Void) {
        self.session = session
        self.onProcessExit = onProcessExit
    }

    func startMonitoring(terminal: GhosttyTerminalView) {
        // Poll for process exit every 500ms
        exitCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self, weak terminal] _ in
            guard let self = self, let terminal = terminal else { return }

            if terminal.processExited {
                self.exitCheckTimer?.invalidate()
                self.exitCheckTimer = nil
                self.onProcessExit()
            }
        }
    }

    func stopMonitoring() {
        exitCheckTimer?.invalidate()
        exitCheckTimer = nil
    }

    deinit {
        stopMonitoring()
    }
}

// MARK: - Terminal View Wrapper

struct TerminalViewWrapper: NSViewRepresentable {
    @ObservedObject var worktree: Worktree
    @ObservedObject var session: TerminalSession
    let paneId: String
    let sessionManager: TerminalSessionManager
    let onProcessExit: () -> Void
    let shouldFocus: Bool  // Pass value directly to trigger updateNSView
    let isFocused: Bool    // Track if this pane should have focus
    let focusVersion: Int  // Version counter - forces updateNSView when changed

    @EnvironmentObject var ghosttyApp: Ghostty.App

    func makeCoordinator() -> TerminalViewCoordinator {
        TerminalViewCoordinator(session: session, onProcessExit: onProcessExit)
    }

    func makeNSView(context: Context) -> NSView {
        // Guard against deleted session
        guard let sessionId = session.id else {
            return NSView(frame: .zero)
        }

        // Check if terminal already exists for this pane
        if let existingTerminal = sessionManager.getTerminal(for: sessionId, paneId: paneId) {
            context.coordinator.startMonitoring(terminal: existingTerminal)

            DispatchQueue.main.async {
                existingTerminal.needsLayout = true
                existingTerminal.layoutSubtreeIfNeeded()
            }

            return existingTerminal
        }

        // Ensure Ghostty app is ready
        guard let app = ghosttyApp.app else {
            return NSView(frame: .zero)
        }

        // Get worktree path
        guard let path = worktree.path else {
            return NSView(frame: .zero)
        }

        // Create new Ghostty terminal
        let terminalView = GhosttyTerminalView(
            frame: .zero,
            worktreePath: path,
            ghosttyApp: app,
            appWrapper: ghosttyApp
        )

        // Set process exit callback
        terminalView.onProcessExit = onProcessExit

        // Set title change callback to update session title
        let sessionToUpdate = session
        let worktreeToUpdate = worktree
        let moc = session.managedObjectContext
        terminalView.onTitleChange = { title in
            Task { @MainActor in
                sessionToUpdate.title = title

                // Notify observers explicitly
                sessionToUpdate.objectWillChange.send()
                worktreeToUpdate.objectWillChange.send()

                do {
                    try moc?.save()
                } catch {
                    print("Failed to save terminal title change: \(error)")
                }
            }
        }

        // Store terminal in manager for persistence
        sessionManager.setTerminal(terminalView, for: sessionId, paneId: paneId)

        // Start monitoring for process exit
        context.coordinator.startMonitoring(terminal: terminalView)

        return terminalView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if shouldFocus {
            guard let window = nsView.window else { return }
            window.makeFirstResponder(nsView)
        } else if !isFocused && nsView.window?.firstResponder == nsView {
            nsView.window?.makeFirstResponder(nil)
        }
    }
}

#Preview {
    TerminalTabView(
        worktree: Worktree(),
        selectedSessionId: .constant(nil),
        repositoryManager: RepositoryManager(viewContext: PersistenceController.preview.container.viewContext)
    )
}
