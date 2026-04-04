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
            do {
                guard let data = try handle.read(upToCount: 65536) else {
                    handle.readabilityHandler = nil
                    try? handle.close()
                    return
                }
                guard !data.isEmpty else {
                    handle.readabilityHandler = nil
                    try? handle.close()
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
            } catch {
                handle.readabilityHandler = nil
            }
        }

        // Read stderr
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            do {
                guard let data = try handle.read(upToCount: 65536) else {
                    handle.readabilityHandler = nil
                    try? handle.close()
                    return
                }
                guard !data.isEmpty else {
                    handle.readabilityHandler = nil
                    try? handle.close()
                    return
                }

                if let output = String(data: data, encoding: .utf8) {
                    logBuffer.appendStderr(output)
                }
            } catch {
                handle.readabilityHandler = nil
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
                    let remainingStdout = (try? stdoutPipe.fileHandleForReading.readToEnd()) ?? Data()
                    let remainingStderr = (try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data()

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
