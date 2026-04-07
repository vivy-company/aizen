import Foundation
import Clibgit2

/// Line change type in diff
nonisolated enum Libgit2LineOrigin: Character, Sendable {
    case context = " "
    case addition = "+"
    case deletion = "-"
    case contextEofnl = "="
    case addEofnl = ">"
    case delEofnl = "<"
    case fileHeader = "F"
    case hunkHeader = "H"
    case binary = "B"

    init(from origin: CChar) {
        switch origin {
        case 32: self = .context        // ' '
        case 43: self = .addition       // '+'
        case 45: self = .deletion       // '-'
        case 61: self = .contextEofnl   // '='
        case 62: self = .addEofnl       // '>'
        case 60: self = .delEofnl       // '<'
        case 70: self = .fileHeader     // 'F'
        case 72: self = .hunkHeader     // 'H'
        case 66: self = .binary         // 'B'
        default: self = .context
        }
    }
}

/// A single line in a diff
nonisolated struct Libgit2DiffLine: Sendable {
    let origin: Libgit2LineOrigin
    let oldLineNumber: Int?
    let newLineNumber: Int?
    let content: String
}

/// A hunk in a diff
nonisolated struct Libgit2DiffHunk: Sendable {
    let header: String
    let oldStart: Int
    let oldLines: Int
    let newStart: Int
    let newLines: Int
    let lines: [Libgit2DiffLine]
}

/// Diff delta (file change)
nonisolated struct Libgit2DiffDelta: Sendable {
    let oldPath: String?
    let newPath: String?
    let status: DeltaStatus
    let hunks: [Libgit2DiffHunk]
    let additions: Int
    let deletions: Int
    let isBinary: Bool

    enum DeltaStatus: Sendable {
        case unmodified
        case added
        case deleted
        case modified
        case renamed
        case copied
        case ignored
        case untracked
        case typeChange
        case unreadable
        case conflicted
    }
}

/// Diff statistics
nonisolated struct Libgit2DiffStats: Sendable {
    let filesChanged: Int
    let insertions: Int
    let deletions: Int
}

/// Diff operations extension for Libgit2Repository
nonisolated extension Libgit2Repository {

    // MARK: - Private Helpers

    func parseDiff(_ diff: OpaquePointer) throws -> [Libgit2DiffDelta] {
        var deltas: [Libgit2DiffDelta] = []

        let numDeltas = git_diff_num_deltas(diff)
        for i in 0..<numDeltas {
            guard let delta = git_diff_get_delta(diff, i) else { continue }

            let status = parseDeltaStatus(delta.pointee.status)
            let oldPath = delta.pointee.old_file.path.map { String(cString: $0) }
            let newPath = delta.pointee.new_file.path.map { String(cString: $0) }
            let isBinary = (delta.pointee.flags & UInt32(GIT_DIFF_FLAG_BINARY.rawValue)) != 0

            // Get hunks and lines
            var hunks: [Libgit2DiffHunk] = []
            var additions = 0
            var deletions = 0

            // Use patch to get detailed line info
            var patch: OpaquePointer?
            if git_patch_from_diff(&patch, diff, i) == 0, let p = patch {
                defer { git_patch_free(p) }

                let numHunks = git_patch_num_hunks(p)
                for h in 0..<numHunks {
                    var hunk: UnsafePointer<git_diff_hunk>?
                    var hunkLines: Int = 0

                    guard git_patch_get_hunk(&hunk, &hunkLines, p, h) == 0, let hunkPtr = hunk else {
                        continue
                    }

                    var lines: [Libgit2DiffLine] = []
                    for l in 0..<hunkLines {
                        var line: UnsafePointer<git_diff_line>?
                        guard git_patch_get_line_in_hunk(&line, p, h, l) == 0, let linePtr = line else {
                            continue
                        }

                        let origin = Libgit2LineOrigin(from: linePtr.pointee.origin)
                        let content: String
                        if let contentPtr = linePtr.pointee.content {
                            let buffer = UnsafeRawBufferPointer(
                                start: contentPtr,
                                count: linePtr.pointee.content_len
                            )
                            content = String(decoding: buffer, as: UTF8.self)
                        } else {
                            content = ""
                        }

                        let oldLine = linePtr.pointee.old_lineno > 0 ? Int(linePtr.pointee.old_lineno) : nil
                        let newLine = linePtr.pointee.new_lineno > 0 ? Int(linePtr.pointee.new_lineno) : nil

                        lines.append(Libgit2DiffLine(
                            origin: origin,
                            oldLineNumber: oldLine,
                            newLineNumber: newLine,
                            content: content
                        ))

                        if origin == .addition { additions += 1 }
                        if origin == .deletion { deletions += 1 }
                    }

                    let header = withUnsafePointer(to: hunkPtr.pointee.header) { ptr in
                        ptr.withMemoryRebound(to: CChar.self, capacity: Int(GIT_DIFF_HUNK_HEADER_SIZE)) {
                            String(cString: $0)
                        }
                    }
                    hunks.append(Libgit2DiffHunk(
                        header: header,
                        oldStart: Int(hunkPtr.pointee.old_start),
                        oldLines: Int(hunkPtr.pointee.old_lines),
                        newStart: Int(hunkPtr.pointee.new_start),
                        newLines: Int(hunkPtr.pointee.new_lines),
                        lines: lines
                    ))
                }
            }

            deltas.append(Libgit2DiffDelta(
                oldPath: oldPath,
                newPath: newPath,
                status: status,
                hunks: hunks,
                additions: additions,
                deletions: deletions,
                isBinary: isBinary
            ))
        }

        return deltas
    }

    func parseDeltaStatus(_ status: git_delta_t) -> Libgit2DiffDelta.DeltaStatus {
        switch status {
        case GIT_DELTA_UNMODIFIED: return .unmodified
        case GIT_DELTA_ADDED: return .added
        case GIT_DELTA_DELETED: return .deleted
        case GIT_DELTA_MODIFIED: return .modified
        case GIT_DELTA_RENAMED: return .renamed
        case GIT_DELTA_COPIED: return .copied
        case GIT_DELTA_IGNORED: return .ignored
        case GIT_DELTA_UNTRACKED: return .untracked
        case GIT_DELTA_TYPECHANGE: return .typeChange
        case GIT_DELTA_UNREADABLE: return .unreadable
        case GIT_DELTA_CONFLICTED: return .conflicted
        default: return .unmodified
        }
    }

}
