//
//  FileBrowserStore+SessionPersistence.swift
//  aizen
//
//  Session restore and save support for the file browser
//

import Foundation
import CoreData
import os

extension FileBrowserStore {
    func loadSession() {
        if let existingSession = worktree.fileBrowserSession {
            session = existingSession

            if let currentPath = existingSession.currentPath {
                self.currentPath = currentPath
            }

            if let expandedPathsArray = existingSession.value(forKey: "expandedPaths") as? [String] {
                expandedPaths = Set(expandedPathsArray)
            }

            if let selectedPath = existingSession.selectedFilePath {
                if let openPathsArray = existingSession.value(forKey: "openFilesPaths") as? [String],
                   openPathsArray.contains(selectedPath) {
                    // Selection is restored after reopened files finish loading.
                }
            }

            if let openPathsArray = existingSession.value(forKey: "openFilesPaths") as? [String] {
                Task {
                    for path in openPathsArray {
                        await openFile(path: path, persistSession: false)
                    }

                    if let selectedPath = existingSession.selectedFilePath,
                       let selectedFile = openFiles.first(where: { $0.path == selectedPath }) {
                        selectedFileId = selectedFile.id
                    }

                    saveSession()
                }
            }
        } else {
            let newSession = FileBrowserSession(context: viewContext)
            newSession.id = UUID()
            newSession.currentPath = currentPath
            newSession.setValue([], forKey: "expandedPaths")
            newSession.setValue([], forKey: "openFilesPaths")
            newSession.worktree = worktree
            session = newSession

            saveSession(immediately: true)
        }
    }

    func saveSession(immediately: Bool = false) {
        sessionSaveTask?.cancel()

        if immediately {
            persistSessionNow()
            return
        }

        sessionSaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: FileBrowserStore.sessionSaveDelay)
            guard let self, !Task.isCancelled else { return }
            self.persistSessionNow()
        }
    }

    private func persistSessionNow() {
        guard let session = session else { return }

        session.currentPath = currentPath
        session.setValue(Array(expandedPaths), forKey: "expandedPaths")
        session.setValue(openFiles.map { $0.path }, forKey: "openFilesPaths")
        session.selectedFilePath = openFiles.first(where: { $0.id == selectedFileId })?.path

        do {
            if viewContext.hasChanges {
                try viewContext.save()
            }
        } catch {
            logger.error("Error saving FileBrowserSession: \(error)")
        }
    }
}
