import ACP
import Foundation

extension AgentTerminalDelegate {
    /// Get output from a terminal process.
    func handleTerminalOutput(
        terminalId: TerminalId,
        sessionId: String
    ) async throws -> TerminalOutputResponse {
        await Task.yield()

        guard var state = terminals[terminalId.value] else {
            throw TerminalError.terminalNotFound(terminalId.value)
        }

        guard !state.isReleased else {
            throw TerminalError.terminalReleased(terminalId.value)
        }

        finalizeExitedProcessOutputIfNeeded(terminalId: terminalId.value)
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
    func getOutput(terminalId: TerminalId) async -> String? {
        await Task.yield()

        if let state = terminals[terminalId.value] {
            finalizeExitedProcessOutputIfNeeded(terminalId: terminalId.value)
            if let refreshedState = terminals[terminalId.value] {
                return refreshedState.outputBuffer
            }
            return state.outputBuffer
        }
        return cachedReleasedOutput(for: terminalId.value)
    }

    func finalizeExitedProcessOutputIfNeeded(terminalId: String) {
        guard var state = terminals[terminalId],
              !state.process.isRunning,
              !state.pipesClosed else {
            return
        }

        let drainedChunks = AgentTerminalProcessIO.collectAndCloseProcessPipes(state.process)
        for chunk in drainedChunks {
            state.appendOutput(chunk)
        }

        state.pipesClosed = true
        terminals[terminalId] = state
    }

    func appendOutput(terminalId: String, data: Data) {
        guard var state = terminals[terminalId] else { return }
        state.appendOutput(data)
        terminals[terminalId] = state
    }
}
