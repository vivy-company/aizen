import Foundation
import Darwin

func parseArguments(_ args: [String]) throws -> ParsedArguments {
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
            case "-a", "--attach":
                flags.insert("attach")
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

// MARK: - Interactive Picker

struct SessionInfo {
    let workspaceName: String
    let repositoryName: String
    let worktreeBranch: String
    let paneCount: Int
    let focusedPaneId: String?
    let activePaneIds: [String]
    let sessionId: UUID
    let worktreeId: UUID
    let repositoryId: UUID
    let workspaceId: UUID

    var displayName: String {
        "\(workspaceName) / \(repositoryName) / \(worktreeBranch)"
    }

    var detailText: String {
        paneCount == 1 ? "1 pane" : "\(paneCount) panes"
    }
}

class InteractivePicker {
    private let items: [SessionInfo]
    private var selectedIndex: Int = 0
    private let style: OutputStyle
    private var originalTermios: termios?

    init(items: [SessionInfo], style: OutputStyle) {
        self.items = items
        self.style = style
    }

    func run() throws -> SessionInfo? {
        guard !items.isEmpty else { return nil }
        guard isTTY() else {
            throw CLIError.invalidArguments("Interactive picker requires a terminal")
        }

        enableRawMode()
        defer { disableRawMode() }

        hideCursor()
        defer { showCursor() }

        render()

        while true {
            guard let key = readKey() else { continue }

            switch key {
            case .up, .k:
                if selectedIndex > 0 {
                    selectedIndex -= 1
                    render()
                }
            case .down, .j:
                if selectedIndex < items.count - 1 {
                    selectedIndex += 1
                    render()
                }
            case .enter:
                clearPicker()
                return items[selectedIndex]
            case .escape, .q:
                clearPicker()
                return nil
            default:
                break
            }
        }
    }

    private func render() {
        // Move cursor to start and clear
        print("\u{1B}[H\u{1B}[J", terminator: "")

        print(style.section("Select session to attach:"))
        print("")

        for (index, item) in items.enumerated() {
            let prefix = index == selectedIndex ? style.success(">") : " "
            let name = index == selectedIndex ? style.header(item.displayName) : item.displayName
            let detail = style.label("(\(item.detailText))")
            print("\(prefix) \(name) \(detail)")
        }

        print("")
        print(style.label("↑/↓ navigate • Enter select • Esc cancel"))

        fflush(stdout)
    }

    private func clearPicker() {
        // Clear the picker area
        let lineCount = items.count + 4  // header + items + footer + blank lines
        print("\u{1B}[\(lineCount)A\u{1B}[J", terminator: "")
        fflush(stdout)
    }

    private func enableRawMode() {
        var raw = termios()
        tcgetattr(STDIN_FILENO, &raw)
        originalTermios = raw

        raw.c_lflag &= ~UInt(ICANON | ECHO)
        // c_cc indices: 16 = VMIN (min chars to read), 17 = VTIME (timeout in deciseconds)
        // These are macOS-specific indices for the control characters array
        raw.c_cc.16 = 1
        raw.c_cc.17 = 0

        tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)
    }

    private func disableRawMode() {
        if var original = originalTermios {
            tcsetattr(STDIN_FILENO, TCSAFLUSH, &original)
        }
    }

    private func hideCursor() {
        print("\u{1B}[?25l", terminator: "")
        fflush(stdout)
    }

    private func showCursor() {
        print("\u{1B}[?25h", terminator: "")
        fflush(stdout)
    }

    private enum Key {
        case up, down, enter, escape, k, j, q, other
    }

    private func readKey() -> Key? {
        var buffer = [UInt8](repeating: 0, count: 3)
        let bytesRead = read(STDIN_FILENO, &buffer, 3)

        guard bytesRead > 0 else { return nil }

        if bytesRead == 1 {
            switch buffer[0] {
            case 0x0A, 0x0D: return .enter      // Enter
            case 0x1B: return .escape           // Escape
            case 0x6A: return .j                // j
            case 0x6B: return .k                // k
            case 0x71: return .q                // q
            default: return .other
            }
        }

        if bytesRead == 3 && buffer[0] == 0x1B && buffer[1] == 0x5B {
            switch buffer[2] {
            case 0x41: return .up               // Up arrow
            case 0x42: return .down             // Down arrow
            default: return .other
            }
        }

        return .other
    }
}

struct PaneInfo {
    let paneId: String
    let index: Int
    let isFocused: Bool

