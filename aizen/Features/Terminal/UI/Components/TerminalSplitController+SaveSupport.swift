//
//  TerminalSplitController+SaveSupport.swift
//  aizen
//

import CoreData
import Foundation
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
}
