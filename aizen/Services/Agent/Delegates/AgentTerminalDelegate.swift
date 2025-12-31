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

    /// Drain remaining data from a pipe synchronously
    private func drainPipe(_ pipe: Pipe, terminalId: String) {
        let handle = pipe.fileHandleForReading

        // Disable handler first to avoid race
        handle.readabilityHandler = nil

        // Drain any remaining data synchronously
        // Use throwing API since handle may already be closed by readabilityHandler
        do {
            while true {
                // readToEnd returns nil at EOF, throws if handle is closed
                guard let data = try handle.read(upToCount: 65536), !data.isEmpty else {
                    break
                }
                if let output = String(data: data, encoding: .utf8) {
                    appendOutput(terminalId: terminalId, output: output)
                }
            }
        } catch {
            // File handle already closed, nothing to drain
        }
    }

    /// Clean up pipe handlers to prevent file handle leaks
    private func cleanupProcessPipes(_ process: Process, terminalId: String? = nil) {
        if let outputPipe = process.standardOutput as? Pipe {
            if let id = terminalId {
                drainPipe(outputPipe, terminalId: id)
            } else {
                outputPipe.fileHandleForReading.readabilityHandler = nil
            }
            try? outputPipe.fileHandleForReading.close()
        }
        if let errorPipe = process.standardError as? Pipe {
            if let id = terminalId {
                drainPipe(errorPipe, terminalId: id)
            } else {
                errorPipe.fileHandleForReading.readabilityHandler = nil
            }
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
        var executablePath: String
        var finalArgs: [String]

        // Check if command contains shell operators that require shell interpretation
        let shellOperators = ["|", "&&", "||", ";", ">", ">>", "<", "$(", "`", "&"]
        let needsShell = shellOperators.contains { command.contains($0) }

        if needsShell {
            // Execute through shell to handle pipes, redirections, etc.
            executablePath = "/bin/sh"
            if let args = args, !args.isEmpty {
                // If args provided separately, join command + args
                finalArgs = ["-c", ([command] + args).joined(separator: " ")]
            } else {
                finalArgs = ["-c", command]
            }
        } else if args == nil || args?.isEmpty == true {
            // No args provided - check if command contains spaces/quotes
            if command.contains(" ") || command.contains("\"") {
                let (parsedExecutable, parsedArgs) = try parseCommandString(command)
                executablePath = try resolveExecutablePath(parsedExecutable)
                finalArgs = parsedArgs
            } else {
                executablePath = try resolveExecutablePath(command)
                finalArgs = []
            }
        } else {
            // Args provided separately
            executablePath = try resolveExecutablePath(command)
            finalArgs = args ?? []
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = finalArgs

        if let cwd = cwd {
            process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }

        // Always use user's shell environment as base, then merge agent-provided vars
        var envDict = ShellEnvironment.loadUserShellEnvironment()
        if let envVars = env {
            for envVar in envVars {
                envDict[envVar.name] = envVar.value
            }
        }
        process.environment = envDict

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let terminalIdValue = UUID().uuidString
        let terminalId = TerminalId(terminalIdValue)

        let state = TerminalState(process: process, outputByteLimit: outputByteLimit ?? defaultOutputByteLimit)
        terminals[terminalIdValue] = state

        // Capture output asynchronously
        // Use read(upToCount:) instead of availableData to get Swift errors instead of ObjC exceptions
        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            do {
                guard let data = try handle.read(upToCount: 65536) else {
                    handle.readabilityHandler = nil
                    try? handle.close()
                    return
                }
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    try? handle.close()
                    return
                }
                if let output = String(data: data, encoding: .utf8) {
                    Task {
                        await self?.appendOutput(terminalId: terminalIdValue, output: output)
                    }
                }
            } catch {
                // File handle closed or unavailable - clean up
                handle.readabilityHandler = nil
            }
        }

        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            do {
                guard let data = try handle.read(upToCount: 65536) else {
                    handle.readabilityHandler = nil
                    try? handle.close()
                    return
                }
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    try? handle.close()
                    return
                }
                if let output = String(data: data, encoding: .utf8) {
                    Task {
                        await self?.appendOutput(terminalId: terminalIdValue, output: output)
                    }
                }
            } catch {
                // File handle closed or unavailable - clean up
                handle.readabilityHandler = nil
            }
        }

        try process.run()
        return CreateTerminalResponse(terminalId: terminalId, _meta: nil)
    }

    /// Get output from a terminal process
    func handleTerminalOutput(terminalId: TerminalId, sessionId: String) async throws -> TerminalOutputResponse {
        guard var state = terminals[terminalId.value] else {
            throw TerminalError.terminalNotFound(terminalId.value)
        }

        guard !state.isReleased else {
            throw TerminalError.terminalReleased(terminalId.value)
        }

        // Always drain available output synchronously to avoid race with async handlers
        // This ensures we capture all data that's been read but not yet appended
        drainAvailableOutput(terminalId: terminalId.value, process: state.process)
        // Re-fetch state after draining
        state = terminals[terminalId.value] ?? state

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
            output: state.outputBuffer,
            exitStatus: exitStatus,
            truncated: state.wasTruncated,
            _meta: nil
        )
    }

    /// Wait for a terminal process to exit
    func handleTerminalWaitForExit(terminalId: TerminalId, sessionId: String) async throws -> WaitForExitResponse {
        guard let state = terminals[terminalId.value] else {
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

        // Clean up pipe handlers and drain remaining data before caching output
        cleanupProcessPipes(state.process, terminalId: terminalId.value)

        // Re-fetch state after draining (output may have been appended)
        state = terminals[terminalId.value] ?? state

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
            // Always drain available output to capture any pending data
            drainAvailableOutput(terminalId: terminalId.value, process: state.process)
            // Re-fetch state after draining
            return terminals[terminalId.value]?.outputBuffer ?? state.outputBuffer
        }
        // Then check released terminals cache
        return releasedOutputs[terminalId.value]?.output
    }

    /// Check if terminal is still running
    func isRunning(terminalId: TerminalId) -> Bool {
        return terminals[terminalId.value]?.process.isRunning ?? false
    }

    /// Drain available output without removing handlers (safe for running processes)
    /// Uses read(upToCount:) which throws Swift errors instead of availableData which throws ObjC exceptions
    private func drainAvailableOutput(terminalId: String, process: Process) {
        // Only drain if process is still running - if terminated, the handles may be invalid
        guard process.isRunning else { return }
        
        // Drain stdout non-blocking
        if let outputPipe = process.standardOutput as? Pipe {
            let handle = outputPipe.fileHandleForReading
            do {
                // Use read(upToCount:) which throws Swift errors instead of availableData
                // which throws ObjC NSException when the file handle is closed
                if let data = try handle.read(upToCount: 65536), !data.isEmpty,
                   let output = String(data: data, encoding: .utf8) {
                    appendOutput(terminalId: terminalId, output: output)
                }
            } catch {
                // File handle closed or process terminated - nothing to drain
            }
        }
        // Drain stderr non-blocking
        if let errorPipe = process.standardError as? Pipe {
            let handle = errorPipe.fileHandleForReading
            do {
                if let data = try handle.read(upToCount: 65536), !data.isEmpty,
                   let output = String(data: data, encoding: .utf8) {
                    appendOutput(terminalId: terminalId, output: output)
                }
            } catch {
                // File handle closed or process terminated - nothing to drain
            }
        }
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
            // Use read(upToCount:) to get Swift errors instead of ObjC exceptions
            if let data = try? pipe.fileHandleForReading.read(upToCount: 4096),
               let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
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
