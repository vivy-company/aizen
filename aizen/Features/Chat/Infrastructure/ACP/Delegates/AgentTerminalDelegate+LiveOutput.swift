import ACP
import Foundation

extension AgentTerminalDelegate {
    /// Get output from a terminal process.
    func handleTerminalOutput(
        terminalId: TerminalId,
        sessionId: String
    ) async throws -> TerminalOutputResponse {
        guard var state = terminals[terminalId.value] else {
            throw TerminalError.terminalNotFound(terminalId.value)
        }

        guard !state.isReleased else {
            throw TerminalError.terminalReleased(terminalId.value)
        }

        drainAvailableOutput(terminalId: terminalId.value, process: state.process)
        state = terminals[terminalId.value] ?? state

        let exitStatus: TerminalExitStatus?
        if state.process.isRunning {
            exitStatus = nil
        } else {
            exitStatus = TerminalExitStatus(
                exitCode: Int(state.process.terminationStatus),
                signal: nil,
                _meta: nil
            )
        }

        return TerminalOutputResponse(
            output: state.outputBuffer,
            exitStatus: exitStatus,
            truncated: state.wasTruncated,
            _meta: nil
        )
    }

    /// Get terminal output for display (checks both active and released terminals).
    func getOutput(terminalId: TerminalId) -> String? {
        if let state = terminals[terminalId.value] {
            drainAvailableOutput(terminalId: terminalId.value, process: state.process)
            return terminals[terminalId.value]?.outputBuffer ?? state.outputBuffer
        }
        return cachedReleasedOutput(for: terminalId.value)
    }

    /// Drain available output without removing handlers (safe for running processes).
    /// Uses read(upToCount:) which throws Swift errors instead of availableData which throws ObjC exceptions.
    func drainAvailableOutput(terminalId: String, process: Process) {
        AgentTerminalProcessIO.drainAvailableOutput(
            terminalId: terminalId,
            process: process
        ) { [weak self] drainedTerminalId, output in
            await self?.appendOutput(terminalId: drainedTerminalId, output: output)
        }
    }

    func appendOutput(terminalId: String, output: String) {
        guard var state = terminals[terminalId] else { return }

        state.outputBuffer += output

        if let limit = state.outputByteLimit, state.outputBuffer.count > limit {
            let startIndex = state.outputBuffer.index(
                state.outputBuffer.startIndex,
                offsetBy: state.outputBuffer.count - limit
            )
            state.outputBuffer = String(state.outputBuffer[startIndex...])
            state.wasTruncated = true
        }

        terminals[terminalId] = state
    }
}
