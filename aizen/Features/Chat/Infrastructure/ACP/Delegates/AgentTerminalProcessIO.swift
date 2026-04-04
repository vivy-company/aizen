import Foundation

enum AgentTerminalProcessIO {
    nonisolated static func installReadabilityHandler(
        on pipe: Pipe,
        terminalId: String,
        appendOutput: @escaping @Sendable (String, String) async -> Void
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
                if let output = String(data: data, encoding: .utf8) {
                    Task {
                        await appendOutput(terminalId, output)
                    }
                }
            } catch {
                handle.readabilityHandler = nil
            }
        }
    }

    nonisolated static func cleanupProcessPipes(
        _ process: Process,
        terminalId: String? = nil,
        appendOutput: (@Sendable (String, String) async -> Void)? = nil
    ) {
        if let outputPipe = process.standardOutput as? Pipe {
            if let terminalId, let appendOutput {
                drainPipe(
                    outputPipe,
                    terminalId: terminalId,
                    appendOutput: appendOutput,
                    closeHandle: false
                )
            } else {
                outputPipe.fileHandleForReading.readabilityHandler = nil
            }
            try? outputPipe.fileHandleForReading.close()
        }

        if let errorPipe = process.standardError as? Pipe {
            if let terminalId, let appendOutput {
                drainPipe(
                    errorPipe,
                    terminalId: terminalId,
                    appendOutput: appendOutput,
                    closeHandle: false
                )
            } else {
                errorPipe.fileHandleForReading.readabilityHandler = nil
            }
            try? errorPipe.fileHandleForReading.close()
        }
    }

    nonisolated static func drainAvailableOutput(
        terminalId: String,
        process: Process,
        appendOutput: @escaping @Sendable (String, String) async -> Void
    ) {
        guard process.isRunning else {
            return
        }

        if let outputPipe = process.standardOutput as? Pipe {
            drainPipe(outputPipe, terminalId: terminalId, appendOutput: appendOutput, closeHandle: false)
        }

        if let errorPipe = process.standardError as? Pipe {
            drainPipe(errorPipe, terminalId: terminalId, appendOutput: appendOutput, closeHandle: false)
        }
    }

    nonisolated private static func drainPipe(
        _ pipe: Pipe,
        terminalId: String,
        appendOutput: @escaping @Sendable (String, String) async -> Void,
        closeHandle: Bool = true
    ) {
        let handle = pipe.fileHandleForReading
        handle.readabilityHandler = nil

        do {
            while true {
                guard let data = try handle.read(upToCount: 65536), !data.isEmpty else {
                    break
                }
                if let output = String(data: data, encoding: .utf8) {
                    Task {
                        await appendOutput(terminalId, output)
                    }
                }
            }
        } catch {
            // The handle is already closed or otherwise unavailable.
        }

        if closeHandle {
            try? handle.close()
        }
    }
}
