//
//  FileBrowserStore.swift
//  aizen
//
//  Application store for file browser state management
//

import Foundation
import SwiftUI
import Combine
import CoreData
import AppKit
import os.log

enum FileGitStatus: Sendable {
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
class FileBrowserStore: ObservableObject {
    @Published var currentPath: String
    @Published var openFiles: [OpenFileInfo] = []
    @Published var selectedFileId: UUID?
    @Published var expandedPaths: Set<String> = []
    @Published var treeRefreshTrigger = UUID()
    @AppStorage("showHiddenFiles") var showHiddenFiles: Bool = true

    // Git status tracking
    @Published private(set) var gitFileStatus: [String: FileGitStatus] = [:]
    @Published private(set) var gitIgnoredPaths: Set<String> = []

    let worktree: Worktree
    let viewContext: NSManagedObjectContext
    var session: FileBrowserSession?
    let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen.app", category: "FileBrowser")
    let fileService = FileService()
    private let gitRuntime = FileBrowserGitRuntime()

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

        guard openFiles[index].content != content else {
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

    func refreshTree() {
        treeRefreshTrigger = UUID()
    }

    func copyPathToClipboard(path: String) {
        Clipboard.copy(path)
        ToastStore.shared.show("Path copied to clipboard", type: .success)
    }

    func revealInFinder(path: String) {
        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
    }

    // MARK: - Git Status

    func loadGitStatus() async {
        guard let worktreePath = worktree.path else { return }
        let expandedPathsSnapshot = expandedPaths
        let snapshot = await gitRuntime.loadGitSnapshot(
            basePath: worktreePath,
            expandedPaths: expandedPathsSnapshot
        )

        gitFileStatus = snapshot.fileStatus
        gitIgnoredPaths = snapshot.ignoredPaths
        refreshTree()
    }

    func refreshGitStatus() {
        Task {
            await loadGitStatus()
        }
    }
}
