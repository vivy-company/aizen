//
//  TerminalSplitController.swift
//  aizen
//
//  Controller-owned split state aligned with Ghostty's terminal controller model.
//

import AppKit
import Combine
import SwiftUI
import os

@MainActor
final class TerminalSplitController: ObservableObject {
    enum CloseAction {
        case pane
        case tab
    }

    let worktree: Worktree
    let session: TerminalSession
    let sessionManager: TerminalSessionManager
    let splitActions = TerminalSplitActions()
    private let titleRegistry = TerminalTitleRegistry.shared

    @Published var layout: SplitNode {
        didSet {
            guard isSelected else { return }
            scheduleLayoutSave()
        }
    }

    @Published var focusedPaneId: String {
        didSet {
            guard isSelected else { return }
            guard !focusedPaneId.isEmpty else { return }
            focusedPaneVoiceRecording = paneVoiceRecordingStates[focusedPaneId] ?? false
            syncGhosttySurfaceFocus()
            scheduleFocusSave()
            applyTitleForFocusedPane()
        }
    }

    @Published var showCloseConfirmation = false
    @Published var voiceAction: (paneId: String, action: VoiceAction)?
    @Published var focusRequestVersion = 0

    private(set) var isSelected: Bool
    private var paneTitles: [String: String] = [:]
    private var layoutSaveTask: Task<Void, Never>?
    private var focusSaveTask: Task<Void, Never>?
    private var contextSaveTask: Task<Void, Never>?
    private var pendingCloseAction: CloseAction = .pane
    private var keyMonitor: Any?
    private var focusedPaneVoiceRecording = false
    private var paneVoiceRecordingStates: [String: Bool] = [:]
    private var closingPaneIds: Set<String> = []
    private var isClosingSession = false

    init(
        worktree: Worktree,
        session: TerminalSession,
        sessionManager: TerminalSessionManager,
        isSelected: Bool
    ) {
        self.worktree = worktree
        self.session = session
        self.sessionManager = sessionManager
        self.isSelected = isSelected

        if let layoutJSON = session.splitLayout,
           let decoded = SplitLayoutHelper.decode(layoutJSON) {
            self.layout = decoded
            self.focusedPaneId = session.focusedPaneId ?? decoded.allPaneIds().first ?? ""
        } else {
            let defaultPaneId = TerminalLayoutDefaults.paneId(
                sessionId: session.id,
                focusedPaneId: session.focusedPaneId
            )
            self.layout = SplitLayoutHelper.createDefault(paneId: defaultPaneId)
            self.focusedPaneId = defaultPaneId
        }

        splitActions.configure(
            splitRight: { [weak self] in self?.splitRight() },
            splitLeft: { [weak self] in self?.splitLeft() },
            splitDown: { [weak self] in self?.splitDown() },
            splitUp: { [weak self] in self?.splitUp() },
            closePane: { [weak self] in self?.closePane() }
        )
    }

    func handleAppear() {
        seedSessionLayoutIfNeeded()
        ensureKeyMonitor()

        guard isSelected else { return }
        activateSplitActions()
        syncGhosttySurfaceFocus()
        persistLayout()
        persistFocus()
        applyTitleForFocusedPane()
        focusRequestVersion += 1
    }

