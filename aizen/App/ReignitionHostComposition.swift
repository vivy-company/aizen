import AizenClient
import AizenCore
import AizenMacPlatform
import AizenStorage
import Foundation

/// The app's v2 Host client composition. Views receive Client projections; they never own Host state.
actor ReignitionHostComposition {
    enum MigrationPreparation: Sendable, Equatable {
        case noLegacyStore
        case alreadyInitialized
        case migrated(MigrationReport)
    }

    let storage: StorageRepository
    let client: HostClient

    init(storageURL: URL? = nil) {
        let storageURL = storageURL ?? ReignitionHostComposition.defaultStorageURL()
        let storage = StorageRepository(url: storageURL)
        self.storage = storage
        client = HostClient(
            transport: MachWireTransport(machServiceName: ReignitionHostService.machServiceName),
            commandOutbox: FileCommandOutbox(url: storageURL.deletingLastPathComponent().appendingPathComponent("client-command-outbox.json"))
        )
    }

    func activate() async throws {
        try ReignitionHostService.registerIfNeeded()
        _ = try await client.negotiate()
    }

    func configureAgentLaunch(_ agentConfiguration: ACPAgentLaunchConfiguration) async throws {
        try await client.configureAgentLaunch(
            executablePath: agentConfiguration.executablePath,
            arguments: agentConfiguration.arguments,
            environment: agentConfiguration.environment
        )
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

    func recoverPendingCommands() async throws {
        _ = try await client.retryPendingCommands()
    }

    func spaces() async throws -> [Space] {
        try await client.spaces()
    }

    func createSpace(name: String) async throws -> SpaceID {
        try await client.createSpace(name: name)
    }

    func conversations(spaceID: SpaceID? = nil) async throws -> [Session] {
        try await client.conversations(spaceID: spaceID)
    }

    func resources(spaceID: SpaceID? = nil) async throws -> [Resource] {
        try await client.resources(spaceID: spaceID)
    }

    func executionContexts(spaceID: SpaceID? = nil) async throws -> [ExecutionContext] {
        try await client.executionContexts(spaceID: spaceID)
    }

    func importLocalFolder(spaceID: SpaceID, path: String, title: String?) async throws -> ResourceID {
        try await client.importLocalFolder(spaceID: spaceID, path: path, title: title)
    }

    func importLocalRepository(spaceID: SpaceID, path: String, title: String?) async throws -> ResourceID {
        try await client.importLocalRepository(spaceID: spaceID, path: path, title: title)
    }

    func createLocalFolderContext(spaceID: SpaceID, resourceID: ResourceID) async throws -> ExecutionContextID {
        try await client.createLocalFolderContext(spaceID: spaceID, resourceID: resourceID)
    }

    func createRepositoryCheckoutContext(spaceID: SpaceID, resourceID: ResourceID) async throws -> ExecutionContextID {
        try await client.createRepositoryCheckoutContext(spaceID: spaceID, resourceID: resourceID)
    }

    func attachExecutionContext(sessionID: SessionID, contextID: ExecutionContextID) async throws {
        try await client.attachExecutionContext(sessionID: sessionID, contextID: contextID)
    }

    func detachExecutionContext(sessionID: SessionID) async throws {
        try await client.detachExecutionContext(sessionID: sessionID)
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

    func cancelRun(id: RunID) async throws {
        try await client.cancelRun(id: id)
    }

    func events() async -> AsyncStream<RunEvent> {
        do {
            return try await client.runEvents()
        } catch {
            return AsyncStream { $0.finish() }
        }
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
struct DefaultACPAgentLaunchConfigurationResolver: ACPAgentLaunchConfigurationResolving {
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
