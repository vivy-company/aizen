//
//  GitDiffService.swift
//  aizen
//
//  Service for getting git diffs and file changes
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
    private let executor: GitCommandExecutor

    init(executor: GitCommandExecutor = GitCommandExecutor()) {
        self.executor = executor
    }

    /// Get diff for a specific file
    func getFileDiff(at path: String, in repoPath: String) async throws -> FileDiff {
        // Get the diff with line numbers
        let output = try await executor.executeGit(
            arguments: ["diff", "--unified=0", "--no-color", path],
            at: repoPath
        )

        return parseDiff(output)
    }

    /// Parse git diff output into line change information
    private func parseDiff(_ output: String) -> FileDiff {
        var changes: [FileDiff.Change] = []

        let lines = output.components(separatedBy: .newlines)

        for line in lines {
            // Parse unified diff format: @@ -start,count +start,count @@
            if line.hasPrefix("@@") {
                let components = line.components(separatedBy: " ")
                for component in components {
                    if component.hasPrefix("+") && !component.hasPrefix("+++") {
                        // Added/modified lines
                        let rangeStr = String(component.dropFirst())
                        if let range = parseRange(rangeStr), range.count > 0 {
                            for lineNum in range.start..<(range.start + range.count) {
                                changes.append(FileDiff.Change(lineNumber: lineNum, type: .added))
                            }
                        }
                    } else if component.hasPrefix("-") && !component.hasPrefix("---") {
                        // Deleted lines (we won't show these in the gutter)
                        let rangeStr = String(component.dropFirst())
                        if let range = parseRange(rangeStr), range.count > 0 {
                            for lineNum in range.start..<(range.start + range.count) {
                                changes.append(FileDiff.Change(lineNumber: lineNum, type: .deleted))
                            }
                        }
                    }
                }
            }
        }

        return FileDiff(changes: changes)
    }

    /// Parse range string like "10,5" or "10" into (start, count)
    private func parseRange(_ rangeStr: String) -> (start: Int, count: Int)? {
        if rangeStr.contains(",") {
            let parts = rangeStr.components(separatedBy: ",")
            guard parts.count == 2,
                  let start = Int(parts[0]),
                  let count = Int(parts[1]) else {
                return nil
            }
            return (start, count)
        } else {
            guard let start = Int(rangeStr) else {
                return nil
            }
            return (start, 1)
        }
    }
}