    func handleDisappear() {
        layoutSaveTask?.cancel()
        focusSaveTask?.cancel()
        contextSaveTask?.cancel()
        deactivateSplitActions()
        clearGhosttySurfaceFocus()

        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    func handleSelectionChange(_ selected: Bool) {
        isSelected = selected

        if selected {
            activateSplitActions()
            syncGhosttySurfaceFocus()
            persistLayout()
            persistFocus()
            applyTitleForFocusedPane()
            focusRequestVersion += 1
        } else {
            deactivateSplitActions()
            clearGhosttySurfaceFocus()
        }
    }

    func handlePaneFocus(_ paneId: String) {
        guard !isClosingSession else { return }
        guard layout.allPaneIds().contains(paneId) else { return }
        activateSplitActions()
        focusedPaneId = paneId
    }

    func handleTitleChange(for paneId: String, title: String) {
        paneTitles[paneId] = title
        if paneId == focusedPaneId,
           let sessionId = session.id {
            titleRegistry.setLiveTitle(title, for: sessionId)
        }
    }

    func handleVoiceRecordingChanged(for paneId: String, isRecording: Bool) {
        paneVoiceRecordingStates[paneId] = isRecording
        if focusedPaneId == paneId {
            focusedPaneVoiceRecording = isRecording
        }
    }

    func resizeSplit(_ node: SplitNode, to newRatio: CGFloat) {
        let updatedSplit = node.withUpdatedRatio(Double(newRatio))
        layout = layout.replacingNode(node, with: updatedSplit)
    }

    func equalize() {
        layout = layout.equalized()
    }

    func splitHorizontal() {
        splitRight()
    }

    func splitVertical() {
        splitDown()
    }

    func splitRight() {
        let sourcePaneId = activePaneId()
        let newPaneId = UUID().uuidString
        let newSplit = SplitNode.split(SplitNode.Split(
            direction: .horizontal,
            ratio: 0.5,
            left: .leaf(paneId: sourcePaneId),
            right: .leaf(paneId: newPaneId)
        ))
        layout = layout.replacingPane(sourcePaneId, with: newSplit)
        focusedPaneId = newPaneId
        focusRequestVersion += 1
        activateSplitActions()
    }

    func splitLeft() {
        let sourcePaneId = activePaneId()
        let newPaneId = UUID().uuidString
        let newSplit = SplitNode.split(SplitNode.Split(
            direction: .horizontal,
            ratio: 0.5,
            left: .leaf(paneId: newPaneId),
            right: .leaf(paneId: sourcePaneId)
        ))
        layout = layout.replacingPane(sourcePaneId, with: newSplit)
        focusedPaneId = newPaneId
        focusRequestVersion += 1
        activateSplitActions()
    }

    func splitDown() {
        let sourcePaneId = activePaneId()
        let newPaneId = UUID().uuidString
        let newSplit = SplitNode.split(SplitNode.Split(
            direction: .vertical,
            ratio: 0.5,
            left: .leaf(paneId: sourcePaneId),
            right: .leaf(paneId: newPaneId)
        ))
        layout = layout.replacingPane(sourcePaneId, with: newSplit)
        focusedPaneId = newPaneId
        focusRequestVersion += 1
        activateSplitActions()
    }

    func splitUp() {
        let sourcePaneId = activePaneId()
        let newPaneId = UUID().uuidString
        let newSplit = SplitNode.split(SplitNode.Split(
            direction: .vertical,
            ratio: 0.5,
            left: .leaf(paneId: newPaneId),
            right: .leaf(paneId: sourcePaneId)
        ))
        layout = layout.replacingPane(sourcePaneId, with: newSplit)
        focusedPaneId = newPaneId
        focusRequestVersion += 1
        activateSplitActions()
    }

    func handleProcessExit(for paneId: String) {
        guard !isClosingSession else { return }
        guard !closingPaneIds.contains(paneId) else { return }

        paneVoiceRecordingStates.removeValue(forKey: paneId)

        if let sessionId = session.id {
            sessionManager.removeTerminal(for: sessionId, paneId: paneId)
        }

        let paneIds = layout.allPaneIds()
        guard paneIds.contains(paneId) else { return }
        closingPaneIds.insert(paneId)
        let shouldTransferFocus = activePaneId() == paneId

        if paneIds.count == 1 {
            closeTab()
            return
        }

        if let newLayout = layout.removingPane(paneId) {
            if shouldTransferFocus {
                transferFocus(from: paneId, to: newLayout.allPaneIds().first)
            } else if focusedPaneId == paneId, let fallbackPaneId = newLayout.allPaneIds().first {
                focusedPaneId = fallbackPaneId
            }
            layout = newLayout
        }
    }

    func closePane() {
        let paneCount = layout.allPaneIds().count

        if paneCount == 1 {
            if let sessionId = session.id,
               sessionManager.paneHasRunningProcess(for: sessionId, paneId: focusedPaneId) {
                pendingCloseAction = .tab
                showCloseConfirmation = true
            } else {
                closeTab()
            }
        } else {
            if let sessionId = session.id,
               sessionManager.paneHasRunningProcess(for: sessionId, paneId: activePaneId()) {
                pendingCloseAction = .pane
                showCloseConfirmation = true
            } else {
                executeClosePaneOnly()
            }
        }
    }

    func executeCloseAction() {
        showCloseConfirmation = false

        switch pendingCloseAction {
        case .pane:
            executeClosePaneOnly()
        case .tab:
            closeTab()
        }
    }

    private func executeClosePaneOnly() {
        guard !isClosingSession else { return }

        let paneIdToClose = activePaneId()
        guard layout.allPaneIds().contains(paneIdToClose) else { return }
        guard !closingPaneIds.contains(paneIdToClose) else { return }

        closingPaneIds.insert(paneIdToClose)
        paneVoiceRecordingStates.removeValue(forKey: paneIdToClose)

        guard let newLayout = layout.removingPane(paneIdToClose) else {
            closeTab()
            return
        }

        transferFocus(from: paneIdToClose, to: newLayout.allPaneIds().first)
        layout = newLayout

        DispatchQueue.main.async { [session, sessionManager] in
            if let sessionId = session.id {
                sessionManager.removeTerminal(for: sessionId, paneId: paneIdToClose)
            }

            if Self.sessionPersistenceEnabled {
                Task {
                    await TmuxSessionManager.shared.killSession(paneId: paneIdToClose)
                }
            }
        }
    }

    private func closeTab() {
        guard !isClosingSession else { return }
        isClosingSession = true
        showCloseConfirmation = false
        layoutSaveTask?.cancel()
        focusSaveTask?.cancel()
        contextSaveTask?.cancel()
        deactivateSplitActions()

        let allPaneIds = layout.allPaneIds()
        closingPaneIds.formUnion(allPaneIds)
        for paneId in allPaneIds {
            paneVoiceRecordingStates.removeValue(forKey: paneId)
        }
        focusedPaneVoiceRecording = false

        if let sessionId = session.id {
            for paneId in allPaneIds {
                sessionManager.removeTerminal(for: sessionId, paneId: paneId)
            }
        }

        if Self.sessionPersistenceEnabled {
            Task {
                for paneId in allPaneIds {
                    await TmuxSessionManager.shared.killSession(paneId: paneId)
                }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak session] in
            guard let session,
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

    private func activateSplitActions() {
        TerminalSplitActionRouter.shared.activate(splitActions)
    }

    private func deactivateSplitActions() {
        TerminalSplitActionRouter.shared.clear(splitActions)
    }

    private func ensureKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleVoiceShortcut(event) ?? event
        }
    }

    private func saveContext() {
        scheduleDebouncedSave()
    }

    private func scheduleDebouncedSave() {
        contextSaveTask?.cancel()
        contextSaveTask = Task { @MainActor [weak session] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled,
                  let session,
                  !session.isDeleted,
                  let context = session.managedObjectContext else { return }
            do {
                try context.save()
            } catch {
                Logger.terminal.error("Failed to save split layout: \(error.localizedDescription)")
            }
        }
    }

    private func seedSessionLayoutIfNeeded() {
        guard !session.isDeleted else { return }
        guard let context = session.managedObjectContext else { return }

        let resolvedPaneId = TerminalLayoutDefaults.paneId(
            sessionId: session.id,
            focusedPaneId: focusedPaneId
        )

        var didChange = false
        if session.focusedPaneId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
            session.focusedPaneId = resolvedPaneId
            didChange = true
        }

        if session.splitLayout?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true,
           let json = SplitLayoutHelper.encode(TerminalLayoutDefaults.defaultLayout(paneId: resolvedPaneId)) {
            session.splitLayout = json
            didChange = true
        }

        guard didChange else { return }
        do {
            try context.save()
        } catch {
            Logger.terminal.error("Failed to seed terminal session layout: \(error.localizedDescription)")
        }
    }

