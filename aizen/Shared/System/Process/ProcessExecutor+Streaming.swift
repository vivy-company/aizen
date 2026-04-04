//
//  ProcessExecutor+Streaming.swift
//  aizen
//
//  Created by OpenAI Codex on 04.04.26.
//

import Foundation

extension ProcessExecutor {
    /// Execute a process and stream output via AsyncStream
    static func executeStreaming(
        executable: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        workingDirectory: String? = nil
    ) -> (process: Process, stream: AsyncStream<StreamOutput>) {
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

        let stream = AsyncStream<StreamOutput> { continuation in
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
                    if let text = String(data: data, encoding: .utf8) {
                        continuation.yield(.stdout(text))
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
                    if let text = String(data: data, encoding: .utf8) {
                        continuation.yield(.stderr(text))
                    }
                } catch {
                    handle.readabilityHandler = nil
                }
            }

            process.terminationHandler = { proc in
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil

                do {
                    let remainingStdout = try stdoutPipe.fileHandleForReading.readToEnd() ?? Data()
                    if !remainingStdout.isEmpty, let text = String(data: remainingStdout, encoding: .utf8) {
                        continuation.yield(.stdout(text))
                    }
                } catch {
                }

                do {
                    let remainingStderr = try stderrPipe.fileHandleForReading.readToEnd() ?? Data()
                    if !remainingStderr.isEmpty, let text = String(data: remainingStderr, encoding: .utf8) {
                        continuation.yield(.stderr(text))
                    }
                } catch {
                }

                continuation.yield(.terminated(proc.terminationStatus))
                try? stdoutPipe.fileHandleForReading.close()
                try? stderrPipe.fileHandleForReading.close()
                continuation.finish()
            }

            continuation.onTermination = { _ in
                if process.isRunning {
                    process.terminate()
                }
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                try? stdoutPipe.fileHandleForReading.close()
                try? stderrPipe.fileHandleForReading.close()
            }

            do {
                try process.run()
            } catch {
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                try? stdoutPipe.fileHandleForReading.close()
                try? stderrPipe.fileHandleForReading.close()
                continuation.yield(.error(error.localizedDescription))
                continuation.finish()
            }
        }

        return (process, stream)
    }
}

/// Output types for streaming execution
nonisolated enum StreamOutput: Sendable {
    case stdout(String)
    case stderr(String)
    case terminated(Int32)
    case error(String)
}
