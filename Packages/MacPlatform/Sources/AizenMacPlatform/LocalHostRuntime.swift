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

    public init(storageURL: URL, credentials providedCredentials: HostIdentityCredentials? = nil) {
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
        let host = LocalHost(
            storage: storage,
            conversationRuns: ConversationRunCoordinator(storage: storage, runtime: runtime, eventPublisher: runEvents),
            managedSandboxes: sandboxes,
            runEventPublisher: runEvents,
            terminalRuntime: TmuxTerminalRuntime(),
            agentLaunchConfiguration: agentLaunchConfiguration,
            pairingRegistry: pairing
        )
        self.host = host
        migrationGate = HostMigrationGate(
            host: host,
            migration: HostLegacyMigrationCoordinator(storage: storage, storageURL: storageURL)
        )
    }

    public func makeMachListener(configuration: HostMachServiceConfiguration) throws -> MachWireHostListener {
        try MachWireHostListener(configuration: configuration, endpoint: migrationGate)
    }

    @MainActor
    public func makeLANListener(credentials: HostIdentityCredentials) -> HostLANWebSocketListener {
        HostLANWebSocketListener(
            host: credentials.publicIdentity,
            hostIdentity: credentials.localIdentity,
            storage: storage,
            endpoint: migrationGate,
            pairing: pairing
        )
    }
}
