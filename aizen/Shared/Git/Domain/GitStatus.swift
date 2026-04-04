//
//  GitStatus.swift
//  aizen
//
//  Git status representation
//

import Foundation

struct GitStatus: Equatable, Identifiable {
    let id = UUID()
    let stagedFiles: [String]
    let modifiedFiles: [String]
    let untrackedFiles: [String]
    let conflictedFiles: [String]
    let currentBranch: String
    let aheadCount: Int
    let behindCount: Int
    let additions: Int
    let deletions: Int

    var hasChanges: Bool {
        totalChanges > 0
    }

    var totalChanges: Int {
        stagedFiles.count + modifiedFiles.count + untrackedFiles.count
    }

    static let empty = GitStatus(
        stagedFiles: [],
        modifiedFiles: [],
        untrackedFiles: [],
        conflictedFiles: [],
        currentBranch: "",
        aheadCount: 0,
        behindCount: 0,
        additions: 0,
        deletions: 0
    )

    // Custom equality that ignores id (for semantic equality)
    static func == (lhs: GitStatus, rhs: GitStatus) -> Bool {
        lhs.stagedFiles == rhs.stagedFiles &&
        lhs.modifiedFiles == rhs.modifiedFiles &&
        lhs.untrackedFiles == rhs.untrackedFiles &&
        lhs.conflictedFiles == rhs.conflictedFiles &&
        lhs.currentBranch == rhs.currentBranch &&
        lhs.aheadCount == rhs.aheadCount &&
        lhs.behindCount == rhs.behindCount &&
        lhs.additions == rhs.additions &&
        lhs.deletions == rhs.deletions
    }
}
