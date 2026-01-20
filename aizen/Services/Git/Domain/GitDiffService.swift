//
//  GitDiffService.swift
//  aizen
//
//  Service for getting git diffs and file changes using libgit2
//

import Foundation

struct FileDiff {
    struct Change {
        let lineNumber: Int
        let type: ChangeType
    }

    enum ChangeType {
        case added
        case modified
        case deleted
    }

    let changes: [Change]
}

actor GitDiffService {

    /// Get diff for a specific file
    func getFileDiff(at filePath: String, in repoPath: String) async throws -> FileDiff {
        let repo = try Libgit2Repository(path: repoPath)

        // Get diff for the file
        if let delta = try repo.diffFile(filePath) {
            var changes: [FileDiff.Change] = []

            for hunk in delta.hunks {
                for line in hunk.lines {
                    switch line.origin {
                    case .addition:
                        if let lineNum = line.newLineNumber {
                            changes.append(FileDiff.Change(lineNumber: lineNum, type: .added))
                        }
                    case .deletion:
                        if let lineNum = line.oldLineNumber {
                            changes.append(FileDiff.Change(lineNumber: lineNum, type: .deleted))
                        }
                    default:
                        break
                    }
                }
            }

            return FileDiff(changes: changes)
        }

        return FileDiff(changes: [])
    }

    /// Get full diff content for display
    func getFullDiff(at repoPath: String) async throws -> [Libgit2DiffDelta] {
        let repo = try Libgit2Repository(path: repoPath)
        return try repo.diffIndexToWorkdir()
    }

    /// Get staged diff content
    func getStagedDiff(at repoPath: String) async throws -> [Libgit2DiffDelta] {
        let repo = try Libgit2Repository(path: repoPath)
        return try repo.diffHeadToIndex()
    }

    /// Get diff statistics
    func getDiffStats(at repoPath: String) async throws -> Libgit2DiffStats {
        let repo = try Libgit2Repository(path: repoPath)
        return try repo.diffStats()
    }
}
