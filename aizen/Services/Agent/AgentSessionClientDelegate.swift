//
//  AgentSessionClientDelegate.swift
//  aizen
//
//  ACP client delegate bridge for AgentSession.
//

import ACP
import Foundation

final class AgentSessionClientDelegate: ClientDelegate, @unchecked Sendable {
    private weak var session: AgentSession?
    private let fileSystemDelegate = AgentFileSystemDelegate()

    init(session: AgentSession) {
        self.session = session
    }

    func handleFileReadRequest(_ path: String, sessionId: String, line: Int?, limit: Int?) async throws -> ReadTextFileResponse {
        try await fileSystemDelegate.handleFileReadRequest(path, sessionId: sessionId, line: line, limit: limit)
    }

    func handleFileWriteRequest(_ path: String, content: String, sessionId: String) async throws -> WriteTextFileResponse {
        try await fileSystemDelegate.handleFileWriteRequest(path, content: content, sessionId: sessionId)
    }

    func handleTerminalCreate(
        command: String,
        sessionId: String,
        args: [String]?,
        cwd: String?,
        env: [EnvVariable]?,
        outputByteLimit: Int?
    ) async throws -> CreateTerminalResponse {
        guard let session else { throw AgentSessionError.sessionNotActive }
        return try await session.handleTerminalCreate(
            command: command,
            sessionId: sessionId,
            args: args,
            cwd: cwd,
            env: env,
            outputByteLimit: outputByteLimit
        )
    }

    func handleTerminalOutput(terminalId: TerminalId, sessionId: String) async throws -> TerminalOutputResponse {
        guard let session else { throw AgentSessionError.sessionNotActive }
        return try await session.handleTerminalOutput(terminalId: terminalId, sessionId: sessionId)
    }

    func handleTerminalWaitForExit(terminalId: TerminalId, sessionId: String) async throws -> WaitForExitResponse {
        guard let session else { throw AgentSessionError.sessionNotActive }
        return try await session.handleTerminalWaitForExit(terminalId: terminalId, sessionId: sessionId)
    }

    func handleTerminalKill(terminalId: TerminalId, sessionId: String) async throws -> KillTerminalResponse {
        guard let session else { throw AgentSessionError.sessionNotActive }
        return try await session.handleTerminalKill(terminalId: terminalId, sessionId: sessionId)
    }

    func handleTerminalRelease(terminalId: TerminalId, sessionId: String) async throws -> ReleaseTerminalResponse {
        guard let session else { throw AgentSessionError.sessionNotActive }
        return try await session.handleTerminalRelease(terminalId: terminalId, sessionId: sessionId)
    }

    func handlePermissionRequest(request: RequestPermissionRequest) async throws -> RequestPermissionResponse {
        guard let session else { throw AgentSessionError.sessionNotActive }
        return try await session.handlePermissionRequest(request: request)
    }
}
