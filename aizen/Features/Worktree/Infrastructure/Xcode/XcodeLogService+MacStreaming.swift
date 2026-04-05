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
        let outputHandle = prepareStreamingOutput(for: process, continuation: continuation)

        do {
            try process.run()
            self.macLogProcess = process
            logger.info("Started Mac log streaming for \(bundleId)")

            await waitForStreamingProcessTermination(process, outputHandle: outputHandle, continuation: continuation)
            logger.info("Mac log streaming ended for \(bundleId)")
        } catch {
            cleanupStreamingOutput(outputHandle, continuation: continuation)
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
