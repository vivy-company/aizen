//
//  XcodeBuildStore+LogStreaming.swift
//  aizen
//
//  Launch log streaming support for Xcode build sessions
//

import Foundation
import os

extension XcodeBuildStore {
    func startLogStream() {
        guard let bundleId = launchedBundleId,
              let destination = launchedDestination else {
            logger.warning("Cannot start log stream: no launched app info")
            return
        }

        stopLogStream()

        isLogStreamActive = true
        logOutput = []

        let appName = (launchedAppPath as NSString?)?.lastPathComponent ?? bundleId

        if destination.type == .mac,
           let outputPipe = launchedOutputPipe,
           let errorPipe = launchedErrorPipe {
            logStreamTask = Task { [weak self] in
                guard let self else { return }

                let pipeStream = await logService.startStreamingFromPipes(
                    outputPipe: outputPipe,
                    errorPipe: errorPipe,
                    appName: appName
                )

                for await line in pipeStream {
                    await MainActor.run {
                        self.appendLogLine(line)
                    }
                }
            }

            macLogStreamTask = Task { [weak self] in
                guard let self else { return }

                let osLogStream = await logService.startStreamingForMacApp(
                    bundleId: bundleId,
                    processName: appName
                )

                for await line in osLogStream {
                    await MainActor.run {
                        self.appendLogLine(line)
                    }
                }

                await MainActor.run {
                    self.isLogStreamActive = false
                }
            }
        } else if destination.type == .device,
                  let outputPipe = launchedOutputPipe,
                  let errorPipe = launchedErrorPipe {
            logStreamTask = Task { [weak self] in
                guard let self else { return }

                let stream = await logService.startStreamingFromPipes(
                    outputPipe: outputPipe,
                    errorPipe: errorPipe,
                    appName: appName
                )

                for await line in stream {
                    await MainActor.run {
                        self.appendLogLine(line)
                    }
                }

                await MainActor.run {
                    self.isLogStreamActive = false
                }
            }
        } else {
            logStreamTask = Task { [weak self] in
                guard let self else { return }

                let stream = await logService.startStreaming(bundleId: bundleId, destination: destination)

                for await line in stream {
                    await MainActor.run {
                        self.appendLogLine(line)
                    }
                }

                await MainActor.run {
                    self.isLogStreamActive = false
                }
            }
        }
    }

    func appendLogLine(_ line: String) {
        logOutput.append(line)
        if logOutput.count > 10000 {
            logOutput.removeFirst(1000)
        }
    }

    func stopLogStream() {
        logStreamTask?.cancel()
        logStreamTask = nil
        macLogStreamTask?.cancel()
        macLogStreamTask = nil
        Task {
            await logService.stopAllStreaming()
        }
        isLogStreamActive = false
    }

    func clearLogs() {
        logOutput = []
    }
}
