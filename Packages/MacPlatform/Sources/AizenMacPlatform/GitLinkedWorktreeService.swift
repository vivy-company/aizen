import AizenHost
import Foundation

/// macOS Git adapter used only by the Host; callers never receive local paths.
public actor GitLinkedWorktreeService: LinkedWorktreeCreating {
    public init() {}

    public func createLinkedWorktree(source: URL, destination: URL, branch: String, createBranch: Bool, baseBranch: String?) async throws {
        guard FileManager.default.fileExists(atPath: source.appendingPathComponent(".git").path) else {
            throw Error.notRepository
        }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        var arguments = ["-C", source.path, "worktree", "add"]
        if createBranch {
            arguments += ["-b", branch]
            if let baseBranch, !baseBranch.isEmpty { arguments.append(baseBranch) }
        } else {
            arguments += [destination.path, branch]
            try await run(arguments)
            return
        }
        arguments.append(destination.path)
        try await run(arguments)
    }

    public enum Error: Swift.Error, LocalizedError { case notRepository, gitFailed(String)
        public var errorDescription: String? { switch self { case .notRepository: "The selected Resource is not a Git repository."; case .gitFailed(let message): message } }
    }

    private func run(_ arguments: [String]) async throws {
        let process = Process(); let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git"); process.arguments = arguments; process.standardError = stderr
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw Error.gitFailed(String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)) }
    }
}
