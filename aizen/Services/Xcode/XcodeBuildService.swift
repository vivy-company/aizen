//
//  XcodeBuildService.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 10.12.25.
//

import Foundation
import os.log

actor XcodeBuildService {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen", category: "XcodeBuildService")

    private var currentProcess: Process?
    private var isCancelled = false

    // MARK: - Build and Run

    func buildAndRun(
        project: XcodeProject,
        scheme: String,
        destination: XcodeDestination
    ) -> AsyncStream<BuildPhase> {
        AsyncStream { continuation in
            Task {
                await self.executeBuild(
                    project: project,
                    scheme: scheme,
                    destination: destination,
                    continuation: continuation
                )
            }
        }
    }

    private func executeBuild(
        project: XcodeProject,
        scheme: String,
        destination: XcodeDestination,
        continuation: AsyncStream<BuildPhase>.Continuation
    ) async {
        isCancelled = false
        continuation.yield(.building(progress: nil))

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")

        // Build arguments
        var arguments: [String] = []

        if project.isWorkspace {
            arguments.append(contentsOf: ["-workspace", project.path])
        } else {
            arguments.append(contentsOf: ["-project", project.path])
        }

        arguments.append(contentsOf: ["-scheme", scheme])
        arguments.append(contentsOf: ["-destination", destination.destinationString])

        // For physical devices, allow automatic provisioning updates
        if destination.type == .device {
            arguments.append("-allowProvisioningUpdates")
        }

        // Build action - for simulators, this will also install the app
        arguments.append("build")

        process.arguments = arguments

        // Set environment
        var environment = ShellEnvironment.loadUserShellEnvironment()
        environment["NSUnbufferedIO"] = "YES" // Ensure unbuffered output
        process.environment = environment

        // Set up pipes
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let logBuffer = LogBuffer()

        // Read stdout
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }

            if let output = String(data: data, encoding: .utf8) {
                logBuffer.appendStdout(output)

                // Parse progress from output
                let progress = self.parseProgress(from: output)
                if let progress = progress {
                    continuation.yield(.building(progress: progress))
                }
            }
        }

        // Read stderr
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }

            if let output = String(data: data, encoding: .utf8) {
                logBuffer.appendStderr(output)
            }
        }

        currentProcess = process

        do {
            try process.run()

            // Use async termination instead of blocking waitUntilExit
            await withCheckedContinuation { (terminationContinuation: CheckedContinuation<Void, Never>) in
                process.terminationHandler = { proc in
                    // Clean up handlers
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    stderrPipe.fileHandleForReading.readabilityHandler = nil

                    // Read any remaining data
                    let remainingStdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    let remainingStderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                    if let str = String(data: remainingStdout, encoding: .utf8) {
                        logBuffer.appendStdout(str)
                    }
                    if let str = String(data: remainingStderr, encoding: .utf8) {
                        logBuffer.appendStderr(str)
                    }
                    let fullLog = logBuffer.combinedLog

                    if proc.terminationStatus == 0 {
                        continuation.yield(.succeeded)
                    } else {
                        let errors = self.parseBuildErrors(from: fullLog)
                        let errorSummary = errors.first?.message ?? "Build failed with exit code \(proc.terminationStatus)"
                        continuation.yield(.failed(error: errorSummary, log: fullLog))
                    }

                    // Close pipes to release file descriptors
                    try? stdoutPipe.fileHandleForReading.close()
                    try? stderrPipe.fileHandleForReading.close()

                    terminationContinuation.resume()
                }
            }

            // Check if cancelled after waiting
            if isCancelled {
                let fullLog = logBuffer.combinedLog
                continuation.yield(.failed(error: "Build cancelled", log: fullLog))
            }

        } catch {
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            try? stdoutPipe.fileHandleForReading.close()
            try? stderrPipe.fileHandleForReading.close()
            logger.error("Failed to start build process: \(error.localizedDescription)")
            continuation.yield(.failed(error: error.localizedDescription, log: ""))
        }

        currentProcess = nil
        continuation.finish()
    }

    // MARK: - Cancel

    func cancelBuild() {
        isCancelled = true
        currentProcess?.terminate()
    }

    // MARK: - Progress Parsing

    private nonisolated func parseProgress(from output: String) -> String? {
        let lines = output.components(separatedBy: "\n")

        for line in lines.reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // CompileSwift normal /path/to/File.swift
            if trimmed.hasPrefix("CompileSwift") {
                if let fileName = extractFileName(from: trimmed) {
                    return "Compiling \(fileName)"
                }
            }

            // CompileC normal /path/to/File.m
            if trimmed.hasPrefix("CompileC") {
                if let fileName = extractFileName(from: trimmed) {
                    return "Compiling \(fileName)"
                }
            }

            // Ld /path/to/binary
            if trimmed.hasPrefix("Ld ") {
                return "Linking..."
            }

            // CodeSign /path/to/app
            if trimmed.hasPrefix("CodeSign ") {
                return "Signing..."
            }

            // ProcessInfoPlistFile
            if trimmed.hasPrefix("ProcessInfoPlistFile") {
                return "Processing Info.plist"
            }

            // CopySwiftLibs
            if trimmed.hasPrefix("CopySwiftLibs") {
                return "Copying Swift libraries"
            }

            // Touch
            if trimmed.hasPrefix("Touch ") {
                return "Finishing..."
            }
        }

        return nil
    }

    private nonisolated func extractFileName(from line: String) -> String? {
        // Extract file name from path in compile command
        let components = line.components(separatedBy: " ")
        for component in components.reversed() {
            if component.hasSuffix(".swift") || component.hasSuffix(".m") ||
               component.hasSuffix(".mm") || component.hasSuffix(".c") ||
               component.hasSuffix(".cpp") {
                return (component as NSString).lastPathComponent
            }
        }
        return nil
    }

    // MARK: - Error Parsing

    private nonisolated func parseBuildErrors(from log: String) -> [BuildError] {
        var errors: [BuildError] = []
        let lines = log.components(separatedBy: "\n")

        for line in lines {
            // Format: /path/to/file.swift:123:45: error: message
            // or: /path/to/file.swift:123: error: message
            let pattern = #"(.+?):(\d+):(\d+)?:?\s*(error|warning|note):\s*(.+)"#

            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: line, options: [], range: NSRange(line.startIndex..., in: line)) {

                let file = match.range(at: 1).location != NSNotFound ?
                    String(line[Range(match.range(at: 1), in: line)!]) : nil

                let lineNum = match.range(at: 2).location != NSNotFound ?
                    Int(String(line[Range(match.range(at: 2), in: line)!])) : nil

                let column = match.range(at: 3).location != NSNotFound ?
                    Int(String(line[Range(match.range(at: 3), in: line)!])) : nil

                let typeStr = match.range(at: 4).location != NSNotFound ?
                    String(line[Range(match.range(at: 4), in: line)!]) : "error"

                let message = match.range(at: 5).location != NSNotFound ?
                    String(line[Range(match.range(at: 5), in: line)!]) : line

                let errorType: BuildError.ErrorType
                switch typeStr.lowercased() {
                case "warning": errorType = .warning
                case "note": errorType = .note
                default: errorType = .error
                }

                let error = BuildError(
                    file: file.flatMap { ($0 as NSString).lastPathComponent },
                    line: lineNum,
                    column: column,
                    message: message,
                    type: errorType
                )
                errors.append(error)
            }
        }

        // Sort errors first, then warnings, then notes
        errors.sort { lhs, rhs in
            let order: [BuildError.ErrorType: Int] = [.error: 0, .warning: 1, .note: 2]
            return (order[lhs.type] ?? 0) < (order[rhs.type] ?? 0)
        }

        return errors
    }
}

// SAFETY: Thread-safe via NSLock protecting all mutable string buffers.
nonisolated private final class LogBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var stdout = ""
    private var stderr = ""

    func appendStdout(_ text: String) {
        lock.lock()
        stdout += text
        lock.unlock()
    }

    func appendStderr(_ text: String) {
        lock.lock()
        stderr += text
        lock.unlock()
    }

    var combinedLog: String {
        lock.lock()
        defer { lock.unlock() }
        return stdout + stderr
    }
}
