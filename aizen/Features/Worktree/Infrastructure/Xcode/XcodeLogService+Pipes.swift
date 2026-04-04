import Foundation

extension XcodeLogService {
    func startStreamingFromPipes(outputPipe: Pipe?, errorPipe: Pipe?, appName: String) -> AsyncStream<String> {
        isStreamingFlag = true

        return AsyncStream { continuation in
            continuation.yield("Streaming stdout/stderr for \(appName)...")
            continuation.yield("---")

            guard let outputPipe, let errorPipe else {
                continuation.yield("Error: No output pipes available")
                continuation.finish()
                return
            }

            let outputHandle = outputPipe.fileHandleForReading
            let errorHandle = errorPipe.fileHandleForReading

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
}
