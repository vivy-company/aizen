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