    var displayName: String {
        let focusMarker = isFocused ? " (focused)" : ""
        return "Pane \(index + 1)\(focusMarker)"
    }

    var shortId: String {
        String(paneId.prefix(8))
    }
}

class PanePicker {
    private let panes: [PaneInfo]
    private var selectedIndex: Int
    private let style: OutputStyle
    private let sessionName: String
    private var originalTermios: termios?

    init(paneIds: [String], focusedPaneId: String?, sessionName: String, style: OutputStyle) {
        self.panes = paneIds.enumerated().map { index, paneId in
            PaneInfo(paneId: paneId, index: index, isFocused: paneId == focusedPaneId)
        }
        self.sessionName = sessionName
        self.style = style
        // Start with focused pane selected
        self.selectedIndex = panes.firstIndex { $0.isFocused } ?? 0
    }

    func run() throws -> String? {
        guard !panes.isEmpty else { return nil }
        guard isTTY() else {
            throw CLIError.invalidArguments("Interactive picker requires a terminal")
        }

        enableRawMode()
        defer { disableRawMode() }

        hideCursor()
        defer { showCursor() }

        render()

        while true {
            guard let key = readKey() else { continue }

            switch key {
            case .up, .k:
                if selectedIndex > 0 {
                    selectedIndex -= 1
                    render()
                }
            case .down, .j:
                if selectedIndex < panes.count - 1 {
                    selectedIndex += 1
                    render()
                }
            case .enter:
                clearPicker()
                return panes[selectedIndex].paneId
            case .escape, .q:
                clearPicker()
                return nil
            default:
                break
            }
        }
    }

    private func render() {
        print("\u{1B}[H\u{1B}[J", terminator: "")

        print(style.section("Select pane to attach:"))
        print(style.label(sessionName))
        print("")

        for (index, pane) in panes.enumerated() {
            let prefix = index == selectedIndex ? style.success(">") : " "
            let name = index == selectedIndex ? style.header(pane.displayName) : pane.displayName
            let detail = style.label("[\(pane.shortId)]")
            print("\(prefix) \(name) \(detail)")
        }

        print("")
        print(style.label("↑/↓ navigate • Enter select • Esc cancel"))

        fflush(stdout)
    }

    private func clearPicker() {
        let lineCount = panes.count + 5
        print("\u{1B}[\(lineCount)A\u{1B}[J", terminator: "")
        fflush(stdout)
    }

    private func enableRawMode() {
        var raw = termios()
        tcgetattr(STDIN_FILENO, &raw)
        originalTermios = raw

        raw.c_lflag &= ~UInt(ICANON | ECHO)
        raw.c_cc.16 = 1
        raw.c_cc.17 = 0

        tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)
    }

    private func disableRawMode() {
        if var original = originalTermios {
            tcsetattr(STDIN_FILENO, TCSAFLUSH, &original)
        }
    }

    private func hideCursor() {
        print("\u{1B}[?25l", terminator: "")
        fflush(stdout)
    }

    private func showCursor() {
        print("\u{1B}[?25h", terminator: "")
        fflush(stdout)
    }

    private enum Key {
        case up, down, enter, escape, k, j, q, other
    }

    private func readKey() -> Key? {
        var buffer = [UInt8](repeating: 0, count: 3)
        let bytesRead = read(STDIN_FILENO, &buffer, 3)

        guard bytesRead > 0 else { return nil }

        if bytesRead == 1 {
            switch buffer[0] {
            case 0x0A, 0x0D: return .enter
            case 0x1B: return .escape
            case 0x6A: return .j
            case 0x6B: return .k
            case 0x71: return .q
            default: return .other
            }
        }

        if bytesRead == 3 && buffer[0] == 0x1B && buffer[1] == 0x5B {
            switch buffer[2] {
            case 0x41: return .up
            case 0x42: return .down
            default: return .other
            }
        }

        return .other
    }
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

func tmuxSessionExists(paneId: String) -> Bool {
    guard let tmux = tmuxPath() else { return false }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: tmux)
    process.arguments = ["has-session", "-t", "aizen-\(paneId)"]
    process.standardError = FileHandle.nullDevice

    do {
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    } catch {
        return false
    }
}

