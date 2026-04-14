import ACP
import Foundation

extension AgentTerminalDelegate {
    /// Wait for a terminal process to exit.
    func handleTerminalWaitForExit(
        terminalId: TerminalId,
        sessionId: String
    ) async throws -> WaitForExitResponse {
        guard let state = terminals[terminalId.value] else {
            throw TerminalError.terminalNotFound(terminalId.value)
        }

        guard !state.isReleased else {
            throw TerminalError.terminalReleased(terminalId.value)
        }

        if !state.process.isRunning {
            finalizeExitedProcessOutputIfNeeded(terminalId: terminalId.value)
            return WaitForExitResponse(
                exitCode: Int(state.process.terminationStatus),
                signal: nil,
                _meta: nil
            )
        }

        let result = await withCheckedContinuation { (continuation: CheckedContinuation<(exitCode: Int?, signal: String?), Never>) in
            var waiterState = state
            waiterState.exitWaiters.append(continuation)
            terminals[terminalId.value] = waiterState
        }

        return WaitForExitResponse(
            exitCode: result.exitCode,
            signal: result.signal,
            _meta: nil
        )
    }

    func resumeExitWaiters(in state: inout TerminalState, exitCode: Int) {
        for waiter in state.exitWaiters {
            waiter.resume(returning: (exitCode, nil))
        }
        state.exitWaiters.removeAll()
    }

    func handleProcessTermination(terminalId: String) {
        guard var state = terminals[terminalId] else {
            return
        }

        finalizeExitedProcessOutputIfNeeded(terminalId: terminalId)
        state = terminals[terminalId] ?? state

        let exitCode = Int(state.process.terminationStatus)
        resumeExitWaiters(in: &state, exitCode: exitCode)
        terminals[terminalId] = state
    }
}
