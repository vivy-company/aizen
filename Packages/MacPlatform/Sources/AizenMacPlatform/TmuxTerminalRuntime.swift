import AizenCore
import AizenHost
import Foundation

/// The macOS implementation of Host-owned terminal creation.
/// Paths remain inside Host-private resource details and are never returned to clients.
public actor TmuxTerminalRuntime: TerminalRuntime {
    public enum Error: Swift.Error, Sendable, Equatable {
        case tmuxUnavailable
        case invalidExecutionContext(ExecutionContextID)
        case processFailed(String)
    }

    public init() {}

    public func createTerminal(
        id: SessionID,
        spaceID: SpaceID,
        executionContext: ExecutionContext,
        resource: Resource?,
        title: String?,
        initialCommand: String?
    ) async throws -> TerminalLaunch {
        let directory = try workingDirectory(for: executionContext, resource: resource)
        let tmux = try tmuxExecutable()
        let sessionName = "aizen-\(id.description)"
        try ensureConfiguration()

        var arguments = [
            "-f", configurationURL.path,
            "new-session", "-d",
            "-s", sessionName,
            "-c", directory.path
        ]
        if let initialCommand, !initialCommand.isEmpty {
            arguments.append(initialCommand)
        }
        try run(tmux, arguments: arguments)
        let paneID = try output(
            tmux,
            arguments: ["display-message", "-p", "-t", sessionName, "#{pane_id}"]
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !paneID.isEmpty else { throw Error.processFailed("tmux did not return a pane identifier") }
        return TerminalLaunch(tmuxSessionName: sessionName, paneID: paneID)
    }

    private var configurationURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".aizen", isDirectory: true)
            .appendingPathComponent("tmux.conf")
    }

    private func workingDirectory(for context: ExecutionContext, resource: Resource?) throws -> URL {
        if context.kind == .gitWorktree,
           let reference = context.hostReference?.rawValue,
           reference.hasPrefix("local-worktree:") {
            return try existingDirectory(
                String(reference.dropFirst("local-worktree:".count)),
                contextID: context.id
            )
        }
        if context.kind == .repositoryCheckout,
           let reference = context.hostReference?.rawValue,
           reference.hasPrefix("local-checkout:") {
            return try existingDirectory(
                String(reference.dropFirst("local-checkout:".count)),
                contextID: context.id
            )
        }
        guard (context.kind == .localFolder || context.kind == .repositoryCheckout),
              let resource,
              resource.spaceID == context.spaceID,
              case .hostPrivate(let reference) = resource.details else {
            throw Error.invalidExecutionContext(context.id)
        }
        let prefix = context.kind == .localFolder ? "local-folder:" : "local-repository:"
        guard reference.rawValue.hasPrefix(prefix) else { throw Error.invalidExecutionContext(context.id) }
        return try existingDirectory(String(reference.rawValue.dropFirst(prefix.count)), contextID: context.id)
    }

    private func existingDirectory(_ path: String, contextID: ExecutionContextID) throws -> URL {
        guard path.hasPrefix("/") else { throw Error.invalidExecutionContext(contextID) }
        let directory = URL(fileURLWithPath: path)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw Error.invalidExecutionContext(contextID)
        }
        return directory
    }

    private func tmuxExecutable() throws -> URL {
        let candidates = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]
        guard let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw Error.tmuxUnavailable
        }
        return URL(fileURLWithPath: path)
    }

    private func run(_ executable: URL, arguments: [String]) throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw Error.processFailed("tmux exited with status \(process.terminationStatus)") }
    }

    private func output(_ executable: URL, arguments: [String]) throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw Error.processFailed("tmux exited with status \(process.terminationStatus)") }
        return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }

    private func ensureConfiguration() throws {
        let directory = configurationURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard !FileManager.default.fileExists(atPath: configurationURL.path) else { return }
        try """
        set -as terminal-features ",*:hyperlinks"
        set -g allow-passthrough on
        set -g status off
        set -g history-limit 10000
        set -g mouse on
        set -g default-terminal "xterm-256color"
        set -ag terminal-overrides ",xterm-256color:RGB"
        """.write(to: configurationURL, atomically: true, encoding: .utf8)
    }
}
