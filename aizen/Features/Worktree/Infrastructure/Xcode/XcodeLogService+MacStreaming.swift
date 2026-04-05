//
//  XcodeLogService+MacStreaming.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 10.12.25.
//

import Foundation
import os

extension XcodeLogService {
    func startStreamingForMacApp(bundleId: String, processName: String) -> AsyncStream<String> {
        stopMacLogStreamSync()
        isStreamingFlag = true

        return AsyncStream { [weak self] continuation in
            guard let self = self else {
                continuation.finish()
                return
            }

            Task {
                await self.runMacLogStream(bundleId: bundleId, processName: processName, continuation: continuation)
            }
        }
    }

    private func runMacLogStream(
        bundleId: String,
        processName: String,
        continuation: AsyncStream<String>.Continuation
    ) async {
        let process = Process()

        // Only show logs from the app's subsystem - excludes all Apple framework noise
        let predicate = "subsystem BEGINSWITH '\(bundleId)'"

        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        process.arguments = [
            "stream",
            "--predicate", predicate,
            "--style", "compact",
            "--level", "debug"
        ]

        continuation.yield("[os_log] Streaming unified logs for \(bundleId)...")
        continuation.yield("[os_log] Predicate: \(predicate)")
        continuation.yield("---")

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        let outputHandle = outputPipe.fileHandleForReading

        do {
            // Use readabilityHandler for non-blocking output (no busy-wait loop)
            outputHandle.readabilityHandler = { handle in
                do {
                    guard let data = try handle.read(upToCount: 65536) else {
                        // Empty data means EOF, clean up handler
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
                        let lines = text.components(separatedBy: "\n").filter { !$0.isEmpty }
                        for line in lines {
                            continuation.yield(line)
                        }
                    }
                } catch {
                    handle.readabilityHandler = nil
                }
            }

            try process.run()
            self.macLogProcess = process
            logger.info("Started Mac log streaming for \(bundleId)")

            // Wait for process termination using async continuation
            await withTaskCancellationHandler {
                await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                    process.terminationHandler = { _ in
                        // Clean up handler
                        outputHandle.readabilityHandler = nil
                        try? outputHandle.close()

                        // Read any remaining data
                        if let remainingData = try? outputHandle.readToEnd(),
                           let text = String(data: remainingData, encoding: .utf8),
                           !text.isEmpty {
                            let lines = text.components(separatedBy: "\n").filter { !$0.isEmpty }
                            for line in lines {
                                continuation.yield(line)
                            }
                        }

                        cont.resume()
                    }
                }
            } onCancel: {
                process.terminate()
            }

            logger.info("Mac log streaming ended for \(bundleId)")
        } catch {
            outputHandle.readabilityHandler = nil
            try? outputHandle.close()
            logger.error("Failed to start Mac log streaming: \(error.localizedDescription)")
            continuation.yield("Error: Failed to start Mac log streaming - \(error.localizedDescription)")
        }

        continuation.finish()
        self.macLogProcess = nil
    }

    func stopMacLogStream() {
        stopMacLogStreamSync()
    }

    func stopMacLogStreamSync() {
        if let process = macLogProcess, process.isRunning {
            process.terminate()
            logger.info("Stopped Mac log streaming")
        }
        macLogProcess = nil
    }
}
