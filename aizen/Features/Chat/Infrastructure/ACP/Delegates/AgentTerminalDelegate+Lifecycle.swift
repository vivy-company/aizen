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

        finalizeExitedProcessOutputIfNeeded(terminalId: terminalId.value)
        state = terminals[terminalId.value] ?? state

        let exitCode = Int(state.process.terminationStatus)
        resumeExitWaiters(in: &state, exitCode: exitCode)
        terminals[terminalId.value] = state

        return KillTerminalResponse(_meta: nil)
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

        finalizeExitedProcessOutputIfNeeded(terminalId: terminalId.value)
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

        return ReleaseTerminalResponse(_meta: nil)
    }

    /// Clean up all terminals
    func cleanup() async {
        let terminalIds = Array(terminals.keys)

        for terminalId in terminalIds {
            guard var state = terminals[terminalId] else {
                continue
            }

            if state.process.isRunning {
                state.process.terminate()
                state.process.waitUntilExit()
            }

            finalizeExitedProcessOutputIfNeeded(terminalId: terminalId)
            state = terminals[terminalId] ?? state
            let exitCode = Int(state.process.terminationStatus)
            resumeExitWaiters(in: &state, exitCode: exitCode)
            terminals[terminalId] = state
        }
        terminals.removeAll()
        clearReleasedOutputs()
    }

    /// Check if terminal is still running
    func isRunning(terminalId: TerminalId) -> Bool {
        terminals[terminalId.value]?.process.isRunning ?? false
    }
}