func tmuxAttach(paneId: String) throws {
    guard let tmux = tmuxPath() else {
        throw CLIError.tmuxNotInstalled
    }

    guard isTTY() else {
        throw CLIError.invalidArguments("tmux attach requires a terminal")
    }

    let sessionName = "aizen-\(paneId)"

    // Replace current process with tmux attach
    let args = [tmux, "attach", "-t", sessionName]
    let cArgs = args.map { strdup($0) } + [nil]

    execv(tmux, cArgs)

    // If execv returns, it failed
    throw CLIError.ioError("Failed to attach to tmux session")
}

func tmuxCreateSession(paneId: String, workingDirectory: String, command: String? = nil) throws {
    guard let tmux = tmuxPath() else {
        throw CLIError.tmuxNotInstalled
    }

    let sessionName = "aizen-\(paneId)"
    let configPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".aizen/tmux.conf").path

    // Ensure config exists
    ensureTmuxConfig()

    var args = [
        tmux,
        "-f", configPath,
        "new-session",
        "-d",  // detached
        "-s", sessionName,
        "-c", workingDirectory
    ]

    // If command specified, add it
    if let command = command {
        args.append(command)
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: tmux)
    process.arguments = Array(args.dropFirst())  // Remove tmux path from args

    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
        throw CLIError.ioError("Failed to create tmux session")
    }
}

private func ensureTmuxConfig() {
    let aizenDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".aizen")
    let configFile = aizenDir.appendingPathComponent("tmux.conf")

    // Create ~/.aizen if needed
    try? FileManager.default.createDirectory(at: aizenDir, withIntermediateDirectories: true)

    // Only create if doesn't exist (don't overwrite user customizations from CLI)
    guard !FileManager.default.fileExists(atPath: configFile.path) else { return }

    let config = """
    # Aizen tmux configuration
    # This file is auto-generated - changes may be overwritten by Aizen app

    # Enable hyperlinks (OSC 8)
    set -as terminal-features ",*:hyperlinks"

    # Allow OSC sequences to pass through
    set -g allow-passthrough on

    # Hide status bar
    set -g status off

    # Increase scrollback buffer
    set -g history-limit 10000

    # Enable mouse support
    set -g mouse on

    # Set default terminal with true color support
    set -g default-terminal "xterm-256color"
    set -ag terminal-overrides ",xterm-256color:RGB"
    """

    try? config.write(to: configFile, atomically: true, encoding: .utf8)
}

// MARK: - Split Layout Creation

func createSinglePaneSplitLayout(paneId: String) -> String {
    // Create a leaf node JSON matching app's format: {"type":"leaf","paneId":"UUID"}
    let layout: [String: Any] = ["type": "leaf", "paneId": paneId]
    guard let data = try? JSONSerialization.data(withJSONObject: layout),
          let json = String(data: data, encoding: .utf8) else {
        return "{\"type\":\"leaf\",\"paneId\":\"\(paneId)\"}"
    }
    return json
}

// MARK: - Split Layout Parsing

func parsePaneIds(from splitLayout: String?) -> [String] {
    guard let json = splitLayout,
          let data = json.data(using: .utf8) else {
        return []
    }

    var paneIds: [String] = []
    extractPaneIds(from: data, into: &paneIds)
    return paneIds
}

private func extractPaneIds(from data: Data, into paneIds: inout [String]) {
    guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return
    }

    // Check if it's a leaf node (app format: {"type":"leaf","paneId":"..."})
    if let paneId = obj["paneId"] as? String {
        paneIds.append(paneId)
        return
    }

    // Handle nested leaf format (old CLI format: {"leaf":{"paneId":"..."}})
    if let leaf = obj["leaf"] as? [String: Any],
       let paneId = leaf["paneId"] as? String {
        paneIds.append(paneId)
        return
    }

    // Check if it's a split node (app format with left/right at top level)
    if let left = obj["left"], let right = obj["right"] {
        if let leftData = try? JSONSerialization.data(withJSONObject: left),
           let rightData = try? JSONSerialization.data(withJSONObject: right) {
            extractPaneIds(from: leftData, into: &paneIds)
            extractPaneIds(from: rightData, into: &paneIds)
        }
        return
    }

    // Check if it's a split node (nested format: {"split":{"left":...,"right":...}})
    if let split = obj["split"] as? [String: Any] {
        if let leftData = try? JSONSerialization.data(withJSONObject: split["left"] as Any),
           let rightData = try? JSONSerialization.data(withJSONObject: split["right"] as Any) {
            extractPaneIds(from: leftData, into: &paneIds)
            extractPaneIds(from: rightData, into: &paneIds)
        }
    }
}
