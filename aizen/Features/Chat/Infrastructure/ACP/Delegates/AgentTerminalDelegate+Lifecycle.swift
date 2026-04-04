//
//  AgentTerminalDelegate+Lifecycle.swift
//  aizen
//
//  Created by OpenAI Codex on 04.04.26.
//

import ACP
import Foundation

extension AgentTerminalDelegate {
    /// Kill a terminal process
    func handleTerminalKill(terminalId: TerminalId, sessionId: String) async throws -> KillTerminalResponse {
        guard var state = terminals[terminalId.value] else {
            throw TerminalError.terminalNotFound(terminalId.value)
        }

        guard !state.isReleased else {
            throw TerminalError.terminalReleased(terminalId.value)
        }

        if state.process.isRunning {
            state.process.terminate()
            state.process.waitUntilExit()
        }

        let exitCode = Int(state.process.terminationStatus)
        resumeExitWaiters(in: &state, exitCode: exitCode)
        terminals[terminalId.value] = state

        return KillTerminalResponse(success: true, _meta: nil)
    }

    /// Release a terminal process
    func handleTerminalRelease(terminalId: TerminalId, sessionId: String) async throws -> ReleaseTerminalResponse {
        guard var state = terminals[terminalId.value] else {
            throw TerminalError.terminalNotFound(terminalId.value)
        }

        if state.process.isRunning {
            state.process.terminate()
            state.process.waitUntilExit()
        }

        AgentTerminalProcessIO.cleanupProcessPipes(
            state.process,
            terminalId: terminalId.value
        ) { [weak self] drainedTerminalId, output in
            await self?.appendOutput(terminalId: drainedTerminalId, output: output)
        }

        state = terminals[terminalId.value] ?? state

        let exitCode = Int(state.process.terminationStatus)
        resumeExitWaiters(in: &state, exitCode: exitCode)

        cacheReleasedOutput(
            terminalId: terminalId.value,
            output: state.outputBuffer,
            exitCode: exitCode
        )

        state.isReleased = true
        state.exitWaiters.removeAll()
        terminals.removeValue(forKey: terminalId.value)

        return ReleaseTerminalResponse(success: true, _meta: nil)
    }

    /// Clean up all terminals
    func cleanup() async {
        for (_, state) in terminals {
            if state.process.isRunning {
                state.process.terminate()
                state.process.waitUntilExit()
            }
            AgentTerminalProcessIO.cleanupProcessPipes(state.process)
            let exitCode = Int(state.process.terminationStatus)
            var currentState = state
            resumeExitWaiters(in: &currentState, exitCode: exitCode)
        }
        terminals.removeAll()
        clearReleasedOutputs()
    }

    /// Check if terminal is still running
    func isRunning(terminalId: TerminalId) -> Bool {
        terminals[terminalId.value]?.process.isRunning ?? false
    }
}
