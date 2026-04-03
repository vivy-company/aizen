//
//  TerminalSplitController+Persistence.swift
//  aizen
//
//  Layout and focus persistence helpers
//

import Foundation
import CoreData
import os

extension TerminalSplitController {
    func saveContext() {
        scheduleDebouncedSave()
    }

    func scheduleDebouncedSave() {
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

    func seedSessionLayoutIfNeeded() {
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

    func scheduleLayoutSave() {
        layoutSaveTask?.cancel()
        let currentLayout = layout
        layoutSaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.persistLayout(currentLayout)
        }
    }

    func scheduleFocusSave() {
        focusSaveTask?.cancel()
        let currentFocusedPaneId = focusedPaneId
        focusSaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            self?.persistFocus(currentFocusedPaneId)
        }
    }

    func persistLayout(_ layoutToSave: SplitNode? = nil) {
        guard !isClosingSession, !session.isDeleted else { return }
        let node = layoutToSave ?? layout
        if let json = SplitLayoutHelper.encode(node), session.splitLayout != json {
            session.splitLayout = json
            saveContext()
        }
    }

    func persistFocus(_ paneId: String? = nil) {
        guard !isClosingSession, !session.isDeleted else { return }
        let id = paneId ?? focusedPaneId
        guard !id.isEmpty else { return }
        guard session.focusedPaneId != id else { return }
        session.focusedPaneId = id
        saveContext()
    }
}
