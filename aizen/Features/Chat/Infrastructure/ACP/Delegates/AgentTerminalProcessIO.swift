import Foundation

enum AgentTerminalProcessIO {
    nonisolated static func installReadabilityHandler(
        on pipe: Pipe,
        terminalId: String,
        appendOutput: @escaping @Sendable (String, Data) async -> Void
    ) {
        pipe.fileHandleForReading.readabilityHandler = { handle in
            do {
                guard let data = try handle.read(upToCount: 65536) else {
                    handle.readabilityHandler = nil
                    try? handle.close()
                    return
                }
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    try? handle.close()
                    return
                }
                Task {
                    await appendOutput(terminalId, data)
                }
            } catch {
                handle.readabilityHandler = nil
            }
        }
    }

    nonisolated static func collectAndCloseProcessPipes(_ process: Process) -> [Data] {
        var drainedChunks: [Data] = []

        if let outputPipe = process.standardOutput as? Pipe {
            if let drained = drainPipe(outputPipe, closeHandle: false), !drained.isEmpty {
                drainedChunks.append(drained)
            }
            try? outputPipe.fileHandleForReading.close()
        }

        if let errorPipe = process.standardError as? Pipe {
            if let drained = drainPipe(errorPipe, closeHandle: false), !drained.isEmpty {
                drainedChunks.append(drained)
            }
            try? errorPipe.fileHandleForReading.close()
        }

        return drainedChunks
    }

    nonisolated private static func drainPipe(
        _ pipe: Pipe,
        closeHandle: Bool = true
    ) -> Data? {
        let handle = pipe.fileHandleForReading
        handle.readabilityHandler = nil
        var drained = Data()

        do {
            while true {
                guard let data = try handle.read(upToCount: 65536), !data.isEmpty else {
                    break
                }
                drained.append(data)
            }
        } catch {
            // The handle is already closed or otherwise unavailable.
        }

        if closeHandle {
            try? handle.close()
        }

        return drained.isEmpty ? nil : drained
    }
}
