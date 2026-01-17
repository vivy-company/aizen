//
//  SplitTerminalView.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import SwiftUI
import os

// MARK: - Split Terminal View

struct SplitTerminalView: View {
    @ObservedObject var worktree: Worktree
    @ObservedObject var session: TerminalSession
    let sessionManager: TerminalSessionManager
    let isSelected: Bool

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("terminalThemeName") private var terminalThemeName = "Aizen Dark"
    @AppStorage("terminalThemeNameLight") private var terminalThemeNameLight = "Aizen Light"
    @AppStorage("terminalUsePerAppearanceTheme") private var usePerAppearanceTheme = false

    private var effectiveThemeName: String {
        guard usePerAppearanceTheme else { return terminalThemeName }
        return colorScheme == .dark ? terminalThemeName : terminalThemeNameLight
    }

    @State private var layout: SplitNode
    @State private var focusedPaneId: String
    @State private var layoutVersion: Int = 0  // Increment when layout changes to force refresh
    @State private var paneTitles: [String: String] = [:]
    @State private var layoutSaveWorkItem: DispatchWorkItem?
    @State private var focusSaveWorkItem: DispatchWorkItem?
    @State private var contextSaveWorkItem: DispatchWorkItem?
    @State private var showCloseConfirmation = false
    @State private var pendingCloseAction: CloseAction = .pane
    @State private var keyMonitor: Any?
    @State private var focusedPaneVoiceRecording = false
    @State private var voiceAction: (paneId: String, action: VoiceAction)?
    @AppStorage("terminalSessionPersistence") private var sessionPersistence = false

