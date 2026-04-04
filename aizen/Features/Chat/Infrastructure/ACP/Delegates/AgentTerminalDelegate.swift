//
//  AgentTerminalDelegate.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import ACP
import Foundation

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

    var terminals: [String: TerminalState] = [:]
    private var releasedOutputs: [String: ReleasedTerminalOutput] = [:]
    private var releasedOutputOrder: [String] = []
    private let defaultOutputByteLimit = 1_000_000
    private let maxReleasedOutputEntries = 50

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
        let commandResolution = try AgentTerminalCommandResolver.resolve(
            command: command,
            args: args
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: commandResolution.executablePath)
        process.arguments = commandResolution.arguments

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

        AgentTerminalProcessIO.installReadabilityHandler(
            on: outputPipe,
            terminalId: terminalIdValue
        ) { [weak self] terminalId, output in
            await self?.appendOutput(terminalId: terminalId, output: output)
        }
        AgentTerminalProcessIO.installReadabilityHandler(
            on: errorPipe,
            terminalId: terminalIdValue
        ) { [weak self] terminalId, output in
            await self?.appendOutput(terminalId: terminalId, output: output)
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
        resumeExitWaiters(in: &state, exitCode: exitCode)
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
        AgentTerminalProcessIO.cleanupProcessPipes(
            state.process,
            terminalId: terminalId.value
        ) { [weak self] drainedTerminalId, output in
            await self?.appendOutput(terminalId: drainedTerminalId, output: output)
        }

        // Re-fetch state after draining (output may have been appended)
        state = terminals[terminalId.value] ?? state

        // Wake up any waiters
        let exitCode = Int(state.process.terminationStatus)
        resumeExitWaiters(in: &state, exitCode: exitCode)

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
            AgentTerminalProcessIO.cleanupProcessPipes(state.process)
            // Wake up any waiters
            let exitCode = Int(state.process.terminationStatus)
            var currentState = state
            resumeExitWaiters(in: &currentState, exitCode: exitCode)
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
        AgentTerminalProcessIO.drainAvailableOutput(
            terminalId: terminalId,
            process: process
        ) { [weak self] drainedTerminalId, output in
            await self?.appendOutput(terminalId: drainedTerminalId, output: output)
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
}
