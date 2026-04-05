//
//  XcodeLogService+StreamingSupport.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 10.12.25.
//

import Foundation

extension XcodeLogService {
    nonisolated func prepareStreamingOutput(
        for process: Process,
        continuation: AsyncStream<String>.Continuation
    ) -> FileHandle {
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        let outputHandle = outputPipe.fileHandleForReading

        // Use readabilityHandler for non-blocking output (no busy-wait loop)
        outputHandle.readabilityHandler = { [weak outputHandle] handle in
            do {
                guard let data = try handle.read(upToCount: 65536) else {
                    outputHandle?.readabilityHandler = nil
                    try? outputHandle?.close()
                    return
                }
                guard !data.isEmpty else {
                    outputHandle?.readabilityHandler = nil
                    try? outputHandle?.close()
                    return
                }

                if let text = String(data: data, encoding: .utf8) {
                    let lines = text.components(separatedBy: "\n").filter { !$0.isEmpty }
                    for line in lines {
                        continuation.yield(line)
                    }
                }
            } catch {
                outputHandle?.readabilityHandler = nil
            }
        }

        return outputHandle
    }

    func waitForStreamingProcessTermination(
        _ process: Process,
        outputHandle: FileHandle,
        continuation: AsyncStream<String>.Continuation
    ) async {
        await withTaskCancellationHandler {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                process.terminationHandler = { _ in
                    self.cleanupStreamingOutput(outputHandle, continuation: continuation)
                    cont.resume()
                }
            }
        } onCancel: {
            process.terminate()
        }
    }

    nonisolated func cleanupStreamingOutput(
        _ outputHandle: FileHandle,
        continuation: AsyncStream<String>.Continuation
    ) {
        outputHandle.readabilityHandler = nil

        if let remainingData = try? outputHandle.readToEnd(),
           let text = String(data: remainingData, encoding: .utf8),
           !text.isEmpty {
            let lines = text.components(separatedBy: "\n").filter { !$0.isEmpty }
            for line in lines {
                continuation.yield(line)
            }
        }

        try? outputHandle.close()
    }
}
