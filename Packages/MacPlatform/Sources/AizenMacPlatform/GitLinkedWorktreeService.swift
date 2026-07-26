import AizenHost
import AizenWire
import Foundation

/// macOS Git adapter used only by the Host; callers never receive local paths.
public actor GitLinkedWorktreeService: LinkedWorktreeCreating, IndependentContextCreating {
    public init() {}

    public func createLinkedWorktree(source: URL, destination: URL, branch: String, createBranch: Bool, baseBranch: String?) async throws {
        guard FileManager.default.fileExists(atPath: source.appendingPathComponent(".git").path) else {
            throw Error.notRepository
        }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        var arguments = ["-C", source.path, "worktree", "add"]
        if createBranch {
            arguments += ["-b", branch]
            arguments.append(destination.path)
            if let baseBranch, !baseBranch.isEmpty { arguments.append(baseBranch) }
        } else {
            arguments += [destination.path, branch]
            try await run(arguments)
            return
        }
        try await run(arguments)
    }

    public func createIndependentContext(source: URL, destination: URL, mode: IndependentContextMode) async throws {
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        switch mode {
        case .clone:
            guard FileManager.default.fileExists(atPath: source.appendingPathComponent(".git").path) else { throw Error.notRepository }
            try await run(["clone", "--local", source.path, destination.path])
        case .copy:
            try await runRsync(source: source, destination: destination)
        }
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

    private func runRsync(source: URL, destination: URL) async throws {
        let process = Process(); let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/rsync")
        process.arguments = ["-a", "--exclude", ".git", "\(source.path)/", "\(destination.path)/"]
        process.standardError = stderr
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw Error.gitFailed(String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)) }
    }
}
