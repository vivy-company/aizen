//
//  FileBrowserViewModel.swift
//  aizen
//
//  View model for file browser state management
//

import Foundation
import SwiftUI
import Combine
import CoreData
import AppKit
import os.log

enum FileGitStatus {
    case modified      // Orange - file has unstaged changes
    case staged        // Green - file has staged changes
    case untracked     // Blue - file is not tracked by git
    case conflicted    // Red - file has merge conflicts
    case added         // Green - new file staged
    case deleted       // Red - file deleted
    case renamed       // Purple - file renamed
    case mixed         // Orange - file has both staged and unstaged changes
}

struct FileItem: Identifiable {
    var id: String { path }
    let name: String
    let path: String
    let isDirectory: Bool
    let isHidden: Bool
    let isGitIgnored: Bool
    let gitStatus: FileGitStatus?

    init(name: String, path: String, isDirectory: Bool, isHidden: Bool = false, isGitIgnored: Bool = false, gitStatus: FileGitStatus? = nil) {
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.isHidden = isHidden
        self.isGitIgnored = isGitIgnored
        self.gitStatus = gitStatus
    }
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
    @Published var treeRefreshTrigger = UUID()
    @AppStorage("showHiddenFiles") var showHiddenFiles: Bool = true

    // Git status tracking
    @Published private(set) var gitFileStatus: [String: FileGitStatus] = [:]
    @Published private(set) var gitIgnoredPaths: Set<String> = []

    private let worktree: Worktree
    private let viewContext: NSManagedObjectContext
    private var session: FileBrowserSession?
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen.app", category: "FileBrowser")

    init(worktree: Worktree, context: NSManagedObjectContext) {
        self.worktree = worktree
        self.viewContext = context
        self.currentPath = worktree.path ?? ""

        // Load or create session
        loadSession()

        // Load git status
        Task {
            await loadGitStatus()
        }
    }

    private func loadSession() {
        // Try to get existing session from worktree
        if let existingSession = worktree.fileBrowserSession {
            self.session = existingSession

            // Restore state from session
            if let currentPath = existingSession.currentPath {
                self.currentPath = currentPath
            }

            if let expandedPathsArray = existingSession.value(forKey: "expandedPaths") as? [String] {
                self.expandedPaths = Set(expandedPathsArray)
            }

            if let selectedPath = existingSession.selectedFilePath {
                // Restore selected file if it was open
                if let openPathsArray = existingSession.value(forKey: "openFilesPaths") as? [String],
                   openPathsArray.contains(selectedPath) {
                    // Will be restored when files are reopened
                }
            }

            // Restore open files
            if let openPathsArray = existingSession.value(forKey: "openFilesPaths") as? [String] {
                Task {
                    for path in openPathsArray {
                        await openFile(path: path)
                    }

                    // Restore selection after files are opened
                    if let selectedPath = existingSession.selectedFilePath,
                       let selectedFile = openFiles.first(where: { $0.path == selectedPath }) {
                        selectedFileId = selectedFile.id
                    }
                }
            }
        } else {
            // Create new session
            let newSession = FileBrowserSession(context: viewContext)
            newSession.id = UUID()
            newSession.currentPath = currentPath
            newSession.setValue([], forKey: "expandedPaths")
            newSession.setValue([], forKey: "openFilesPaths")
            newSession.worktree = worktree
            self.session = newSession

            saveSession()
        }
    }

    private func saveSession() {
        guard let session = session else { return }

        session.currentPath = currentPath
        session.setValue(Array(expandedPaths), forKey: "expandedPaths")
        session.setValue(openFiles.map { $0.path }, forKey: "openFilesPaths")
        session.selectedFilePath = openFiles.first(where: { $0.id == selectedFileId })?.path

        do {
            try viewContext.save()
        } catch {
            logger.error("Error saving FileBrowserSession: \(error)")
        }
    }

    func listDirectory(path: String) throws -> [FileItem] {
        let contents = try FileManager.default.contentsOfDirectory(atPath: path)

        return contents.compactMap { name -> FileItem? in
            let isHidden = name.hasPrefix(".")

            // Skip hidden files if setting is off
            if isHidden && !showHiddenFiles {
                return nil
            }

            let filePath = (path as NSString).appendingPathComponent(name)
            let fileURL = URL(fileURLWithPath: filePath)
            let isDir = isBrowsableDirectory(fileURL)

            // Get relative path for git status lookup
            let relativePath = getRelativePath(for: filePath)

            // Check git ignored status
            let isIgnored = gitIgnoredPaths.contains(filePath) || gitIgnoredPaths.contains(relativePath)

            // Get git status for this file
            let status = gitFileStatus[relativePath]

            return FileItem(
                name: name,
                path: filePath,
                isDirectory: isDir,
                isHidden: isHidden,
                isGitIgnored: isIgnored,
                gitStatus: status
            )
        }.sorted { item1, item2 in
            if item1.isDirectory != item2.isDirectory {
                return item1.isDirectory
            }
            return item1.name.localizedCaseInsensitiveCompare(item2.name) == .orderedAscending
        }
    }

