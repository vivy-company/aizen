//
//  SplitTerminalView.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import SwiftUI
import os.log

// MARK: - Split Terminal View

struct SplitTerminalView: View {
    @ObservedObject var worktree: Worktree
    @ObservedObject var session: TerminalSession
    let sessionManager: TerminalSessionManager
    let isSelected: Bool

    @State private var layout: SplitNode
    @State private var focusedPaneId: String
    @State private var layoutVersion: Int = 0  // Increment when layout changes to force refresh
    @State private var layoutSaveWorkItem: DispatchWorkItem?
    @State private var focusSaveWorkItem: DispatchWorkItem?
    private let logger = Logger.terminal

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
                scheduleLayoutSave()
            }
            // Persist focused pane changes separately
            .onChange(of: focusedPaneId) { _ in
                scheduleFocusSave()
            }
            // Initial persistence to store default layout/pane
            .onAppear {
                persistLayout()
                persistFocus()
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
            }
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
                    dividerColor: Color(nsColor: .black),
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
                    Logger.terminal.error("Failed to delete terminal session: \(error.localizedDescription)")
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

    private func saveContext() {
        guard let context = session.managedObjectContext else { return }
        do {
            try context.save()
        } catch {
            logger.error("Failed to save split layout: \(error.localizedDescription)")
        }
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
        let node = layoutToSave ?? layout
        if let json = SplitLayoutHelper.encode(node) {
            session.splitLayout = json
            saveContext()
        }
    }

    private func persistFocus(_ paneId: String? = nil) {
        let id = paneId ?? focusedPaneId
        session.focusedPaneId = id
        saveContext()
    }
}