    private enum CloseAction {
        case pane
        case tab
    }

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
            // Persist layout changes without re-triggering the whole task chain
            .onChange(of: layout) { _ in
                guard isSelected else { return }
                scheduleLayoutSave()
            }
            // Persist focused pane changes separately
            .onChange(of: focusedPaneId) { _ in
                guard isSelected else { return }
                scheduleFocusSave()
                applyTitleForFocusedPane()
            }
            // Initial persistence to store default layout/pane (only for selected session)
            .onAppear {
                if isSelected {
                    persistLayout()
                    persistFocus()
                    applyTitleForFocusedPane()
                }
                if keyMonitor == nil {
                    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                        handleVoiceShortcut(event)
                    }
                }
            }
            // Trigger focus when tab becomes selected (views are kept alive via opacity)
            .onChange(of: isSelected) { newValue in
                if newValue {
                    // Force focus update by toggling focusedPaneId
                    let currentFocus = focusedPaneId
                    focusedPaneId = ""
                    DispatchQueue.main.async {
                        focusedPaneId = currentFocus
                    }
                }
            }
            // Only set split actions for the currently selected/visible session
            .focusedSceneValue(\.terminalSplitActions, isSelected ? TerminalSplitActions(
                splitHorizontal: splitHorizontal,
                splitVertical: splitVertical,
                closePane: closePane
            ) : nil)
            .onDisappear {
                layoutSaveWorkItem?.cancel()
                focusSaveWorkItem?.cancel()
                contextSaveWorkItem?.cancel()
                if let monitor = keyMonitor {
                    NSEvent.removeMonitor(monitor)
                    keyMonitor = nil
                }
            }
            .alert(
                String(localized: "terminal.close.confirmTitle", defaultValue: "Close Terminal?"),
                isPresented: $showCloseConfirmation
            ) {
                Button(String(localized: "terminal.close.cancel", defaultValue: "Cancel"), role: .cancel) {}
                Button(String(localized: "terminal.close.confirm", defaultValue: "Close"), role: .destructive) {
                    executeCloseAction()
                }
            } message: {
                Text(String(localized: "terminal.close.confirmMessage", defaultValue: "A process is still running in this terminal. Are you sure you want to close it?"))
            }
    }

    private func renderNode(_ node: SplitNode) -> AnyView {
        switch node {
        case .leaf(let paneId):
            let voiceActionBinding = Binding<VoiceAction?>(
                get: { voiceAction?.paneId == paneId ? voiceAction?.action : nil },
                set: { _ in voiceAction = nil }
            )
            return AnyView(
                TerminalPaneView(
                    worktree: worktree,
                    session: session,
                    paneId: paneId,
                    isFocused: focusedPaneId == paneId,
                    sessionManager: sessionManager,
                    voiceAction: voiceActionBinding,
                    onFocus: {
                        focusedPaneId = paneId
                        applyTitleForFocusedPane()
                    },
                    onProcessExit: { handleProcessExit(for: paneId) },
                    onTitleChange: { title in handleTitleChange(for: paneId, title: title) },
                    onVoiceRecordingChanged: { isRecording in
                        if focusedPaneId == paneId {
                            focusedPaneVoiceRecording = isRecording
                        }
                    }
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
                    dividerColor: Color(nsColor: GhosttyThemeParser.loadDividerColor(named: effectiveThemeName)),
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

        let paneIds = layout.allPaneIds()
        let paneCount = paneIds.count

        // Ignore exit callbacks for panes that are already closed
        guard paneIds.contains(paneId) else { return }

        if paneCount == 1 {
            // Only one pane - delete the entire terminal session
            // Use a small delay to allow SwiftUI to process the deletion gracefully
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak session] in
                guard let session = session,
                      !session.isDeleted,
                      let context = session.managedObjectContext else { return }
                context.delete(session)
                do {
                    try context.save()
                } catch {
                    Logger.terminal.error("Failed to delete terminal session: \(error.localizedDescription)")
                }
            }
        } else {
            // Multiple panes - just close this one
            if let newLayout = layout.removingPane(paneId) {
                if focusedPaneId == paneId, let nextPane = newLayout.allPaneIds().first {
                    focusedPaneId = nextPane
                }
                layout = newLayout
                layoutVersion += 1
            }
        }
    }

    private func closePane() {
        let paneCount = layout.allPaneIds().count

        if paneCount == 1 {
            // Single pane - close the entire tab
            if let sessionId = session.id,
               sessionManager.paneHasRunningProcess(for: sessionId, paneId: focusedPaneId) {
                pendingCloseAction = .tab
                showCloseConfirmation = true
            } else {
                closeTab()
            }
        } else {
            // Multiple panes - close just this pane
            if let sessionId = session.id,
               sessionManager.paneHasRunningProcess(for: sessionId, paneId: focusedPaneId) {
                pendingCloseAction = .pane
                showCloseConfirmation = true
            } else {
                executeClosePaneOnly()
            }
        }
    }

    private func executeCloseAction() {
        switch pendingCloseAction {
        case .pane:
            executeClosePaneOnly()
        case .tab:
            closeTab()
        }
    }

    private func executeClosePaneOnly() {
        let paneIdToClose = focusedPaneId

        guard let newLayout = layout.removingPane(paneIdToClose) else {
            closeTab()
            return
        }

        // Shift focus to a surviving pane before removing the view
        if let nextPane = newLayout.allPaneIds().first {
            focusedPaneId = nextPane
        }

        layout = newLayout.equalized()
        layoutVersion += 1

        // Remove terminal after the layout update so AppKit can resign responders safely
        DispatchQueue.main.async {
            if let sessionId = session.id {
                sessionManager.removeTerminal(for: sessionId, paneId: paneIdToClose)
            }

            if sessionPersistence {
                Task {
                    await TmuxSessionManager.shared.killSession(paneId: paneIdToClose)
                }
            }
        }
    }

    private func closeTab() {
        let allPaneIds = layout.allPaneIds()

        // Remove all terminals for this session
        if let sessionId = session.id {
            for paneId in allPaneIds {
                sessionManager.removeTerminal(for: sessionId, paneId: paneId)
            }
        }

        // Kill all tmux sessions if persistence is enabled
        if sessionPersistence {
            Task {
                for paneId in allPaneIds {
                    await TmuxSessionManager.shared.killSession(paneId: paneId)
                }
            }
        }

        // Delete the terminal session
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak session] in
            guard let session = session,
                  !session.isDeleted,
                  let context = session.managedObjectContext else { return }
            context.delete(session)
            do {
                try context.save()
            } catch {
                Logger.terminal.error("Failed to delete terminal session: \(error.localizedDescription)")
            }
        }
    }

    private func saveContext() {
        scheduleDebouncedSave()
    }

    private func scheduleDebouncedSave() {
        contextSaveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak session] in
            guard let session = session,
                  !session.isDeleted,
                  let context = session.managedObjectContext else { return }
            do {
                try context.save()
            } catch {
                Logger.terminal.error("Failed to save split layout: \(error.localizedDescription)")
            }
        }
        contextSaveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
    }

    // MARK: - Persistence Helpers

    private func scheduleLayoutSave() {
        layoutSaveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [layout] in
            persistLayout(layout)
        }
        layoutSaveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)
    }

    private func scheduleFocusSave() {
        focusSaveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [focusedPaneId] in
            persistFocus(focusedPaneId)
        }
        focusSaveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: workItem)
    }

    private func persistLayout(_ layoutToSave: SplitNode? = nil) {
        guard !session.isDeleted else { return }
        let node = layoutToSave ?? layout
        if let json = SplitLayoutHelper.encode(node) {
            session.splitLayout = json
            saveContext()
        }
    }

    private func persistFocus(_ paneId: String? = nil) {
        guard !session.isDeleted else { return }
        let id = paneId ?? focusedPaneId
        session.focusedPaneId = id
        saveContext()
    }

    // MARK: - Title Handling

    private func handleTitleChange(for paneId: String, title: String) {
        paneTitles[paneId] = title
        if paneId == focusedPaneId {
            session.title = title
            saveContext()
        }
    }

    private func applyTitleForFocusedPane() {
        guard !session.isDeleted else { return }
        if let title = paneTitles[focusedPaneId] {
            session.title = title
            saveContext()
        }
    }

    // MARK: - Voice Shortcut Handling

    private func handleVoiceShortcut(_ event: NSEvent) -> NSEvent? {
        guard isSelected else { return event }

        let keyCodeEscape: UInt16 = 53
        let keyCodeReturn: UInt16 = 36

        // Handle Enter/Escape when voice recording is active
        if focusedPaneVoiceRecording {
            if event.keyCode == keyCodeEscape {
                voiceAction = (focusedPaneId, .cancel)
                return nil
            }
            if event.keyCode == keyCodeReturn {
                voiceAction = (focusedPaneId, .accept)
                return nil
            }
        }

        // Handle ⌘⇧M to toggle voice recording
        guard event.modifierFlags.contains(.command),
              event.modifierFlags.contains(.shift),
              event.charactersIgnoringModifiers?.lowercased() == "m" else {
            return event
        }
        voiceAction = (focusedPaneId, .toggle)
        return nil
    }
}
