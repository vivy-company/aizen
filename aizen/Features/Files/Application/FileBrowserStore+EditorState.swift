//
//  FileBrowserStore+EditorState.swift
//  aizen
//
//  Open-file editor state and persistence
//

import Foundation

extension FileBrowserStore {
    func openFile(path: String, persistSession: Bool = true) async {
        let fileURL = URL(fileURLWithPath: path)

        if isBrowsableDirectory(fileURL) {
            currentPath = path
            if persistSession {
                saveSession()
            }
            return
        }

        if let existing = openFiles.first(where: { $0.path == path }) {
            selectedFileId = existing.id
            return
        }

        let maxOpenFileBytes = 5 * 1024 * 1024
        if let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize,
           size > maxOpenFileBytes {
            let mb = Double(size) / 1024.0 / 1024.0
            ToastStore.shared.show(String(format: "File too large to open (%.1f MB). Open in external editor.", mb), type: .info)
            return
        }

        guard let content = try? await fileService.readFile(path: path) else {
            ToastStore.shared.show("Unable to open file (not UTF-8 text).", type: .info)
            return
        }

        let fileInfo = OpenFileInfo(
            name: fileURL.lastPathComponent,
            path: path,
            content: content
        )

        openFiles.append(fileInfo)
        selectedFileId = fileInfo.id
        if persistSession {
            saveSession()
        }
    }

    func closeFile(id: UUID) {
        openFiles.removeAll { $0.id == id }
        if selectedFileId == id {
            selectedFileId = openFiles.last?.id
        }
        saveSession()
    }

    func saveFile(id: UUID) throws {
        guard let index = openFiles.firstIndex(where: { $0.id == id }) else {
            return
        }

        let file = openFiles[index]
        try file.content.write(toFile: file.path, atomically: true, encoding: .utf8)
        openFiles[index].hasUnsavedChanges = false
    }

    func updateFileContent(id: UUID, content: String) {
        guard let index = openFiles.firstIndex(where: { $0.id == id }) else {
            return
        }

        guard openFiles[index].content != content else {
            return
        }

        openFiles[index].content = content
        openFiles[index].hasUnsavedChanges = true
    }
}
