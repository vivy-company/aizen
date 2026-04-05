//
//  XcodeBuildService+Execution.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 10.12.25.
//

import Foundation
import os

extension XcodeBuildService {
    func executeBuild(
        project: XcodeProject,
        scheme: String,
        destination: XcodeDestination,
        continuation: AsyncStream<BuildPhase>.Continuation
    ) async {
        isCancelled = false
        continuation.yield(.building(progress: nil))

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")

        var arguments: [String] = []
        if project.isWorkspace {
            arguments.append(contentsOf: ["-workspace", project.path])
        } else {
            arguments.append(contentsOf: ["-project", project.path])
        }

        arguments.append(contentsOf: ["-scheme", scheme])
        arguments.append(contentsOf: ["-destination", destination.destinationString])

        if destination.type == .device {
            arguments.append("-allowProvisioningUpdates")
        }

        arguments.append("build")
        process.arguments = arguments

        var environment = ShellEnvironment.loadUserShellEnvironment()
        environment["NSUnbufferedIO"] = "YES"
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let logBuffer = LogBuffer()

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
                    if let progress = self.parseProgress(from: output) {
                        continuation.yield(.building(progress: progress))
                    }
                }
            } catch {
                handle.readabilityHandler = nil
            }
        }

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

            await withCheckedContinuation { (terminationContinuation: CheckedContinuation<Void, Never>) in
                process.terminationHandler = { proc in
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    stderrPipe.fileHandleForReading.readabilityHandler = nil

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

                    try? stdoutPipe.fileHandleForReading.close()
                    try? stderrPipe.fileHandleForReading.close()
                    terminationContinuation.resume()
                }
            }

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
}

// SAFETY: Thread-safe via NSLock protecting all mutable string buffers.
nonisolated final class LogBuffer: @unchecked Sendable {
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
