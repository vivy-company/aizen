//
//  ACPProcessManager.swift
//  aizen
//
//  Manages subprocess lifecycle, I/O pipes, and message serialization
//

import Foundation
import os.log

actor ACPProcessManager {
    // MARK: - Properties

    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?

    private var readBuffer: Data = Data()

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let logger: Logger

    // Callback for incoming data
    private var onDataReceived: ((Data) async -> Void)?
    private var onTermination: ((Int32) async -> Void)?

    // MARK: - Initialization

    init(encoder: JSONEncoder, decoder: JSONDecoder) {
        self.encoder = encoder
        self.decoder = decoder
        self.logger = Logger.forCategory("ACPProcessManager")
    }

    // MARK: - Process Lifecycle

    func launch(agentPath: String, arguments: [String] = [], workingDirectory: String? = nil) throws {
        guard process == nil else {
            // Process already running - this is an invalid state
            throw ACPClientError.invalidResponse
        }

        let proc = Process()

        // Resolve symlinks to get the actual file
        let resolvedPath = (try? FileManager.default.destinationOfSymbolicLink(atPath: agentPath)) ?? agentPath
        let actualPath = resolvedPath.hasPrefix("/") ? resolvedPath : ((agentPath as NSString).deletingLastPathComponent as NSString).appendingPathComponent(resolvedPath)

        // Check if this is a Node.js script by reading only the first line (shebang)
        // Only read up to 64 bytes to check for "#!/usr/bin/env node" - much faster than reading entire file
        let isNodeScript: Bool = {
            guard let handle = FileHandle(forReadingAtPath: actualPath) else { return false }
            defer { try? handle.close() }
            guard let data = try? handle.read(upToCount: 64),
                  let firstLine = String(data: data, encoding: .utf8) else { return false }
            return firstLine.hasPrefix("#!/usr/bin/env node")
        }()

        if isNodeScript {
            // Try to find node in multiple locations
            let searchPaths = [
                (agentPath as NSString).deletingLastPathComponent, // Original directory (for symlinks like /opt/homebrew/bin)
                (actualPath as NSString).deletingLastPathComponent, // Actual file directory
                "/opt/homebrew/bin",
                "/usr/local/bin",
                "/usr/bin"
            ]

            var foundNode: String?
            for searchPath in searchPaths {
                let nodePath = (searchPath as NSString).appendingPathComponent("node")
                if FileManager.default.fileExists(atPath: nodePath) {
                    foundNode = nodePath
                    break
                }
            }

            if let nodePath = foundNode {
                proc.executableURL = URL(fileURLWithPath: nodePath)
                proc.arguments = [actualPath] + arguments
            } else {
                proc.executableURL = URL(fileURLWithPath: agentPath)
                proc.arguments = arguments
            }
        } else {
            proc.executableURL = URL(fileURLWithPath: agentPath)
            proc.arguments = arguments
        }

        // Load user's shell environment for full access to their commands
        var environment = ShellEnvironment.loadUserShellEnvironment()

        // Respect requested working directory: set both cwd and PWD/OLDPWD
        if let workingDirectory, !workingDirectory.isEmpty {
            environment["PWD"] = workingDirectory
            environment["OLDPWD"] = workingDirectory
            proc.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }

        // Get the directory containing the agent executable (for node, etc.)
        let agentDir = (agentPath as NSString).deletingLastPathComponent

        // Prepend agent directory to PATH (highest priority)
        if let existingPath = environment["PATH"] {
            environment["PATH"] = "\(agentDir):\(existingPath)"
        } else {
            environment["PATH"] = agentDir
        }

        proc.environment = environment

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()

        proc.standardInput = stdin
        proc.standardOutput = stdout
        proc.standardError = stderr

        stdinPipe = stdin
        stdoutPipe = stdout
        stderrPipe = stderr

        proc.terminationHandler = { [weak self] process in
            Task {
                await self?.handleTermination(exitCode: process.terminationStatus)
            }
        }

        try proc.run()
        process = proc

        startReading()
        startReadingStderr()
    }

    func isRunning() -> Bool {
        return process?.isRunning == true
    }

    func terminate() {
        // Clear readability handlers first
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil

        // Close file handles explicitly
        try? stdinPipe?.fileHandleForWriting.close()
        try? stdoutPipe?.fileHandleForReading.close()
        try? stderrPipe?.fileHandleForReading.close()

        process?.terminate()
        process = nil

        stdinPipe = nil
        stdoutPipe = nil
        stderrPipe = nil

        readBuffer.removeAll()
    }

    // MARK: - I/O Operations

    func writeMessage<T: Encodable>(_ message: T) async throws {
        guard let stdin = stdinPipe?.fileHandleForWriting else {
            throw ACPClientError.processNotRunning
        }

        let data = try encoder.encode(message)

        var lineData = data
        lineData.append(0x0A) // newline

        try stdin.write(contentsOf: lineData)
    }

    // MARK: - Callbacks

    func setDataReceivedCallback(_ callback: @escaping (Data) async -> Void) {
        self.onDataReceived = callback
    }

    func setTerminationCallback(_ callback: @escaping (Int32) async -> Void) {
        self.onTermination = callback
    }

    // MARK: - Private Methods

    private func startReading() {
        guard let stdout = stdoutPipe?.fileHandleForReading else { return }

        // Use readabilityHandler for non-blocking async I/O
        stdout.readabilityHandler = { [weak self] handle in
            let data = handle.availableData

            guard !data.isEmpty else {
                // EOF or pipe closed
                handle.readabilityHandler = nil
                return
            }

            Task {
                await self?.processIncomingData(data)
            }
        }
    }

    private func startReadingStderr() {
        guard let stderr = stderrPipe?.fileHandleForReading else { return }

        stderr.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                // EOF or pipe closed - clean up handler
                handle.readabilityHandler = nil
                return
            }
            // Discard stderr output
        }
    }

    private func processIncomingData(_ data: Data) async {
        readBuffer.append(data)

        // Process complete lines
        while let newlineIndex = readBuffer.firstIndex(of: 0x0A) {
            let lineData = readBuffer[..<newlineIndex]
            readBuffer.removeSubrange(...newlineIndex)

            await onDataReceived?(Data(lineData))
        }
    }

    private func handleTermination(exitCode: Int32) async {
        await drainAndClosePipes()
        logger.info("Agent process terminated with code: \(exitCode)")
        await onTermination?(exitCode)
    }

    private func drainAndClosePipes() async {
        if let stdoutHandle = stdoutPipe?.fileHandleForReading {
            stdoutHandle.readabilityHandler = nil
            let remaining = stdoutHandle.readDataToEndOfFile()
            if !remaining.isEmpty {
                await processIncomingData(remaining)
            }
            try? stdoutHandle.close()
        }

        if let stderrHandle = stderrPipe?.fileHandleForReading {
            stderrHandle.readabilityHandler = nil
            _ = stderrHandle.readDataToEndOfFile()
            try? stderrHandle.close()
        }

        try? stdinPipe?.fileHandleForWriting.close()

        stdinPipe = nil
        stdoutPipe = nil
        stderrPipe = nil
        process = nil
        readBuffer.removeAll()
    }
}
