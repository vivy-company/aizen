//
//  XcodeLogService.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 10.12.25.
//

import Foundation
import os.log

actor XcodeLogService {
    let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen", category: "XcodeLogService")

    var isStreamingFlag = false

    var macLogProcess: Process?

    // MARK: - Log Streaming via log command (for simulators)

    private var currentProcess: Process?

    func startStreaming(bundleId: String, destination: XcodeDestination) -> AsyncStream<String> {
        stopStreamingSync()
        isStreamingFlag = true

        return AsyncStream { [weak self] continuation in
            guard let self = self else {
                continuation.finish()
                return
            }

            Task {
                await self.runLogStream(bundleId: bundleId, destination: destination, continuation: continuation)
            }
        }
    }

    private func runLogStream(bundleId: String, destination: XcodeDestination, continuation: AsyncStream<String>.Continuation) async {
        let process = Process()

        // Only show logs from the app's subsystem - excludes all Apple framework noise
        let predicate = "subsystem BEGINSWITH '\(bundleId)'"

        // For simulators, use xcrun simctl spawn to access the simulator's log stream
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = [
            "simctl", "spawn", destination.id,
            "log", "stream",
            "--predicate", predicate,
            "--style", "compact",
            "--level", "debug"
        ]

        continuation.yield("Streaming unified logs for \(bundleId)...")
        continuation.yield("Predicate: \(predicate)")
        continuation.yield("---")
        let outputHandle = prepareStreamingOutput(for: process, continuation: continuation)

        do {
            try process.run()
            self.currentProcess = process
            logger.info("Started log streaming for \(bundleId) on \(destination.name)")

            await waitForStreamingProcessTermination(process, outputHandle: outputHandle, continuation: continuation)
            logger.info("Log streaming ended for \(bundleId)")
        } catch {
            cleanupStreamingOutput(outputHandle, continuation: continuation)
            logger.error("Failed to start log streaming: \(error.localizedDescription)")
            continuation.yield("Error: Failed to start log streaming - \(error.localizedDescription)")
        }

        continuation.finish()
        self.currentProcess = nil
        isStreamingFlag = false
    }

    func stopStreaming() {
        stopStreamingSync()
        stopMacLogStreamSync()
    }

    private func stopStreamingSync() {
        if let process = currentProcess, process.isRunning {
            process.terminate()
            logger.info("Stopped log streaming")
        }
        currentProcess = nil
        isStreamingFlag = false
    }

    func stopAllStreaming() {
        stopStreamingSync()
        stopMacLogStreamSync()
    }

    var isStreaming: Bool {
        isStreamingFlag
    }
}
