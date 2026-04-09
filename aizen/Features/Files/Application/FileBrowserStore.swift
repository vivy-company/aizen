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
    static let sessionSaveDelay = Duration.milliseconds(150)

    @Published var currentPath: String
    @Published var openFiles: [OpenFileInfo] = []
    @Published var selectedFileId: UUID?
    @Published var expandedPaths: Set<String> = []
    @Published var treeRefreshTrigger = UUID()
    @AppStorage("showHiddenFiles") var showHiddenFiles: Bool = true

    // Git status tracking
    @Published var gitFileStatus: [String: FileGitStatus] = [:]
    @Published var gitIgnoredPaths: Set<String> = []

    let worktree: Worktree
    let viewContext: NSManagedObjectContext
    var session: FileBrowserSession?
    let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen.app", category: "FileBrowser")
    let fileService = FileService()
    let gitRuntime = FileBrowserGitRuntime()
    var sessionSaveTask: Task<Void, Never>?

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

    deinit {
        sessionSaveTask?.cancel()
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

}
