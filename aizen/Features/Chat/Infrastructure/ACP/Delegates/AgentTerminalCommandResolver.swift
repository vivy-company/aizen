import Foundation

struct AgentTerminalCommandResolution {
    let executablePath: String
    let arguments: [String]
}

enum AgentTerminalCommandResolver {
    nonisolated private static let shellOperators = ["|", "&&", "||", ";", ">", ">>", "<", "$(", "`", "&"]

    nonisolated static func resolve(command: String, args: [String]?) throws -> AgentTerminalCommandResolution {
        let needsShell = shellOperators.contains { command.contains($0) }

        if needsShell {
            let shellArguments: [String]
            if let args, !args.isEmpty {
                shellArguments = ["-c", ([command] + args).joined(separator: " ")]
            } else {
                shellArguments = ["-c", command]
            }

            return AgentTerminalCommandResolution(
                executablePath: "/bin/sh",
                arguments: shellArguments
            )
        }

        if args == nil || args?.isEmpty == true {
            if command.contains(" ") || command.contains("\"") {
                let parsedCommand = try parseCommandString(command)
                return AgentTerminalCommandResolution(
                    executablePath: try resolveExecutablePath(parsedCommand.executable),
                    arguments: parsedCommand.arguments
                )
            }

            return AgentTerminalCommandResolution(
                executablePath: try resolveExecutablePath(command),
                arguments: []
            )
        }

        return AgentTerminalCommandResolution(
            executablePath: try resolveExecutablePath(command),
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

    nonisolated private static func resolveExecutablePath(_ command: String) throws -> String {
        let fileManager = FileManager.default

        if command.hasPrefix("/") {
            guard fileManager.fileExists(atPath: command) else {
                throw AgentTerminalDelegate.TerminalError.executableNotFound(command)
            }
            return command
        }

        let commonPaths = [
            "/usr/local/bin/\(command)",
            "/usr/bin/\(command)",
            "/bin/\(command)",
            "/opt/homebrew/bin/\(command)",
            "/opt/local/bin/\(command)",
        ]

        for path in commonPaths where fileManager.fileExists(atPath: path) {
            return path
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [command]

        let pipe = Pipe()
        process.standardOutput = pipe

        defer {
            try? pipe.fileHandleForReading.close()
        }

        do {
            try process.run()
            process.waitUntilExit()
            if let data = try? pipe.fileHandleForReading.read(upToCount: 4096),
               let path = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !path.isEmpty,
               fileManager.fileExists(atPath: path) {
                return path
            }
        } catch {
            // Ignore `which` failures and fall through to the explicit error.
        }

        throw AgentTerminalDelegate.TerminalError.executableNotFound(command)
    }
}
