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
    var releasedOutputs: [String: ReleasedTerminalOutput] = [:]
    var releasedOutputOrder: [String] = []
    private let defaultOutputByteLimit = 1_000_000
    let maxReleasedOutputEntries = 50

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
        var envDict = await ShellEnvironment.loadUserShellEnvironmentAsync()
        if let envVars = env {
            for envVar in envVars {
                envDict[envVar.name] = envVar.value
            }
        }

        let commandResolution = try AgentTerminalCommandResolver.resolve(
            command: command,
            args: args,
            cwd: cwd,
            environment: envDict
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: commandResolution.executablePath)
        process.arguments = commandResolution.arguments

        if let cwd = cwd {
            process.currentDirectoryURL = URL(fileURLWithPath: cwd)
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
        process.terminationHandler = { [weak self] _ in
            Task {
                await self?.handleProcessTermination(terminalId: terminalIdValue)
            }
        }

        AgentTerminalProcessIO.installReadabilityHandler(
            on: outputPipe,
            terminalId: terminalIdValue
        ) { [weak self] terminalId, output in
            await self?.appendOutput(terminalId: terminalId, data: output)
        }
        AgentTerminalProcessIO.installReadabilityHandler(
            on: errorPipe,
            terminalId: terminalIdValue
        ) { [weak self] terminalId, output in
            await self?.appendOutput(terminalId: terminalId, data: output)
        }

        do {
            try process.run()
            return CreateTerminalResponse(terminalId: terminalId, _meta: nil)
        } catch {
            terminals.removeValue(forKey: terminalIdValue)
            _ = AgentTerminalProcessIO.collectAndCloseProcessPipes(process)
            throw error
        }
    }
}
