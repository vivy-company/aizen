//
//  FileBrowserViewModel.swift
//  aizen
//
//  View model for file browser state management
//

import Foundation
import SwiftUI
import Combine

struct FileItem: Identifiable {
    let id = UUID()
    let name: String
    let path: String
    let isDirectory: Bool
}

struct OpenFileInfo: Identifiable, Equatable {
    let id: UUID
    let name: String
    let path: String
    var content: String
    var hasUnsavedChanges: Bool

    init(id: UUID = UUID(), name: String, path: String, content: String, hasUnsavedChanges: Bool = false) {
        self.id = id
        self.name = name
        self.path = path
        self.content = content
        self.hasUnsavedChanges = hasUnsavedChanges
    }

    static func == (lhs: OpenFileInfo, rhs: OpenFileInfo) -> Bool {
        lhs.id == rhs.id
    }
}

@MainActor
class FileBrowserViewModel: ObservableObject {
    @Published var currentPath: String
    @Published var openFiles: [OpenFileInfo] = []
    @Published var selectedFileId: UUID?
    @Published var expandedPaths: Set<String> = []

    init(rootPath: String) {
        self.currentPath = rootPath
    }

    func listDirectory(path: String) throws -> [FileItem] {
        let url = URL(fileURLWithPath: path)
        let contents = try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        return contents.map { fileURL in
            let isDir = (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            return FileItem(
                name: fileURL.lastPathComponent,
                path: fileURL.path,
                isDirectory: isDir
            )
        }.sorted { item1, item2 in
            if item1.isDirectory != item2.isDirectory {
                return item1.isDirectory
            }
            return item1.name.localizedCaseInsensitiveCompare(item2.name) == .orderedAscending
        }
    }

    func openFile(path: String) async {
        print("DEBUG ViewModel: openFile called with: \(path)")

        // Check if already open
        if let existing = openFiles.first(where: { $0.path == path }) {
            print("DEBUG ViewModel: File already open, selecting")
            selectedFileId = existing.id
            return
        }

        // Load file content
        let fileURL = URL(fileURLWithPath: path)
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            print("DEBUG ViewModel: Failed to read file")
            return
        }

        print("DEBUG ViewModel: File loaded, content length: \(content.count)")

        let fileInfo = OpenFileInfo(
            name: fileURL.lastPathComponent,
            path: path,
            content: content
        )

        openFiles.append(fileInfo)
        selectedFileId = fileInfo.id
        print("DEBUG ViewModel: File added to openFiles, count: \(openFiles.count)")
    }

    func closeFile(id: UUID) {
        openFiles.removeAll { $0.id == id }
        if selectedFileId == id {
            selectedFileId = openFiles.last?.id
        }
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

        openFiles[index].content = content
        openFiles[index].hasUnsavedChanges = true
    }

    func toggleExpanded(path: String) {
        if expandedPaths.contains(path) {
            expandedPaths.remove(path)
        } else {
            expandedPaths.insert(path)
        }
    }

    func isExpanded(path: String) -> Bool {
        expandedPaths.contains(path)
    }
}
