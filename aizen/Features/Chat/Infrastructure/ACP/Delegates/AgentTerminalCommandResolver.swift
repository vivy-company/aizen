import Foundation

struct AgentTerminalCommandResolution {
    let executablePath: String
    let arguments: [String]
}

enum AgentTerminalCommandResolver {
    nonisolated private static let shellOperators = ["|", "&&", "||", ";", ">", ">>", "<", "$(", "`", "&"]

    nonisolated static func resolve(
        command: String,
        args: [String]?,
        cwd: String?,
        environment: [String: String]
    ) throws -> AgentTerminalCommandResolution {
        let needsShell = shellOperators.contains { command.contains($0) }

        if needsShell {
            let additionalArguments = args?.map(shellEscaped) ?? []
            let shellCommand = ([command] + additionalArguments).joined(separator: " ")

            return AgentTerminalCommandResolution(
                executablePath: "/bin/sh",
                arguments: ["-c", shellCommand]
            )
        }

        if args == nil || args?.isEmpty == true {
            if command.contains(" ") || command.contains("\"") {
                let parsedCommand = try parseCommandString(command)
                return AgentTerminalCommandResolution(
                    executablePath: try resolveExecutablePath(parsedCommand.executable, cwd: cwd, environment: environment),
                    arguments: parsedCommand.arguments
                )
            }

            return AgentTerminalCommandResolution(
                executablePath: try resolveExecutablePath(command, cwd: cwd, environment: environment),
                arguments: []
            )
        }

        return AgentTerminalCommandResolution(
            executablePath: try resolveExecutablePath(command, cwd: cwd, environment: environment),
            arguments: args ?? []
        )
    }

    nonisolated private static func parseCommandString(_ command: String) throws -> (executable: String, arguments: [String]) {
        var executable: String?
        var arguments: [String] = []
        var currentArgument = ""
        var inQuotes = false
        var escapeNext = false

        for character in command {
            if escapeNext {
                currentArgument.append(character)
                escapeNext = false
                continue
            }

            if character == "\\" {
                escapeNext = true
                continue
            }

            if character == "\"" {
                inQuotes.toggle()
                continue
            }

            if character == " " && !inQuotes {
                appendArgument(
                    currentArgument,
                    executable: &executable,
                    arguments: &arguments
                )
                currentArgument = ""
                continue
            }

            currentArgument.append(character)
        }

        appendArgument(
            currentArgument,
            executable: &executable,
            arguments: &arguments
        )

        guard let executable, !executable.isEmpty else {
            throw AgentTerminalDelegate.TerminalError.commandParsingFailed(command)
        }

        return (executable, arguments)
    }

    nonisolated private static func appendArgument(
        _ argument: String,
        executable: inout String?,
        arguments: inout [String]
    ) {
        guard !argument.isEmpty else {
            return
        }

        if executable == nil {
            executable = argument
        } else {
            arguments.append(argument)
        }
    }

    nonisolated private static func resolveExecutablePath(
        _ command: String,
        cwd: String?,
        environment: [String: String]
    ) throws -> String {
        let fileManager = FileManager.default
        let expandedCommand = (command as NSString).expandingTildeInPath

        if expandedCommand.contains("/") {
            let resolvedPath: String
            if expandedCommand.hasPrefix("/") {
                resolvedPath = expandedCommand
            } else {
                let baseDirectory = cwd.flatMap { URL(fileURLWithPath: $0, isDirectory: true) }
                    ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
                resolvedPath = URL(fileURLWithPath: expandedCommand, relativeTo: baseDirectory)
                    .standardizedFileURL
                    .path
            }

            guard fileManager.fileExists(atPath: resolvedPath),
                  fileManager.isExecutableFile(atPath: resolvedPath) else {
                throw AgentTerminalDelegate.TerminalError.executableNotFound(command)
            }

            return resolvedPath
        }

        let commonPaths = [
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/opt/homebrew/bin",
            "/opt/local/bin",
        ]

        let environmentPath = environment["PATH"]
            ?? ProcessInfo.processInfo.environment["PATH"]
            ?? ""
        let candidateDirectories = environmentPath
            .split(separator: ":")
            .map(String.init)
            + commonPaths

        for directory in candidateDirectories {
            let candidate = URL(fileURLWithPath: directory, isDirectory: true)
                .appendingPathComponent(expandedCommand)
                .path
            if fileManager.fileExists(atPath: candidate),
               fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        throw AgentTerminalDelegate.TerminalError.executableNotFound(command)
    }

    nonisolated private static func shellEscaped(_ argument: String) -> String {
        guard !argument.isEmpty else {
            return "''"
        }

        let escaped = argument.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }
}
