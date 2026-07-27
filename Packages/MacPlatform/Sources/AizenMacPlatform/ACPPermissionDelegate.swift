import ACP
import AizenCore
import AizenHost

/// Bridges an ACP permission callback to the Host-owned one-shot permission registry.
public final class ACPPermissionDelegate: ClientDelegate, @unchecked Sendable {
    private let run: Run
    private let registry: PendingPermissionRegistry

    public init(run: Run, registry: PendingPermissionRegistry) { self.run = run; self.registry = registry }

    public func handlePermissionRequest(request: RequestPermissionRequest) async throws -> RequestPermissionResponse {
        let pending = PendingPermissionRequest(
            spaceID: run.spaceID,
            sessionID: run.sessionID,
            runID: run.id,
            title: request.toolCall.title ?? "Agent permission request",
            detail: request.toolCall.toolCallId,
            options: request.options.map { .init(id: $0.optionId, title: $0.name) }
        )
        return .init(outcome: .init(optionId: await registry.request(pending)))
    }

    public func handleFileReadRequest(_ path: String, sessionId: String, line: Int?, limit: Int?) async throws -> ReadTextFileResponse { throw ClientError.invalidResponse }
    public func handleFileWriteRequest(_ path: String, content: String, sessionId: String) async throws -> WriteTextFileResponse { throw ClientError.invalidResponse }
    public func handleTerminalCreate(command: String, sessionId: String, args: [String]?, cwd: String?, env: [EnvVariable]?, outputByteLimit: Int?) async throws -> CreateTerminalResponse { throw ClientError.invalidResponse }
    public func handleTerminalOutput(terminalId: TerminalId, sessionId: String) async throws -> TerminalOutputResponse { throw ClientError.invalidResponse }
    public func handleTerminalWaitForExit(terminalId: TerminalId, sessionId: String) async throws -> WaitForExitResponse { throw ClientError.invalidResponse }
    public func handleTerminalKill(terminalId: TerminalId, sessionId: String) async throws -> KillTerminalResponse { throw ClientError.invalidResponse }
    public func handleTerminalRelease(terminalId: TerminalId, sessionId: String) async throws -> ReleaseTerminalResponse { throw ClientError.invalidResponse }
}

public struct ACPPermissionDelegateProvider: ACPRunDelegateProviding {
    private let registry: PendingPermissionRegistry
    public init(registry: PendingPermissionRegistry) { self.registry = registry }
    public func delegate(for run: Run) async throws -> (any ClientDelegate)? { ACPPermissionDelegate(run: run, registry: registry) }
}
