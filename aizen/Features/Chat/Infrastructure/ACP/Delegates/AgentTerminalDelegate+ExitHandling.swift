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

            Task {
                await self.monitorProcessExit(terminalId: terminalId)
            }
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

    func monitorProcessExit(terminalId: TerminalId) async {
        guard let state = terminals[terminalId.value] else { return }
        let process = state.process

        while process.isRunning {
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard terminals[terminalId.value] != nil else { return }
        }

        guard var currentState = terminals[terminalId.value],
              !currentState.exitWaiters.isEmpty else { return }

        let exitCode = Int(process.terminationStatus)
        resumeExitWaiters(in: &currentState, exitCode: exitCode)
        terminals[terminalId.value] = currentState
    }
}
