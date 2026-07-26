import AizenCore
import AizenHost
import AizenSecurity
import AizenStorage
import Foundation

/// macOS Host runtime construction shared by the persistent helper and deterministic local tests.
public final class LocalHostRuntime: @unchecked Sendable {
    public let host: LocalHost
    public let agentLaunchConfiguration: HostAgentLaunchConfigurationStore
    private let storage: StorageRepository
    private let migrationGate: HostMigrationGate
    private let pairing: PairingRequestRegistry
    private let connectionRegistry = HostConnectionRegistry()
    private let storageURL: URL
    private let terminalRuntime: any TerminalRuntime
    private let terminalControl = TerminalControlLeaseRegistry()

    public init(storageURL: URL, credentials providedCredentials: HostIdentityCredentials? = nil) {
        self.storageURL = storageURL
        let storage = StorageRepository(url: storageURL)
        self.storage = storage
        let credentials: HostIdentityCredentials
        if let provided = providedCredentials {
            self.pairing = PairingRequestRegistry(hostID: provided.publicIdentity.hostID, approval: PairingApprovalService(storage: storage))
            credentials = provided
        } else {
            let identity = LocalCryptographicIdentity()
            credentials = .init(publicIdentity: .init(hostID: HostID(), displayName: "Local Host", cryptographicIdentity: identity.publicIdentity()), localIdentity: identity)
            self.pairing = PairingRequestRegistry(hostID: credentials.publicIdentity.hostID, approval: PairingApprovalService(storage: storage))
        }
        let pairing = self.pairing
        let root = storageURL.deletingLastPathComponent()
        let agentLaunchConfiguration = HostAgentLaunchConfigurationStore(
            configurationURL: root.appendingPathComponent("host-agent-launch.json")
        )
        let runEvents = RunEventPublisher()
        let sandboxes = ManagedSandboxService(storage: storage, rootURL: root.appendingPathComponent("Sandboxes", isDirectory: true))
        let runtime = ACPRunRuntime(
            configurationResolver: StorageBackedACPRunConfigurationResolver(
                storage: storage,
                agentConfiguration: agentLaunchConfiguration,
                managedSandboxRoot: root.appendingPathComponent("Sandboxes", isDirectory: true)
            ),
            delegateProvider: NoACPToolDelegateProvider()
        )
        self.agentLaunchConfiguration = agentLaunchConfiguration
        let worktrees = GitLinkedWorktreeService()
        let terminalRuntime = TmuxTerminalRuntime()
        let repositoryReader = GitRepositoryStatusReader()
        self.terminalRuntime = terminalRuntime
        let host = LocalHost(
            storage: storage,
            conversationRuns: ConversationRunCoordinator(storage: storage, runtime: runtime, eventPublisher: runEvents),
            managedSandboxes: sandboxes,
            runEventPublisher: runEvents,
            terminalRuntime: terminalRuntime,
            agentLaunchConfiguration: agentLaunchConfiguration,
            pairingRegistry: pairing,
            linkedWorktrees: worktrees,
            independentContexts: worktrees,
            repositoryStatusReader: repositoryReader,
            repositoryDiffReader: repositoryReader,
            repositoryHistoryReader: repositoryReader,
            repositoryBranchReader: repositoryReader,
            repositoryIndexUpdater: repositoryReader,
            repositoryCommitter: repositoryReader,
            repositoryBranchUpdater: repositoryReader,
            repositoryFetcher: repositoryReader,
            xcodeProjectOpener: MacXcodeProjectOpener(),
            xcodeProjectInspector: MacXcodeProjectInspector(),
            xcodeProjectBuilder: MacXcodeProjectBuilder()
        )
        self.host = host
        migrationGate = HostMigrationGate(
            host: host,
            migration: HostLegacyMigrationCoordinator(storage: storage, storageURL: storageURL)
        )
    }

    public func makeMachListener(configuration: HostMachServiceConfiguration) throws -> MachWireHostListener {
        try MachWireHostListener(
            configuration: configuration,
            endpoint: HostDiagnosticsEndpoint(endpoint: migrationGate) { [weak self] in
                await self?.diagnostics() ?? .init(
                    storageState: .unavailable,
                    migrationState: .idle,
                    activeConnectionCount: 0,
                    activeRunCount: 0,
                    activeOperationCount: 0,
                    lastStartupError: "Aizen Host runtime is unavailable."
                )
            },
            connectionRegistry: connectionRegistry
        )
    }

    public func diagnostics() async -> HostDiagnosticsSnapshot {
        let migrationState: HostDiagnosticsSnapshot.MigrationState = FileManager.default.fileExists(
            atPath: HostLegacyMigrationRequestStore.requestURL(for: storageURL).path
        ) ? .pending : .idle
        do {
            let snapshot = try await storage.load()
            return .init(
                storageState: .ready,
                migrationState: migrationState,
                activeConnectionCount: connectionRegistry.count,
                activeRunCount: snapshot.runs.filter { $0.lifecycle.isActive }.count,
                activeOperationCount: snapshot.operations.filter { $0.lifecycle == .running }.count,
                lastStartupError: HostStartupStatusStore.lastError(storageURL: storageURL),
                consecutiveStartupFailureCount: HostStartupStatusStore.consecutiveFailureCount(storageURL: storageURL)
            )
        } catch {
            return .init(
                storageState: .unavailable,
                migrationState: migrationState,
                activeConnectionCount: connectionRegistry.count,
                activeRunCount: 0,
                activeOperationCount: 0,
                lastStartupError: error.localizedDescription,
                consecutiveStartupFailureCount: HostStartupStatusStore.consecutiveFailureCount(storageURL: storageURL)
            )
        }
    }

    /// Drops only persisted sessions whose exact tmux pane can no longer be found.
    @discardableResult
    public func recoverTerminalSessions() async throws -> Int {
        let sessions = try await storage.load().terminalSessions
        let recoverableIDs = try await terminalRuntime.recoverableTerminalSessionIDs(sessions)
        let staleIDs = Set(sessions.map(\.id)).subtracting(recoverableIDs)
        guard !staleIDs.isEmpty else { return 0 }
        _ = try await storage.transact { snapshot in
            snapshot.terminalSessions.removeAll { staleIDs.contains($0.id) }
        }
        return staleIDs.count
    }

    /// A process-owned operation cannot survive a Host restart. Persist that fact before clients resume polling.
    @discardableResult
    public func recoverInterruptedOperations() async throws -> Int {
        var recoveredCount = 0
        _ = try await storage.transact { snapshot in
            for index in snapshot.operations.indices where snapshot.operations[index].lifecycle == .running {
                snapshot.operations[index].lifecycle = .failed
                snapshot.operations[index].failureDescription = "Aizen Host restarted before this operation completed."
                recoveredCount += 1
            }
        }
        return recoveredCount
    }

    @MainActor
    public func makeLANListener(credentials: HostIdentityCredentials) -> HostLANWebSocketListener {
        HostLANWebSocketListener(
            host: credentials.publicIdentity,
            hostIdentity: credentials.localIdentity,
            storage: storage,
            endpoint: migrationGate,
            pairing: pairing,
            terminalControl: terminalControl
        )
    }
}

private extension RunLifecycle {
    var isActive: Bool {
        switch self {
        case .queued, .preparingContext, .startingAgent, .running, .waitingForPermission, .cancelling, .interrupted:
            true
        case .completed, .succeeded, .failed, .cancelled:
            false
        }
    }
}
