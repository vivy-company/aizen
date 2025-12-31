import Foundation
import Clibgit2

/// Errors from libgit2 operations
nonisolated enum Libgit2Error: LocalizedError {
    case notARepository(String)
    case repositoryPathMissing(String)
    case repositoryCorrupted(String)
    case worktreeNotFound(String)
    case worktreeAlreadyExists(String)
    case worktreeLocked(String)
    case branchNotFound(String)
    case branchAlreadyExists(String)
    case referenceNotFound(String)
    case mergeConflict(String)
    case uncommittedChanges(String)
    case networkError(String)
    case authenticationFailed(String)
    case invalidPath(String)
    case indexError(String)
    case checkoutError(String)
    case unknownError(Int32, String)

    var errorDescription: String? {
        switch self {
        case .notARepository(let path):
            return "Not a git repository: \(path)"
        case .repositoryPathMissing(let path):
            return "Repository path no longer exists: \(path)"
        case .repositoryCorrupted(let message):
            return "Repository corrupted: \(message)"
        case .worktreeNotFound(let name):
            return "Worktree not found: \(name)"
        case .worktreeAlreadyExists(let name):
            return "Worktree already exists: \(name)"
        case .worktreeLocked(let name):
            return "Worktree is locked: \(name)"
        case .branchNotFound(let name):
            return "Branch not found: \(name)"
        case .branchAlreadyExists(let name):
            return "Branch already exists: \(name)"
        case .referenceNotFound(let ref):
            return "Reference not found: \(ref)"
        case .mergeConflict(let message):
            return "Merge conflict: \(message)"
        case .uncommittedChanges(let message):
            return "Uncommitted changes: \(message)"
        case .networkError(let message):
            return "Network error: \(message)"
        case .authenticationFailed(let message):
            return "Authentication failed: \(message)"
        case .invalidPath(let path):
            return "Invalid path: \(path)"
        case .indexError(let message):
            return "Index error: \(message)"
        case .checkoutError(let message):
            return "Checkout error: \(message)"
        case .unknownError(let code, let message):
            return "Git error (\(code)): \(message)"
        }
    }

    /// Create error from libgit2 error code
    static func from(_ errorCode: Int32, context: String = "") -> Libgit2Error {
        let gitError = git_error_last()
        let message: String
        if let errorPtr = gitError, let msgPtr = errorPtr.pointee.message {
            message = String(cString: msgPtr)
        } else {
            message = context.isEmpty ? "Unknown error" : context
        }

        // Map common error codes to specific errors
        if errorCode == Int32(GIT_ENOTFOUND.rawValue) {
            if context.contains("worktree") {
                return .worktreeNotFound(message)
            } else if context.contains("branch") {
                return .branchNotFound(message)
            } else if context.contains("reference") {
                return .referenceNotFound(message)
            }
            return .unknownError(errorCode, message)
        } else if errorCode == Int32(GIT_EEXISTS.rawValue) {
            if context.contains("worktree") {
                return .worktreeAlreadyExists(message)
            } else if context.contains("branch") {
                return .branchAlreadyExists(message)
            }
            return .unknownError(errorCode, message)
        } else if errorCode == Int32(GIT_ELOCKED.rawValue) {
            return .worktreeLocked(message)
        } else if errorCode == Int32(GIT_EMERGECONFLICT.rawValue) {
            return .mergeConflict(message)
        } else if errorCode == Int32(GIT_EUNCOMMITTED.rawValue) {
            return .uncommittedChanges(message)
        } else if errorCode == Int32(GIT_EAUTH.rawValue) {
            return .authenticationFailed(message)
        } else {
            return .unknownError(errorCode, message)
        }
    }

    /// Check if error code indicates success, throw if not
    static func check(_ errorCode: Int32, context: String = "") throws {
        guard errorCode >= 0 else {
            throw from(errorCode, context: context)
        }
    }
}
