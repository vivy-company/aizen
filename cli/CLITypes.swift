import Foundation

enum ExitCode: Int32 {
    case success = 0
    case generalError = 1
    case invalidArguments = 2
    case repositoryNotFound = 3
    case workspaceNotFound = 5
    case pathNotFound = 6
    case hostUnavailable = 7
    case incompatibleHost = 8
}

enum CLIError: Error, LocalizedError {
    case invalidArguments(String)
    case repositoryNotFound(String)
    case workspaceNotFound(String)
    case pathNotFound(String)
    case appNotFound
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
        case .workspaceNotFound(let name):
            return "Workspace not found: \(name)"
        case .pathNotFound(let path):
            return "Path does not exist: \(path)"
        case .appNotFound:
            return "Aizen app not found. Please install and launch Aizen first."
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
