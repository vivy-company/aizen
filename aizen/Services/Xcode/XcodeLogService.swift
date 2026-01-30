//
//  XcodeLogService.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 10.12.25.
//

import Foundation
import os.log

actor XcodeLogService {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen", category: "XcodeLogService")

    private var isStreamingFlag = false

    // MARK: - Log Streaming from Process Pipes (for Mac apps)

    func startStreamingFromPipes(outputPipe: Pipe?, errorPipe: Pipe?, appName: String) -> AsyncStream<String> {
        isStreamingFlag = true

        return AsyncStream { continuation in
            continuation.yield("Streaming stdout/stderr for \(appName)...")
            continuation.yield("---")

            guard let outputPipe = outputPipe, let errorPipe = errorPipe else {
                continuation.yield("Error: No output pipes available")
                continuation.finish()
                return
            }

            let outputHandle = outputPipe.fileHandleForReading
            let errorHandle = errorPipe.fileHandleForReading

            // Read stdout in background
            DispatchQueue.global(qos: .userInitiated).async {
                outputHandle.readabilityHandler = { handle in
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
                            let lines = text.components(separatedBy: "\n").filter { !$0.isEmpty }
                            for line in lines {
                                continuation.yield(line)
                            }
                        }
                    } catch {
                        handle.readabilityHandler = nil
                    }
                }
            }

            // Read stderr in background
            DispatchQueue.global(qos: .userInitiated).async {
                errorHandle.readabilityHandler = { handle in
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
                            let lines = text.components(separatedBy: "\n").filter { !$0.isEmpty }
                            for line in lines {
                                continuation.yield("[stderr] \(line)")
                            }
                        }
                    } catch {
                        handle.readabilityHandler = nil
                    }
                }
            }

            continuation.onTermination = { _ in
                outputHandle.readabilityHandler = nil
                errorHandle.readabilityHandler = nil
            }
        }
    }

    // MARK: - Log Streaming via log command (for Mac apps)

    private var macLogProcess: Process?

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

    private func runMacLogStream(bundleId: String, processName: String, continuation: AsyncStream<String>.Continuation) async {
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

    private func stopMacLogStreamSync() {
        if let process = macLogProcess, process.isRunning {
            process.terminate()
            logger.info("Stopped Mac log streaming")
        }
        macLogProcess = nil
    }

    func stopMacLogStream() {
        stopMacLogStreamSync()
    }

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
            self.currentProcess = process
            logger.info("Started log streaming for \(bundleId) on \(destination.name)")

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

            logger.info("Log streaming ended for \(bundleId)")
        } catch {
            outputHandle.readabilityHandler = nil
            try? outputHandle.close()
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
