import Foundation
import Darwin

public func parseArguments(_ args: [String]) throws -> ParsedArguments {
    var positionals: [String] = []
    var options: [String: String] = [:]
    var flags: Set<String> = []

    var index = 0
    while index < args.count {
        let arg = args[index]
        if arg == "--" {
            if index + 1 < args.count {
                positionals.append(contentsOf: args[(index + 1)...])
            }
            break
        }

        if arg.hasPrefix("-") {
            switch arg {
            case "-h", "--help":
                flags.insert("help")
            case "--json":
                flags.insert("json")
            case "--no-color":
                flags.insert("no-color")
            case "-f", "--force":
                flags.insert("force")
            case "-w", "--workspace":
                index += 1
                guard index < args.count else {
                    throw CLIError.invalidArguments("Missing value for --workspace")
                }
                options["workspace"] = args[index]
            case "-d", "--destination":
                index += 1
                guard index < args.count else {
                    throw CLIError.invalidArguments("Missing value for --destination")
                }
                options["destination"] = args[index]
            case "--exclude-workspace":
                index += 1
                guard index < args.count else {
                    throw CLIError.invalidArguments("Missing value for --exclude-workspace")
                }
                options["exclude-workspace"] = args[index]
            case "--name":
                index += 1
                guard index < args.count else {
                    throw CLIError.invalidArguments("Missing value for --name")
                }
                options["name"] = args[index]
            case "--path":
                index += 1
                guard index < args.count else {
                    throw CLIError.invalidArguments("Missing value for --path")
                }
                options["path"] = args[index]
            case "--color":
                index += 1
                guard index < args.count else {
                    throw CLIError.invalidArguments("Missing value for --color")
                }
                options["color"] = args[index]
            case "--worktree":
                index += 1
                guard index < args.count else {
                    throw CLIError.invalidArguments("Missing value for --worktree")
                }
                options["worktree"] = args[index]
            case "--pane":
                index += 1
                guard index < args.count else {
                    throw CLIError.invalidArguments("Missing value for --pane")
                }
                options["pane"] = args[index]
            case "-a", "--attach":
                flags.insert("attach")
            case "--cross-project":
                flags.insert("cross-project")
            case "-c", "--command":
                index += 1
                guard index < args.count else {
                    throw CLIError.invalidArguments("Missing value for --command")
                }
                options["command"] = args[index]
            default:
                throw CLIError.invalidArguments("Unknown option: \(arg)")
            }
        } else {
            positionals.append(arg)
        }
        index += 1
    }

    return ParsedArguments(positionals: positionals, options: options, flags: flags)
}

func expandPath(_ path: String) -> String {
    let expanded = (path as NSString).expandingTildeInPath
    if expanded.hasPrefix("/") {
        return URL(fileURLWithPath: expanded).standardizedFileURL.path
    }
    let cwd = FileManager.default.currentDirectoryPath
    let combined = URL(fileURLWithPath: cwd).appendingPathComponent(expanded)
    return combined.standardizedFileURL.path
}

func isTTY() -> Bool {
    return isatty(STDIN_FILENO) == 1
}

func isStdoutTTY() -> Bool {
    return isatty(STDOUT_FILENO) == 1
}

struct OutputStyle {
    let useColor: Bool

    func section(_ text: String) -> String {
        return style(text, [.bold, .cyan])
    }

    func header(_ text: String) -> String {
        return style(text, [.bold])
    }

    func label(_ text: String) -> String {
        return style(text, [.dim])
    }

    func success(_ text: String) -> String {
        return style(text, [.green])
    }

    func warning(_ text: String) -> String {
        return style(text, [.yellow])
    }

    private func style(_ text: String, _ codes: [ANSIStyle]) -> String {
        guard useColor else { return text }
        let codeString = codes.map(\.rawValue).joined(separator: ";")
        return "\u{001B}[\(codeString)m\(text)\u{001B}[0m"
    }
}

enum ANSIStyle: String {
    case bold = "1"
    case dim = "2"
    case red = "31"
    case green = "32"
    case yellow = "33"
    case blue = "34"
    case magenta = "35"
    case cyan = "36"
}

func shouldUseColor(flags: Set<String>) -> Bool {
    if flags.contains("no-color") {
        return false
    }
    let env = ProcessInfo.processInfo.environment
    if env["NO_COLOR"] != nil {
        return false
    }
    if let term = env["TERM"], term == "dumb" {
        return false
    }
    if env["FORCE_COLOR"] != nil {
        return true
    }
    return isStdoutTTY()
}

public func encodeJSON<T: Encodable>(_ payload: T, prettyPrinted: Bool = true) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = prettyPrinted ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
    return String(decoding: try encoder.encode(payload), as: UTF8.self)
}

func readLineTrimmed() -> String? {
    guard let line = readLine() else { return nil }
    return line.trimmingCharacters(in: .whitespacesAndNewlines)
}

func prompt(_ message: String) -> String? {
    print(message, terminator: "")
    fflush(stdout)
    return readLineTrimmed()
}

func formatDate(_ date: Date?) -> String {
    guard let date = date else { return "-" }
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone.current
    return formatter.string(from: date)
}

func isValidHexColor(_ value: String) -> Bool {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.count != 7 { return false }
    if !trimmed.hasPrefix("#") { return false }
    let hex = trimmed.dropFirst()
    return hex.allSatisfy { c in
        (c >= "0" && c <= "9") || (c >= "a" && c <= "f") || (c >= "A" && c <= "F")
    }
}

func normalizePath(_ path: String) -> String {
    let expanded = expandPath(path)
    return expanded.hasSuffix("/") && expanded.count > 1 ? String(expanded.dropLast()) : expanded
}

// MARK: - Tmux Utilities

func tmuxPath() -> String? {
    let paths = [
        "/opt/homebrew/bin/tmux",
        "/usr/local/bin/tmux",
        "/usr/bin/tmux"
    ]
    return paths.first { FileManager.default.isExecutableFile(atPath: $0) }
}

func isTmuxAvailable() -> Bool {
    return tmuxPath() != nil
}

func tmuxSessionExists(sessionName: String) -> Bool {
    guard let tmux = tmuxPath() else { return false }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: tmux)
    process.arguments = ["has-session", "-t", sessionName]
    process.standardError = FileHandle.nullDevice

    do {
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    } catch {
        return false
    }
}

func tmuxAttach(sessionName: String) throws {
    guard let tmux = tmuxPath() else {
        throw CLIError.tmuxNotInstalled
    }

    guard isTTY() else {
        throw CLIError.invalidArguments("tmux attach requires a terminal")
    }

    // Replace current process with tmux attach
    let args = [tmux, "attach", "-t", sessionName]
    let cArgs = args.map { strdup($0) } + [nil]

    execv(tmux, cArgs)

    // If execv returns, it failed
    throw CLIError.ioError("Failed to attach to tmux session")
}

func findAizenAppBundle() -> URL? {
    let candidates = [
        "/Applications/Aizen.app",
        "/Applications/Aizen Nightly.app",
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Aizen.app").path,
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Aizen Nightly.app").path
    ]

    return candidates.lazy
        .map(URL.init(fileURLWithPath:))
        .first { FileManager.default.fileExists(atPath: $0.path) }
}
