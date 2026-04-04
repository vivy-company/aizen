//
//  ProcessExecutor.swift
//  aizen
//
//  Non-blocking async process execution utility
//

import Foundation

/// Result of a process execution
nonisolated struct ProcessResult: Sendable {
    let exitCode: Int32
    let stdout: String
    let stderr: String

    var succeeded: Bool { exitCode == 0 }
}

/// Error types for process execution
enum ProcessExecutorError: Error, LocalizedError {
    case executionFailed(String)
    case invalidExecutable(String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .executionFailed(let message):
            return "Process execution failed: \(message)"
        case .invalidExecutable(let path):
            return "Invalid executable: \(path)"
        case .timeout:
            return "Process execution timed out"
        }
    }
}

/// Actor for non-blocking process execution
actor ProcessExecutor {
    static let shared = ProcessExecutor()

    /// Execute a process and capture output asynchronously (non-blocking)
    func executeWithOutput(
        executable: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        workingDirectory: String? = nil
    ) async throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        if let env = environment {
            process.environment = env
        }

        if let workDir = workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workDir)
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Use nonisolated data collection with locks
        let dataCollector = DataCollector()

        // Set up non-blocking output capture using readabilityHandler
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
                dataCollector.appendStdout(data)
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
                dataCollector.appendStderr(data)
            } catch {
                handle.readabilityHandler = nil
            }
        }

        // Run process and wait asynchronously for termination
        return try await withCheckedThrowingContinuation { continuation in
            let resumeGuard = ResumeGuard()

            process.terminationHandler = { [dataCollector, resumeGuard] proc in
                resumeGuard.runOnce {
                    // Clean up handlers
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    stderrPipe.fileHandleForReading.readabilityHandler = nil

                    // Read any remaining data
                    let remainingStdout = (try? stdoutPipe.fileHandleForReading.readToEnd()) ?? Data()
                    let remainingStderr = (try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data()

                    dataCollector.appendStdout(remainingStdout)
                    dataCollector.appendStderr(remainingStderr)

                    let result = ProcessResult(
                        exitCode: proc.terminationStatus,
                        stdout: dataCollector.stdoutString,
                        stderr: dataCollector.stderrString
                    )

                    // Close pipes to release file descriptors
                    try? stdoutPipe.fileHandleForReading.close()
                    try? stderrPipe.fileHandleForReading.close()

                    continuation.resume(returning: result)
                }
            }

            do {
                try process.run()
            } catch {
                resumeGuard.runOnce {
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    stderrPipe.fileHandleForReading.readabilityHandler = nil
                    try? stdoutPipe.fileHandleForReading.close()
                    try? stderrPipe.fileHandleForReading.close()

                    continuation.resume(throwing: ProcessExecutorError.executionFailed(error.localizedDescription))
                }
            }
        }
    }

    /// Execute a process without capturing output (just exit code)
    func execute(
        executable: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        workingDirectory: String? = nil
    ) async throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        if let env = environment {
            process.environment = env
        }

        if let workDir = workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workDir)
        }

        // Discard output
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        return try await withCheckedThrowingContinuation { continuation in
            let resumeGuard = ResumeGuard()

            process.terminationHandler = { [resumeGuard] proc in
                resumeGuard.runOnce {
                    continuation.resume(returning: proc.terminationStatus)
                }
            }

            do {
                try process.run()
            } catch {
                resumeGuard.runOnce {
                    continuation.resume(throwing: ProcessExecutorError.executionFailed(error.localizedDescription))
                }
            }
        }
    }

}

// SAFETY: Thread-safe via NSLock. Ensures continuation is only resumed once.
nonisolated private final class ResumeGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var hasResumed = false

    func runOnce(_ block: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !hasResumed else { return }
        hasResumed = true
        block()
    }
}

/// Thread-safe data collector for process output
// SAFETY: Thread-safe via NSLock protecting all Data buffer mutations.
nonisolated private final class DataCollector: @unchecked Sendable {
    private var stdoutData = Data()
    private var stderrData = Data()
    private let lock = NSLock()

    func appendStdout(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        stdoutData.append(data)
    }

    func appendStderr(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        stderrData.append(data)
    }

    var stdoutString: String {
        lock.lock()
        defer { lock.unlock() }
        return String(data: stdoutData, encoding: .utf8) ?? ""
    }

    var stderrString: String {
        lock.lock()
        defer { lock.unlock() }
        return String(data: stderrData, encoding: .utf8) ?? ""
    }
}
