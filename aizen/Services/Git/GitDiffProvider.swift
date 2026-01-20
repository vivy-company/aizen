//
//  GitDiffProvider.swift
//  aizen
//
//  Git diff provider for tracking file changes in the editor gutter
//

import Foundation
import CodeEditSourceEditor

/// Provides git diff information for files
actor GitDiffProvider {

    /// Get git diff status for each line in a file
    /// - Parameters:
    ///   - filePath: Absolute path to the file
    ///   - repoPath: Path to the git repository root
    /// - Returns: Dictionary mapping line numbers to their diff status
    func getLineDiff(filePath: String, repoPath: String) async throws -> [Int: GitDiffLineStatus] {
        // Get relative path from repo root
        let fileURL = URL(fileURLWithPath: filePath)
        let repoURL = URL(fileURLWithPath: repoPath)
        let relativePath = fileURL.path.replacingOccurrences(of: repoURL.path + "/", with: "")

        // Actor methods run on background executor, no need for Task.detached
        let repo = try Libgit2Repository(path: repoPath)
        let delta = try repo.diffFile(relativePath)

        guard let delta = delta else {
            return [:]
        }

        return parseDiffDelta(delta)
    }

    /// Parse libgit2 diff delta into line status mapping
    private func parseDiffDelta(_ delta: Libgit2DiffDelta) -> [Int: GitDiffLineStatus] {
        var lineStatus: [Int: GitDiffLineStatus] = [:]

        for hunk in delta.hunks {
            let oldCount = hunk.oldLines
            let newCount = hunk.newLines
            let newStart = hunk.newStart

            if oldCount == 0 {
                // Lines were added
                for offset in 0..<newCount {
                    lineStatus[newStart + offset] = .added
                }
            } else if newCount == 0 {
                // Lines were deleted
                lineStatus[hunk.oldStart] = .deleted(afterLine: newStart > 0 ? newStart - 1 : 0)
            } else {
                // Parse individual lines for more precise status
                var hunkHasAdditions = false
                for line in hunk.lines {
                    switch line.origin {
                    case .addition:
                        if let lineNum = line.newLineNumber {
                            lineStatus[lineNum] = .added
                            hunkHasAdditions = true
                        }
                    case .deletion:
                        // Deletions are tracked differently - mark the next line
                        break
                    case .context:
                        break
                    default:
                        break
                    }
                }

                // If no specific additions found in this hunk, mark as modified
                if !hunkHasAdditions {
                    for offset in 0..<newCount {
                        lineStatus[newStart + offset] = .modified
                    }
                }
            }
        }

        return lineStatus
    }

    /// Check if a file is tracked by git
    func isFileTracked(filePath: String, repoPath: String) async -> Bool {
        let fileURL = URL(fileURLWithPath: filePath)
        let repoURL = URL(fileURLWithPath: repoPath)
        let relativePath = fileURL.path.replacingOccurrences(of: repoURL.path + "/", with: "")

        // Actor methods run on background executor, no need for Task.detached
        do {
            let repo = try Libgit2Repository(path: repoPath)
            let status = try repo.status()

            // File is tracked if it's in any category except untracked
            let allPaths = status.staged.map { $0.path } +
                          status.modified.map { $0.path } +
                          status.conflicted.map { $0.path }

            // Also check if file exists in HEAD
            if allPaths.contains(relativePath) {
                return true
            }

            // Check if file is in the index or HEAD (not untracked)
            return !status.untracked.contains { $0.path == relativePath }
        } catch {
            return false
        }
    }
}