    private func scheduleLayoutSave() {
        layoutSaveTask?.cancel()
        let currentLayout = layout
        layoutSaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.persistLayout(currentLayout)
        }
    }

    private func scheduleFocusSave() {
        focusSaveTask?.cancel()
        let currentFocusedPaneId = focusedPaneId
        focusSaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            self?.persistFocus(currentFocusedPaneId)
        }
    }

    private func persistLayout(_ layoutToSave: SplitNode? = nil) {
        guard !isClosingSession, !session.isDeleted else { return }
        let node = layoutToSave ?? layout
        if let json = SplitLayoutHelper.encode(node), session.splitLayout != json {
            session.splitLayout = json
            saveContext()
        }
    }

    private func persistFocus(_ paneId: String? = nil) {
        guard !isClosingSession, !session.isDeleted else { return }
        let id = paneId ?? focusedPaneId
        guard !id.isEmpty else { return }
        guard session.focusedPaneId != id else { return }
        session.focusedPaneId = id
        saveContext()
    }

    private func applyTitleForFocusedPane() {
        guard !isClosingSession, !session.isDeleted else { return }
        guard let sessionId = session.id else { return }

        if let title = paneTitles[focusedPaneId] {
            titleRegistry.setLiveTitle(title, for: sessionId)
        } else {
            titleRegistry.clearLiveTitle(for: sessionId)
        }
    }

    private func handleVoiceShortcut(_ event: NSEvent) -> NSEvent? {
        guard isSelected else { return event }
        let targetPaneId = activePaneId()

        if focusedPaneVoiceRecording {
            if event.keyCode == 53 {
                voiceAction = (targetPaneId, .cancel)
                return nil
            }
            if event.keyCode == 36 {
                voiceAction = (targetPaneId, .accept)
                return nil
            }
        }

        guard event.modifierFlags.contains(.command),
              event.modifierFlags.contains(.shift),
              event.charactersIgnoringModifiers?.lowercased() == "m" else {
            return event
        }

        voiceAction = (targetPaneId, .toggle)
        return nil
    }

    private func activePaneId() -> String {
        let paneIds = layout.allPaneIds()
        if let sessionId = session.id,
           let responderPaneId = sessionManager.focusedPaneId(for: sessionId),
           paneIds.contains(responderPaneId) {
            if focusedPaneId != responderPaneId {
                focusedPaneId = responderPaneId
            }
            return responderPaneId
        }

        if paneIds.contains(focusedPaneId) {
            return focusedPaneId
        }

        if let fallbackPaneId = paneIds.first {
            focusedPaneId = fallbackPaneId
            return fallbackPaneId
        }

        return focusedPaneId
    }

    private func syncGhosttySurfaceFocus() {
        guard isSelected, let sessionId = session.id else { return }

        let paneIds = Set(layout.allPaneIds())
        for paneId in paneIds {
            guard let surface = sessionManager.getTerminal(for: sessionId, paneId: paneId) else { continue }
            surface.setGhosttyFocused(paneId == focusedPaneId)
        }
    }

    private func clearGhosttySurfaceFocus() {
        guard let sessionId = session.id else { return }

        let paneIds = Set(layout.allPaneIds())
        for paneId in paneIds {
            guard let surface = sessionManager.getTerminal(for: sessionId, paneId: paneId) else { continue }
            surface.setGhosttyFocused(false)
        }
    }

    private func transferFocus(from sourcePaneId: String, to targetPaneId: String?) {
        guard let targetPaneId else { return }

        if focusedPaneId != targetPaneId {
            focusedPaneId = targetPaneId
        }

        if let sessionId = session.id,
           let targetSurface = sessionManager.getTerminal(for: sessionId, paneId: targetPaneId) {
            let sourceSurface = sessionManager.getTerminal(for: sessionId, paneId: sourcePaneId)
            Ghostty.moveFocus(to: targetSurface, from: sourceSurface)
        }

        focusRequestVersion += 1
    }

    private static var sessionPersistenceEnabled: Bool {
        UserDefaults.standard.bool(forKey: "terminalSessionPersistence")
    }
}
