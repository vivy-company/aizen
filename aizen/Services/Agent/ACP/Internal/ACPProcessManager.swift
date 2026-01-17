//
//  ACPProcessManager.swift
//  aizen
//
//  Manages subprocess lifecycle, I/O pipes, and message serialization
//

import Foundation
import Darwin
import os.log

actor ACPProcessManager {
    // MARK: - Properties

    private var process: Process?
    private var processGroupId: pid_t?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?

    private var readBuffer: Data = Data()
    private var largeBufferDumpCount: Int = 0
    private var lastLargeBufferDumpSize: Int = 0

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let logger: Logger

    private static let largeBufferWarningThreshold = 200000
    private static let largeBufferDumpMinGrowth = 8192
    private static let maxLargeBufferDumps = 3

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

    func launch(agentPath: String, arguments: [String] = [], workingDirectory: String? = nil) async throws {
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
        // Use async version to ensure we get the complete environment with all user vars (e.g., OPENCODE=1)
        var environment = await ShellEnvironment.loadUserShellEnvironmentAsync()

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
        processGroupId = nil
        if proc.processIdentifier > 0 {
            let pid = proc.processIdentifier
            if setpgid(pid, pid) == 0 {
                processGroupId = pid
            } else {
                logger.warning("Failed to set process group for pid=\(pid): \(String(cString: strerror(errno)))")
            }
        }
        if proc.processIdentifier > 0 {
            let pid = proc.processIdentifier
            let pgid = processGroupId
            Task {
                await ACPProcessRegistry.shared.recordProcess(pid: pid, pgid: pgid, agentPath: actualPath)
            }
        }

        startReading()
        startReadingStderr()
    }

    func isRunning() -> Bool {
        return process?.isRunning == true
    }

    func terminate() async {
        let proc = process
        let pgid = processGroupId
        let pid = proc?.processIdentifier

        // Clear readability handlers first
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil

        // Close file handles explicitly
        try? stdinPipe?.fileHandleForWriting.close()
        try? stdoutPipe?.fileHandleForReading.close()
        try? stderrPipe?.fileHandleForReading.close()

        if let proc, proc.isRunning {
            if let pgid {
                _ = killpg(pgid, SIGTERM)
            } else {
                proc.terminate()
            }
        }

        if let proc {
            let exited = await waitForExit(proc, timeout: 2.0)
            if !exited, proc.processIdentifier > 0 {
                if let pgid {
                    _ = killpg(pgid, SIGKILL)
                } else {
                    _ = kill(proc.processIdentifier, SIGKILL)
                }
            }
        }
        await ACPProcessRegistry.shared.removeProcess(pid: pid, pgid: pgid)
        process = nil
        processGroupId = nil

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

        await drainBufferedMessages()
    }

    private func handleTermination(exitCode: Int32) async {
        let pid = process?.processIdentifier
        let pgid = processGroupId
        await drainAndClosePipes()
        logger.info("Agent process terminated with code: \(exitCode)")
        await ACPProcessRegistry.shared.removeProcess(pid: pid, pgid: pgid)
        await onTermination?(exitCode)
    }

    private func drainAndClosePipes() async {
        if let stdoutHandle = stdoutPipe?.fileHandleForReading {
            stdoutHandle.readabilityHandler = nil
            do {
                while true {
                    guard let chunk = try stdoutHandle.read(upToCount: 65536), !chunk.isEmpty else {
                        break
                    }
                    await processIncomingData(chunk)
                }
            } catch {
                // Handle already closed or invalid file handles safely
            }
            try? stdoutHandle.close()
        }

        if let stderrHandle = stderrPipe?.fileHandleForReading {
            stderrHandle.readabilityHandler = nil
            do {
                while true {
                    guard let chunk = try stderrHandle.read(upToCount: 65536), !chunk.isEmpty else {
                        break
                    }
                    _ = chunk
                }
            } catch {
                // Handle already closed or invalid file handles safely
            }
            try? stderrHandle.close()
        }

        await flushRemainingBufferIfNeeded()

        try? stdinPipe?.fileHandleForWriting.close()

        stdinPipe = nil
        stdoutPipe = nil
        stderrPipe = nil
        process = nil
        processGroupId = nil
        readBuffer.removeAll()
    }

    // MARK: - JSON Message Parsing
    // ACP spec: Messages are newline-delimited JSON (one message per line)
    // However, we handle multi-line JSON to be forgiving with agents that
    // send pretty-printed JSON

    private func drainBufferedMessages() async {
        while let message = popNextMessage() {
            await onDataReceived?(message)
        }
    }

    /// Extract the next complete JSON message from the buffer
    /// ACP spec says newline-delimited, but JSON strings can contain \n characters
    /// We need to find complete JSON objects, not just split on newlines
    private func popNextMessage() -> Data? {
        // Skip leading whitespace
        let whitespace: Set<UInt8> = [0x20, 0x09, 0x0D, 0x0A]  // space, tab, CR, LF
        while true {
            while let first = readBuffer.first, whitespace.contains(first) {
                readBuffer.removeFirst()
            }

            guard !readBuffer.isEmpty else {
                return nil
            }

            guard let first = readBuffer.first else { return nil }

            // JSON-RPC messages should start with object/array
            if first != 0x7B && first != 0x5B {
                if let newline = readBuffer.firstIndex(of: 0x0A) {
                    let dropped = readBuffer.prefix(upTo: newline)
                    let removeCount = readBuffer.distance(from: readBuffer.startIndex, to: newline) + 1
                    readBuffer.removeFirst(min(removeCount, readBuffer.count))
                    if !dropped.isEmpty {
                        logger.debug("Discarded non-JSON stdout line (\(dropped.count) bytes)")
                    }
                    continue
                }

                if readBuffer.count > 4096 {
                    logger.warning("Discarding \(self.readBuffer.count) bytes of non-JSON stdout")
                    self.readBuffer.removeAll(keepingCapacity: true)
                }
                return nil
            }

            break
        }

        // Convert to byte array for safe subscript access
        let bytes = Array(readBuffer)

        var depth = 0
        var inString = false
        var escaped = false

        for endIndex in 0..<bytes.count {
            let byte = bytes[endIndex]

            if inString {
                if escaped {
                    escaped = false
                    continue
                }
                if byte == 0x5C { // '\\'
                    escaped = true
                    continue
                }
                if byte == 0x22 { // '"'
                    inString = false
                }
                continue
            }

            if byte == 0x22 { // '"'
                inString = true
                continue
            }

            if byte == 0x7B || byte == 0x5B { // '{' or '['
                depth += 1
            } else if byte == 0x7D || byte == 0x5D { // '}' or ']'
                depth -= 1
                if depth == 0 {
                    let testData = Data(bytes[0...endIndex])
                    let removeCount = min(endIndex + 1, readBuffer.count)
                    readBuffer.removeFirst(removeCount)
                    return testData
                }
            }
        }

        if readBuffer.count > Self.largeBufferWarningThreshold {
            logger.warning("Large buffer (\(self.readBuffer.count) bytes) without complete JSON message")
            dumpLargeBufferIfEnabled(reason: "incomplete_json")
        }

        return nil
    }

    private func dumpLargeBufferIfEnabled(reason: String) {
        guard ProcessInfo.processInfo.environment["AIZEN_ACP_DUMP_STDOUT"] == "1" else {
            return
        }
        guard largeBufferDumpCount < Self.maxLargeBufferDumps else { return }

        let size = readBuffer.count
        guard size - lastLargeBufferDumpSize >= Self.largeBufferDumpMinGrowth else { return }

        largeBufferDumpCount += 1
        lastLargeBufferDumpSize = size

        let timestamp = String(Int(Date().timeIntervalSince1970))
        let filename = "aizen-acp-stdout-\(reason)-\(timestamp)-\(size).bin"
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        do {
            try readBuffer.write(to: fileURL, options: [.atomic])
            logger.warning("Dumped ACP stdout buffer to \(fileURL.path)")
        } catch {
            logger.error("Failed to dump ACP stdout buffer: \(error.localizedDescription)")
        }
    }

    private func flushRemainingBufferIfNeeded() async {
        await drainBufferedMessages()

        if !readBuffer.isEmpty {
            // Process any remaining partial line as a message
            let remaining = readBuffer
            readBuffer.removeAll(keepingCapacity: true)
            if !remaining.isEmpty {
                await onDataReceived?(remaining)
            }
        }
    }

    private func waitForExit(_ proc: Process, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while proc.isRunning, Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return !proc.isRunning
    }
}