    private func isBrowsableDirectory(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else {
            return false
        }

        if values.isDirectory == true {
            return true
        }

        // URL.isDirectoryKey is false for symlinked directories; resolve via fileExists.
        if values.isSymbolicLink == true {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
                return isDirectory.boolValue
            }
        }

        return false
    }

    private func getRelativePath(for absolutePath: String) -> String {
        guard let basePath = worktree.path else { return absolutePath }
        if absolutePath.hasPrefix(basePath) {
            var relative = String(absolutePath.dropFirst(basePath.count))
            if relative.hasPrefix("/") {
                relative = String(relative.dropFirst())
            }
            return relative
        }
        return absolutePath
    }

    func openFile(path: String) async {
        let fileURL = URL(fileURLWithPath: path)

        // Gracefully handle directory selections (e.g. symlinked repo folders in Cross-Project).
        if isBrowsableDirectory(fileURL) {
            currentPath = path
            saveSession()
            return
        }

        // Check if already open
        if let existing = openFiles.first(where: { $0.path == path }) {
            selectedFileId = existing.id
            return
        }

        // Load file content
        let maxOpenFileBytes = 5 * 1024 * 1024
        if let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize,
           size > maxOpenFileBytes {
            let mb = Double(size) / 1024.0 / 1024.0
            ToastManager.shared.show(String(format: "File too large to open (%.1f MB). Open in external editor.", mb), type: .info)
            return
        }

        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            ToastManager.shared.show("Unable to open file (not UTF-8 text).", type: .info)
            return
        }

        let fileInfo = OpenFileInfo(
            name: fileURL.lastPathComponent,
            path: path,
            content: content
        )

        openFiles.append(fileInfo)
        selectedFileId = fileInfo.id
        saveSession()
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

        openFiles[index].content = content
        openFiles[index].hasUnsavedChanges = true
    }

    func toggleExpanded(path: String) {
        if expandedPaths.contains(path) {
            expandedPaths.remove(path)
        } else {
            expandedPaths.insert(path)
        }
        saveSession()
    }

    func isExpanded(path: String) -> Bool {
        expandedPaths.contains(path)
    }

    private func refreshTree() {
        treeRefreshTrigger = UUID()
    }

    // MARK: - File Operations

    private let fileService = FileService()

    func createNewFile(parentPath: String, name: String) async {
        let filePath = (parentPath as NSString).appendingPathComponent(name)

        do {
            try await fileService.createFile(at: filePath)
            ToastManager.shared.show("Created \(name)", type: .success)

            // Refresh the tree to show new file
            refreshTree()

            // Open the new file
            await openFile(path: filePath)
        } catch {
            ToastManager.shared.show(error.localizedDescription, type: .error)
        }
    }

    func createNewFolder(parentPath: String, name: String) async {
        let folderPath = (parentPath as NSString).appendingPathComponent(name)

        do {
            try await fileService.createDirectory(at: folderPath)
            ToastManager.shared.show("Created folder \(name)", type: .success)

            // Refresh the tree to show new folder
            refreshTree()

            // Auto-expand the newly created folder
            expandedPaths.insert(folderPath)
        } catch {
            ToastManager.shared.show(error.localizedDescription, type: .error)
        }
    }

    func renameItem(oldPath: String, newName: String) async {
        let parentPath = (oldPath as NSString).deletingLastPathComponent
        let newPath = (parentPath as NSString).appendingPathComponent(newName)

        do {
            try await fileService.renameItem(from: oldPath, to: newPath)
            ToastManager.shared.show("Renamed to \(newName)", type: .success)

            // If file was open, update its info
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

            // If it was a directory that was expanded, update its path in expandedPaths
            if expandedPaths.contains(oldPath) {
                expandedPaths.remove(oldPath)
                expandedPaths.insert(newPath)
            }

            // Refresh the tree to show rename
            refreshTree()

            saveSession()
        } catch {
            ToastManager.shared.show(error.localizedDescription, type: .error)
        }
    }

    func deleteItem(path: String) async {
        let fileName = (path as NSString).lastPathComponent

        do {
            try await fileService.deleteItem(at: path)
            ToastManager.shared.show("Deleted \(fileName)", type: .success)

            // Close file if it was open
            if let openFile = openFiles.first(where: { $0.path == path }) {
                closeFile(id: openFile.id)
            }

            // Remove from expanded paths if it was a directory
            expandedPaths.remove(path)

            // Refresh the tree to show deletion
            refreshTree()
        } catch {
            ToastManager.shared.show(error.localizedDescription, type: .error)
        }
    }

    func copyPathToClipboard(path: String) {
        Clipboard.copy(path)
        ToastManager.shared.show("Path copied to clipboard", type: .success)
    }

    func revealInFinder(path: String) {
        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
    }

    // MARK: - Git Status

    func loadGitStatus() async {
        guard let worktreePath = worktree.path else { return }

        do {
            // Load git status using libgit2 on background thread to avoid blocking UI
            let newStatus = try await Task.detached {
                let repo = try Libgit2Repository(path: worktreePath)
                let status = try repo.status()

                // Convert to file status map
                var statusMap: [String: FileGitStatus] = [:]

                for entry in status.staged {
                    let absolutePath = (worktreePath as NSString).appendingPathComponent(entry.path)
                    statusMap[absolutePath] = .staged
                }

                for entry in status.modified {
                    let absolutePath = (worktreePath as NSString).appendingPathComponent(entry.path)
                    statusMap[absolutePath] = .modified
                }

                for entry in status.untracked {
                    let absolutePath = (worktreePath as NSString).appendingPathComponent(entry.path)
                    statusMap[absolutePath] = .untracked
                }

                for entry in status.conflicted {
                    let absolutePath = (worktreePath as NSString).appendingPathComponent(entry.path)
                    statusMap[absolutePath] = .conflicted
                }

                return statusMap
            }.value

            gitFileStatus = newStatus

            // Load gitignored files for visible directories
            await loadGitIgnored(for: worktreePath)

            // Refresh tree to reflect new status
            refreshTree()
        } catch {
            logger.debug("Failed to load git status: \(error.localizedDescription)")
        }
    }

    private func loadGitIgnored(for basePath: String) async {
        var ignoredPaths = Set<String>()

        // Get expanded paths snapshot before going off main thread
        let expandedPathsSnapshot = expandedPaths

        // Get list of all files/dirs in expanded paths plus root (run off main thread)
        let pathsToCheck: [String] = await Task.detached {
            var paths: [String] = []

            // Add root level items
            if let items = try? FileManager.default.contentsOfDirectory(atPath: basePath) {
                paths.append(contentsOf: items)
            }

            // Add items from expanded directories
            for expandedPath in expandedPathsSnapshot {
                let relativePath = expandedPath.hasPrefix(basePath)
                    ? String(expandedPath.dropFirst(basePath.count + 1))
                    : ""
                if let items = try? FileManager.default.contentsOfDirectory(atPath: expandedPath) {
                    for item in items {
                        let itemRelPath = relativePath.isEmpty ? item : "\(relativePath)/\(item)"
                        paths.append(itemRelPath)
                    }
                }
            }

            return paths
        }.value

        guard !pathsToCheck.isEmpty else { return }

        // Process in batches to avoid argument list too long error
        let batchSize = 100
        for batchStart in stride(from: 0, to: pathsToCheck.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, pathsToCheck.count)
            let batch = Array(pathsToCheck[batchStart..<batchEnd])

            // Use git check-ignore command with async execution (non-blocking)
            do {
                let result = try await ProcessExecutor.shared.executeWithOutput(
                    executable: "/usr/bin/git",
                    arguments: ["check-ignore"] + batch,
                    workingDirectory: basePath
                )

                // git check-ignore returns exit code 1 when no files are ignored, which is fine
                for line in result.stdout.split(separator: "\n") {
                    let path = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !path.isEmpty {
                        ignoredPaths.insert(path)
                        let absolutePath = (basePath as NSString).appendingPathComponent(path)
                        ignoredPaths.insert(absolutePath)
                    }
                }
            } catch {
                logger.debug("git check-ignore: \(error.localizedDescription)")
            }
        }

        gitIgnoredPaths = ignoredPaths
    }

    func refreshGitStatus() {
        Task {
            await loadGitStatus()
        }
    }
}
