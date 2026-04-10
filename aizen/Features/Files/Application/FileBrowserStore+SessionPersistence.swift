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
                    // Selection is restored after selected file hydration completes.
                }
            }

            if let openPathsArray = existingSession.value(forKey: "openFilesPaths") as? [String] {
                restoreOpenFiles(openPathsArray, selectedPath: existingSession.selectedFilePath)
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

    func restoreOpenFiles(_ paths: [String], selectedPath: String?) {
        sessionRestoreTask?.cancel()
        editorRuntimesByFileId.values.forEach { $0.clearGitDiff() }
        editorRuntimesByFileId.removeAll()

        openFiles = paths.map { path in
            OpenFileInfo(
                name: URL(fileURLWithPath: path).lastPathComponent,
                path: path,
                content: ""
            )
        }

        if let selectedPath,
           let selectedFile = openFiles.first(where: { $0.path == selectedPath }) {
            selectedFileId = selectedFile.id
        } else {
            selectedFileId = openFiles.last?.id
        }

        sessionRestoreTask = Task { @MainActor [weak self] in
            guard let self else { return }

            if let selectedPath {
                await self.hydrateRestoredFile(path: selectedPath, selectAfterHydration: true)
            }

            for path in paths where path != selectedPath {
                guard !Task.isCancelled else { return }
                await self.hydrateRestoredFile(path: path)
            }

            self.saveSession()
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
