//
//  AgentTerminalDelegate.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import Foundation

/// Tracks state of a single terminal
private struct TerminalState {
    let process: Process
    var outputBuffer: String = ""
    var outputByteLimit: Int?
    var lastReadIndex: Int = 0
    var isReleased: Bool = false
    var wasTruncated: Bool = false
    var exitWaiters: [CheckedContinuation<(exitCode: Int?, signal: String?), Never>] = []
}

/// Cached output for released terminals (for UI display)
private struct ReleasedTerminalOutput {
    let output: String
    let exitCode: Int?
}

/// Actor responsible for handling terminal operations for agent sessions
actor AgentTerminalDelegate {

    // MARK: - Errors

    enum TerminalError: LocalizedError {
        case terminalNotFound(String)
        case terminalReleased(String)
        case executableNotFound(String)
        case commandParsingFailed(String)

        var errorDescription: String? {
            switch self {
            case .terminalNotFound(let id):
                return "Terminal with ID '\(id)' not found"
            case .terminalReleased(let id):
                return "Terminal with ID '\(id)' has been released"
            case .executableNotFound(let path):
                return "Executable not found: '\(path)'"
            case .commandParsingFailed(let command):
                return "Failed to parse command string: '\(command)'"
            }
        }
    }

    // MARK: - Private Properties

    private var terminals: [String: TerminalState] = [:]
    private var releasedOutputs: [String: ReleasedTerminalOutput] = [:]
    private var releasedOutputOrder: [String] = []
    private let defaultOutputByteLimit = 1_000_000
    private let maxReleasedOutputEntries = 50

    // MARK: - Private Cleanup

    /// Clean up pipe handlers to prevent file handle leaks
    private func cleanupProcessPipes(_ process: Process) {
        if let outputPipe = process.standardOutput as? Pipe {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            try? outputPipe.fileHandleForReading.close()
        }
        if let errorPipe = process.standardError as? Pipe {
            errorPipe.fileHandleForReading.readabilityHandler = nil
            try? errorPipe.fileHandleForReading.close()
        }
    }

    // MARK: - Initialization

    init() {}

    // MARK: - Terminal Operations

    /// Create a new terminal process
    func handleTerminalCreate(
        command: String,
        sessionId: String,
        args: [String]?,
        cwd: String?,
        env: [EnvVariable]?,
        outputByteLimit: Int?
    ) async throws -> CreateTerminalResponse {
        // Determine executable and final args
        var executable = command
        var finalArgs = args ?? []

        // If args is empty/nil but command contains spaces/quotes, parse the command string
        if (args == nil || args?.isEmpty == true) && (command.contains(" ") || command.contains("\"")) {
            let (parsedExecutable, parsedArgs) = try parseCommandString(command)
            executable = parsedExecutable
            finalArgs = parsedArgs
        }

        // Resolve executable path
        let executablePath = try resolveExecutablePath(executable)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = finalArgs

        if let cwd = cwd {
            process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }

        if let envVars = env {
            var envDict = [String: String]()
            for envVar in envVars {
                envDict[envVar.name] = envVar.value
            }
            process.environment = envDict
        }

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let terminalIdValue = UUID().uuidString
        let terminalId = TerminalId(terminalIdValue)

        let state = TerminalState(process: process, outputByteLimit: outputByteLimit ?? defaultOutputByteLimit)
        terminals[terminalIdValue] = state

        // Capture output asynchronously
        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                try? handle.close()
                return
            }
            if !data.isEmpty, let output = String(data: data, encoding: .utf8) {
                Task {
                    await self?.appendOutput(terminalId: terminalIdValue, output: output)
                }
            }
        }

        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                try? handle.close()
                return
            }
            if !data.isEmpty, let output = String(data: data, encoding: .utf8) {
                Task {
                    await self?.appendOutput(terminalId: terminalIdValue, output: output)
                }
            }
        }

        try process.run()
        return CreateTerminalResponse(terminalId: terminalId, _meta: nil)
    }

    /// Get output from a terminal process
    func handleTerminalOutput(terminalId: TerminalId, sessionId: String) async throws -> TerminalOutputResponse {
        guard let state = terminals[terminalId.value] else {
            throw TerminalError.terminalNotFound(terminalId.value)
        }

        guard !state.isReleased else {
            throw TerminalError.terminalReleased(terminalId.value)
        }

        let output = state.outputBuffer
        let exitStatus: TerminalExitStatus?
        if state.process.isRunning {
            exitStatus = nil
        } else {
            exitStatus = TerminalExitStatus(
                exitCode: Int(state.process.terminationStatus),
                signal: nil,
                _meta: nil
            )
        }

        return TerminalOutputResponse(
            output: output,
            exitStatus: exitStatus,
            truncated: state.wasTruncated,
            _meta: nil
        )
    }

    /// Wait for a terminal process to exit
    func handleTerminalWaitForExit(terminalId: TerminalId, sessionId: String) async throws -> WaitForExitResponse {
        guard var state = terminals[terminalId.value] else {
            throw TerminalError.terminalNotFound(terminalId.value)
        }

        guard !state.isReleased else {
            throw TerminalError.terminalReleased(terminalId.value)
        }

        // If already exited, return immediately
        if !state.process.isRunning {
            return WaitForExitResponse(
                exitCode: Int(state.process.terminationStatus),
                signal: nil,
                _meta: nil
            )
        }

        // Wait for exit
        let result = await withCheckedContinuation { continuation in
            var waiterState = state
            waiterState.exitWaiters.append(continuation)
            terminals[terminalId.value] = waiterState

            // Start monitoring process in background
            Task {
                await self.monitorProcessExit(terminalId: terminalId)
            }
        }

        return WaitForExitResponse(
            exitCode: result.exitCode,
            signal: result.signal,
            _meta: nil
        )
    }

    /// Kill a terminal process
    func handleTerminalKill(terminalId: TerminalId, sessionId: String) async throws -> KillTerminalResponse {
        guard var state = terminals[terminalId.value] else {
            throw TerminalError.terminalNotFound(terminalId.value)
        }

        guard !state.isReleased else {
            throw TerminalError.terminalReleased(terminalId.value)
        }

        if state.process.isRunning {
            state.process.terminate()
            // Wait for process to actually terminate
            state.process.waitUntilExit()
        }

        // Wake up any waiters
        let exitCode = Int(state.process.terminationStatus)
        for waiter in state.exitWaiters {
            waiter.resume(returning: (exitCode, nil))
        }
        state.exitWaiters.removeAll()
        terminals[terminalId.value] = state

        return KillTerminalResponse(success: true, _meta: nil)
    }

    /// Release a terminal process
    func handleTerminalRelease(terminalId: TerminalId, sessionId: String) async throws -> ReleaseTerminalResponse {
        guard var state = terminals[terminalId.value] else {
            throw TerminalError.terminalNotFound(terminalId.value)
        }

        // Kill if still running and wait for termination
        if state.process.isRunning {
            state.process.terminate()
            state.process.waitUntilExit()
        }

        // Clean up pipe handlers to prevent leaks
        cleanupProcessPipes(state.process)

        // Wake up any waiters
        let exitCode = Int(state.process.terminationStatus)
        for waiter in state.exitWaiters {
            waiter.resume(returning: (exitCode, nil))
        }

        // Cache output for UI display before removing
        cacheReleasedOutput(
            terminalId: terminalId.value,
            output: state.outputBuffer,
            exitCode: exitCode
        )

        // Mark as released and clean up
        state.isReleased = true
        state.exitWaiters.removeAll()
        terminals.removeValue(forKey: terminalId.value)

        return ReleaseTerminalResponse(success: true, _meta: nil)
    }

    /// Clean up all terminals
    func cleanup() async {
        for (_, state) in terminals {
            if state.process.isRunning {
                state.process.terminate()
                state.process.waitUntilExit()
            }
            // Clean up pipe handlers to prevent leaks
            cleanupProcessPipes(state.process)
            // Wake up any waiters
            let exitCode = Int(state.process.terminationStatus)
            for waiter in state.exitWaiters {
                waiter.resume(returning: (exitCode, nil))
            }
        }
        terminals.removeAll()
        releasedOutputs.removeAll()
        releasedOutputOrder.removeAll()
    }

    // MARK: - Public Helpers

    /// Get terminal output for display (checks both active and released terminals)
    func getOutput(terminalId: TerminalId) -> String? {
        // First check active terminals
        if let state = terminals[terminalId.value] {
            return state.outputBuffer
        }
        // Then check released terminals cache
        return releasedOutputs[terminalId.value]?.output
    }

    /// Check if terminal is still running
    func isRunning(terminalId: TerminalId) -> Bool {
        return terminals[terminalId.value]?.process.isRunning ?? false
    }

    // MARK: - Private Helpers

    private func appendOutput(terminalId: String, output: String) {
        guard var state = terminals[terminalId] else { return }

        state.outputBuffer += output

        // Apply byte limit truncation
        if let limit = state.outputByteLimit, state.outputBuffer.count > limit {
            let startIndex = state.outputBuffer.index(
                state.outputBuffer.startIndex,
                offsetBy: state.outputBuffer.count - limit
            )
            state.outputBuffer = String(state.outputBuffer[startIndex...])
            state.wasTruncated = true
        }

        terminals[terminalId] = state
    }

    private func cacheReleasedOutput(terminalId: String, output: String, exitCode: Int) {
        releasedOutputs[terminalId] = ReleasedTerminalOutput(output: output, exitCode: exitCode)
        releasedOutputOrder.removeAll { $0 == terminalId }
        releasedOutputOrder.append(terminalId)

        while releasedOutputOrder.count > maxReleasedOutputEntries,
              let oldest = releasedOutputOrder.first {
            releasedOutputOrder.removeFirst()
            releasedOutputs.removeValue(forKey: oldest)
        }
    }

    private func monitorProcessExit(terminalId: TerminalId) async {
        guard let state = terminals[terminalId.value] else { return }
        let process = state.process

        // Poll for process exit
        while process.isRunning {
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            // Check if terminal was released/killed while waiting
            guard terminals[terminalId.value] != nil else { return }
        }

        // Process exited, wake up waiters if not already handled by kill/release
        guard var currentState = terminals[terminalId.value],
              !currentState.exitWaiters.isEmpty else { return }

        let exitCode = Int(process.terminationStatus)
        for waiter in currentState.exitWaiters {
            waiter.resume(returning: (exitCode, nil))
        }
        currentState.exitWaiters.removeAll()
        terminals[terminalId.value] = currentState
    }

    /// Parse a shell command string into executable and arguments
    /// Handles quoted strings and escaped quotes properly
    private func parseCommandString(_ command: String) throws -> (String, [String]) {
        var executable: String?
        var args: [String] = []
        var currentArg = ""
        var inQuotes = false
        var escapeNext = false

        for char in command {
            if escapeNext {
                currentArg.append(char)
                escapeNext = false
                continue
            }

            if char == "\\" {
                escapeNext = true
                continue
            }

            if char == "\"" {
                inQuotes = !inQuotes
                continue
            }

            if char == " " && !inQuotes {
                if !currentArg.isEmpty {
                    if executable == nil {
                        executable = currentArg
                    } else {
                        args.append(currentArg)
                    }
                    currentArg = ""
                }
                continue
            }

            currentArg.append(char)
        }

        // Add final argument if any
        if !currentArg.isEmpty {
            if executable == nil {
                executable = currentArg
            } else {
                args.append(currentArg)
            }
        }

        guard let exec = executable, !exec.isEmpty else {
            throw TerminalError.commandParsingFailed(command)
        }

        return (exec, args)
    }

    /// Resolve executable path from command name
    /// Handles both absolute paths and command names
    private func resolveExecutablePath(_ command: String) throws -> String {
        let fileManager = FileManager.default

        // If it's an absolute path and exists, use it
        if command.hasPrefix("/") {
            if fileManager.fileExists(atPath: command) {
                return command
            }
            throw TerminalError.executableNotFound(command)
        }

        // Common binary paths on macOS
        let commonPaths = [
            "/usr/local/bin/\(command)",
            "/usr/bin/\(command)",
            "/bin/\(command)",
            "/opt/homebrew/bin/\(command)",
            "/opt/local/bin/\(command)",
        ]

        for path in commonPaths {
            if fileManager.fileExists(atPath: path) {
                return path
            }
        }

        // Try using 'which' to find the command
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
            let data = pipe.fileHandleForReading.availableData
            if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                if !path.isEmpty && FileManager.default.fileExists(atPath: path) {
                    return path
                }
            }
        } catch {
            // Fallback if 'which' fails
        }

        // If nothing found, throw error
        throw TerminalError.executableNotFound(command)
    }
}
