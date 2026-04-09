//
//  FileBrowserStore+Mutations.swift
//  aizen
//
//  File and folder mutation workflows
//

import Foundation

extension FileBrowserStore {
    func createNewFile(parentPath: String, name: String) async {
        let filePath = (parentPath as NSString).appendingPathComponent(name)

        do {
            try await fileService.createFile(at: filePath)
            ToastStore.shared.show("Created \(name)", type: .success)
            refreshTree()
            await openFile(path: filePath)
        } catch {
            ToastStore.shared.show(error.localizedDescription, type: .error)
        }
    }

    func createNewFolder(parentPath: String, name: String) async {
        let folderPath = (parentPath as NSString).appendingPathComponent(name)

        do {
            try await fileService.createDirectory(at: folderPath)
            ToastStore.shared.show("Created folder \(name)", type: .success)
            refreshTree()
            expandedPaths.insert(folderPath)
            saveSession()
        } catch {
            ToastStore.shared.show(error.localizedDescription, type: .error)
        }
    }

    func renameItem(oldPath: String, newName: String) async {
        let parentPath = (oldPath as NSString).deletingLastPathComponent
        let newPath = (parentPath as NSString).appendingPathComponent(newName)

        do {
            try await fileService.renameItem(from: oldPath, to: newPath)
            ToastStore.shared.show("Renamed to \(newName)", type: .success)

            if let index = openFiles.firstIndex(where: { $0.path == oldPath }) {
                let fileInfo = openFiles[index]
                openFiles[index] = OpenFileInfo(
                    id: fileInfo.id,
                    name: newName,
                    path: newPath,
                    content: fileInfo.content,
                    hasUnsavedChanges: fileInfo.hasUnsavedChanges
                )
            }

            if expandedPaths.contains(oldPath) {
                expandedPaths.remove(oldPath)
                expandedPaths.insert(newPath)
            }

            refreshTree()
            saveSession()
        } catch {
            ToastStore.shared.show(error.localizedDescription, type: .error)
        }
    }

    func deleteItem(path: String) async {
        let fileName = (path as NSString).lastPathComponent

        do {
            try await fileService.deleteItem(at: path)
            ToastStore.shared.show("Deleted \(fileName)", type: .success)

            if let openFile = openFiles.first(where: { $0.path == path }) {
                closeFile(id: openFile.id)
            }

            expandedPaths.remove(path)
            refreshTree()
            saveSession()
        } catch {
            ToastStore.shared.show(error.localizedDescription, type: .error)
        }
    }
}
