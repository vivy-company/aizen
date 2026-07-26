import AizenClient
import AizenCore
import AizenHost
import AizenMacPlatform
import AizenStorage
import AizenTransport
import Foundation

/// The app's local v2 Host composition. Views receive Client projections; they never own Storage or Host state.
actor ReignitionHostComposition {
    enum MigrationPreparation: Sendable, Equatable {
        case noLegacyStore
        case alreadyInitialized
        case migrated(MigrationReport)
    }

    let storage: StorageRepository
    let host: LocalHost
    let client: HostClient

    init(storageURL: URL? = nil) {
        let storageURL = storageURL ?? ReignitionHostComposition.defaultStorageURL()
        let storage = StorageRepository(url: storageURL)
        let sandboxRoot = storageURL.deletingLastPathComponent().appendingPathComponent("Sandboxes", isDirectory: true)
        let sandboxes = ManagedSandboxService(storage: storage, rootURL: sandboxRoot)
        let runtime = ACPRunRuntime(
            configurationResolver: StorageBackedACPRunConfigurationResolver(
                storage: storage,
                agentConfiguration: DefaultACPAgentLaunchConfigurationResolver(),
                managedSandboxRoot: sandboxRoot
            ),
            delegateProvider: NoACPToolDelegateProvider()
        )
        self.storage = storage
        host = LocalHost(
            storage: storage,
            conversationRuns: ConversationRunCoordinator(storage: storage, runtime: runtime),
            managedSandboxes: sandboxes
        )
        client = HostClient(transport: InProcessTransport(endpoint: host))
    }

    static func defaultStorageURL(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "win.aizen.app", isDirectory: true)
            .appendingPathComponent("Reignition", isDirectory: true)
            .appendingPathComponent("storage-v2.json")
    }

    func snapshot() async throws -> StorageSnapshot {
        try JSONDecoder().decode(StorageSnapshot.self, from: try await client.snapshotData())
    }

    func conversations(spaceID: SpaceID? = nil) async throws -> [Session] {
        try await client.conversations(spaceID: spaceID)
    }

    func conversationTimeline(sessionID: SessionID) async throws -> [ConversationMessage] {
        try await client.conversationTimeline(sessionID: sessionID)
    }

    func createConversation(spaceID: SpaceID, title: String) async throws -> SessionID {
        try await client.createConversation(spaceID: spaceID, title: title)
    }

    func sendConversation(spaceID: SpaceID, sessionID: SessionID, content: String) async throws -> RunID {
        try await client.sendConversation(spaceID: spaceID, sessionID: sessionID, content: content)
    }

    func prepareLegacyMigration(legacyStoreURL: URL?, legacyModelURL: URL?, fileManager: FileManager = .default) async throws -> MigrationPreparation {
        guard let legacyStoreURL, fileManager.fileExists(atPath: legacyStoreURL.path) else { return .noLegacyStore }
        guard let legacyModelURL else { throw CocoaError(.fileNoSuchFile) }
        guard try await storage.load().isEmpty else { return .alreadyInitialized }
        let report = try await LegacyCoreDataMigration.migrate(
            sourceStoreURL: legacyStoreURL,
            legacyModelURL: legacyModelURL,
            destination: storage,
            backupDirectory: legacyStoreURL.deletingLastPathComponent().appendingPathComponent("Reignition Backups", isDirectory: true)
        )
        return .migrated(report)
    }
}

/// The app composition boundary maps the existing user agent preference into the v2 Host runtime.
/// Selecting an agent per Conversation belongs to the forthcoming v2 Client state, not to Storage.
private struct DefaultACPAgentLaunchConfigurationResolver: ACPAgentLaunchConfigurationResolving {
    enum Error: Swift.Error, LocalizedError {
        case agentNotConfigured(String)

        var errorDescription: String? {
            switch self {
            case .agentNotConfigured(let agentID):
                "Agent '\(agentID)' is not installed or enabled. Configure it in Settings."
            }
        }
    }

    func launchConfiguration() async throws -> ACPAgentLaunchConfiguration {
        let agentID = UserDefaults.standard.string(forKey: "defaultACPAgent") ?? AgentRegistry.defaultAgentID
        guard AgentRegistry.shared.validateAgent(named: agentID),
            let executablePath = AgentRegistry.shared.getAgentPath(for: agentID) else {
            throw Error.agentNotConfigured(agentID)
        }
        return ACPAgentLaunchConfiguration(
            executablePath: executablePath,
            arguments: AgentRegistry.shared.getAgentLaunchArgs(for: agentID),
            environment: await AgentRegistry.shared.resolvedAgentLaunchEnvironment(for: agentID)
        )
    }
}
