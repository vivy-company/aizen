import Foundation

enum ExitCode: Int32 {
    case success = 0
    case generalError = 1
    case invalidArguments = 2
    case repositoryNotFound = 3
    case notGitRepository = 4
    case workspaceNotFound = 5
    case pathNotFound = 6
}

enum CLIError: Error, LocalizedError {
    case invalidArguments(String)
    case repositoryNotFound(String)
    case notGitRepository(String)
    case workspaceNotFound(String)
    case pathNotFound(String)
    case appNotFound
    case modelNotFound
    case storeLoadFailed(String)
    case cloneFailed(String)
    case ioError(String)
    case tmuxNotInstalled
    case noActiveSessions
    case sessionNotFound(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .invalidArguments(let message):
            return message
        case .repositoryNotFound(let path):
            return "Repository not found for path: \(path)"
        case .notGitRepository(let path):
            return "Not a git repository: \(path)"
        case .workspaceNotFound(let name):
            return "Workspace not found: \(name)"
        case .pathNotFound(let path):
            return "Path does not exist: \(path)"
        case .appNotFound:
            return "Aizen app not found. Please install and launch Aizen first."
        case .modelNotFound:
            return "Aizen data model not found in app bundle."
        case .storeLoadFailed(let message):
            return "Failed to load Aizen data store: \(message)"
        case .cloneFailed(let message):
            return "Clone failed: \(message)"
        case .ioError(let message):
            return message
        case .tmuxNotInstalled:
            return "tmux is not installed. Install with: brew install tmux"
        case .noActiveSessions:
            return "No active terminal sessions found"
        case .sessionNotFound(let name):
            return "No terminal session found for: \(name)"
        case .cancelled:
            return "Cancelled"
        }
    }

    var exitCode: ExitCode {
        switch self {
        case .invalidArguments:
            return .invalidArguments
        case .repositoryNotFound:
            return .repositoryNotFound
        case .notGitRepository:
            return .notGitRepository
        case .workspaceNotFound:
            return .workspaceNotFound
        case .pathNotFound:
            return .pathNotFound
        default:
            return .generalError
        }
    }
}

struct ParsedArguments {
    var positionals: [String]
    var options: [String: String]
    var flags: Set<String>
}

func printError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}
