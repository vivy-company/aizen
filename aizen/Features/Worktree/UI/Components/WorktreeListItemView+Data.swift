//
//  WorktreeListItemView+Data.swift
//  aizen
//
//  Derived app and worktree state for the row view.
//

import SwiftUI

extension WorktreeListItemView {
    var defaultTerminal: DetectedApp? {
        guard let bundleId = defaultTerminalBundleId else { return nil }
        return AppDetector.shared.getTerminals().first { $0.bundleIdentifier == bundleId }
    }

    var defaultEditor: DetectedApp? {
        guard let bundleId = defaultEditorBundleId else { return nil }
        return AppDetector.shared.getEditors().first { $0.bundleIdentifier == bundleId }
    }

    var finderApp: DetectedApp? {
        AppDetector.shared.getApps(for: .finder).first
    }

    var worktreeStatus: ItemStatus {
        ItemStatus(rawValue: worktree.status ?? "active") ?? .active
    }

    var isGitEnvironment: Bool {
        guard let path = worktree.path else { return false }
        return GitUtils.isGitRepository(at: path)
    }

    var supportsBranchOperations: Bool {
        isGitEnvironment && !worktree.isIndependentEnvironment
    }

    var supportsMergeOperations: Bool {
        isGitEnvironment && (worktree.isLinkedEnvironment || worktree.isPrimary)
    }

    var activeViewType: String {
        guard let worktreeId = worktree.id else { return "" }
        return tabStateManager.getState(for: worktreeId).viewType
    }

    var chatSessionCount: Int {
        sessionCounts.chats
    }

    var terminalSessionCount: Int {
        sessionCounts.terminals
    }

    var browserSessionCount: Int {
        sessionCounts.browsers
    }

    var fileSessionCount: Int {
        sessionCounts.files
    }

    var mergeSourceStatuses: [WorktreeStatusInfo] {
        worktreeStatuses.filter { $0.worktree.id != worktree.id }
    }
}
