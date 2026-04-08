//
//  TerminalSplitController+SessionSeed.swift
//  aizen
//

import CoreData
import Foundation
import os

extension TerminalSplitController {
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
}
