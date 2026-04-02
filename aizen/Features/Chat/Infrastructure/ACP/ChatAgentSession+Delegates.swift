import ACP
import Foundation

extension ChatAgentSession {
    // MARK: - ACP Delegate Forwarding

    func handleTerminalCreate(
        command: String,
        sessionId: String,
        args: [String]?,
        cwd: String?,
        env: [EnvVariable]?,
        outputByteLimit: Int?
    ) async throws -> CreateTerminalResponse {
        let effectiveCwd = cwd ?? (workingDirectory.isEmpty ? nil : workingDirectory)

        return try await terminalDelegate.handleTerminalCreate(
            command: command,
            sessionId: sessionId,
            args: args,
            cwd: effectiveCwd,
            env: env,
            outputByteLimit: outputByteLimit
        )
    }

    func handleTerminalOutput(terminalId: TerminalId, sessionId: String) async throws
        -> TerminalOutputResponse
    {
        try await terminalDelegate.handleTerminalOutput(
            terminalId: terminalId,
            sessionId: sessionId
        )
    }

    func handleTerminalWaitForExit(terminalId: TerminalId, sessionId: String) async throws
        -> WaitForExitResponse
    {
        try await terminalDelegate.handleTerminalWaitForExit(
            terminalId: terminalId,
            sessionId: sessionId
        )
    }

    func handleTerminalKill(terminalId: TerminalId, sessionId: String) async throws
        -> KillTerminalResponse
    {
        try await terminalDelegate.handleTerminalKill(
            terminalId: terminalId,
            sessionId: sessionId
        )
    }

    func handleTerminalRelease(terminalId: TerminalId, sessionId: String) async throws
        -> ReleaseTerminalResponse
    {
        try await terminalDelegate.handleTerminalRelease(
            terminalId: terminalId,
            sessionId: sessionId
        )
    }

    func handlePermissionRequest(request: RequestPermissionRequest) async throws
        -> RequestPermissionResponse
    {
        await permissionHandler.handlePermissionRequest(request: request)
    }

    /// Respond to a permission request - delegates to permission handler
    func respondToPermission(optionId: String) {
        permissionHandler.respondToPermission(optionId: optionId)
    }

    // MARK: - Terminal Output Access

    /// Get terminal output for display in UI
    func getTerminalOutput(terminalId: String) async -> String? {
        await terminalDelegate.getOutput(terminalId: TerminalId(terminalId))
    }

    /// Check if terminal is still running
    func isTerminalRunning(terminalId: String) async -> Bool {
        await terminalDelegate.isRunning(terminalId: TerminalId(terminalId))
    }
}
