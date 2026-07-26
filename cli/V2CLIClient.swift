import AizenCore
import AizenMacPlatform
import AizenWire
import Foundation

/// CLI composition for the local v2 Host. The CLI stays a client and never opens v2 files directly.
actor V2CLIClient {
    static let productVersion = "2.0.0"
    private let client: LocalHostClient
    private var negotiated = false

    init(storageURL: URL? = nil) {
        let storageURL = storageURL ?? Self.defaultStorageURL()
        client = LocalHostClient(
            storageURL: storageURL,
            commandOutboxURL: storageURL.deletingLastPathComponent().appendingPathComponent("cli-command-outbox.json")
        )
    }

    func spaces() async throws -> [Space] {
        try await recoverPendingCommands()
        return try await client.spaces()
    }

    func createSpace(name: String, icon: String?) async throws {
        try await recoverPendingCommands()
        _ = try await client.createSpace(name: name, icon: icon)
    }

    func renameSpace(id: SpaceID, name: String) async throws {
        try await recoverPendingCommands()
        try await client.renameSpace(id: id, name: name)
    }

    func deleteSpace(id: SpaceID) async throws {
        try await recoverPendingCommands()
        try await client.deleteSpace(id: id)
    }

    func conversations(spaceID: SpaceID? = nil) async throws -> [Session] {
        try await recoverPendingCommands()
        return try await client.conversations(in: spaceID)
    }

    func createConversation(spaceID: SpaceID, title: String) async throws -> SessionID {
        try await recoverPendingCommands()
        return try await client.createConversation(spaceID: spaceID, title: title)
    }

    func conversationTimeline(sessionID: SessionID) async throws -> [ConversationMessage] {
        try await recoverPendingCommands()
        return try await client.conversationTimeline(sessionID: sessionID)
    }

    func sendConversation(spaceID: SpaceID, sessionID: SessionID, content: String) async throws -> RunID {
        try await recoverPendingCommands()
        return try await client.sendConversation(spaceID: spaceID, sessionID: sessionID, content: content)
    }

    func runs(spaceID: SpaceID? = nil) async throws -> [Run] {
        try await recoverPendingCommands()
        return try await client.runs(in: spaceID)
    }

    func cancelRun(id: RunID) async throws {
        try await recoverPendingCommands()
        try await client.cancelRun(id: id)
    }

    func resources(spaceID: SpaceID? = nil) async throws -> [Resource] {
        try await recoverPendingCommands()
        return try await client.resources(in: spaceID)
    }

    func importLocalFolder(spaceID: SpaceID, path: String, title: String? = nil) async throws -> ResourceID {
        try await recoverPendingCommands()
        return try await client.importLocalFolder(spaceID: spaceID, path: path, title: title)
    }

    func importLocalRepository(spaceID: SpaceID, path: String, title: String? = nil) async throws -> ResourceID {
        try await recoverPendingCommands()
        return try await client.importLocalRepository(spaceID: spaceID, path: path, title: title)
    }

    func removeResource(id: ResourceID) async throws {
        try await recoverPendingCommands()
        try await client.removeResource(id: id)
    }

    func refreshRepositoryResource(id: ResourceID) async throws {
        try await recoverPendingCommands()
        try await client.refreshRepositoryResource(id: id)
    }

    func executionContexts(spaceID: SpaceID? = nil, resourceID: ResourceID? = nil) async throws -> [ExecutionContext] {
        try await recoverPendingCommands()
        return try await client.executionContexts(in: spaceID, resourceID: resourceID)
    }

    func terminalSessions(spaceID: SpaceID? = nil) async throws -> [AizenCore.TerminalSession] {
        try await recoverPendingCommands()
        return try await client.terminalSessions(in: spaceID)
    }

    func createTerminalSession(
        spaceID: SpaceID,
        executionContextID: ExecutionContextID,
        title: String? = nil,
        initialCommand: String? = nil
    ) async throws -> AizenCore.TerminalSession {
        try await recoverPendingCommands()
        return try await client.createTerminalSession(
            spaceID: spaceID,
            executionContextID: executionContextID,
            title: title,
            initialCommand: initialCommand
        )
    }

    func createLocalFolderContext(spaceID: SpaceID, resourceID: ResourceID) async throws -> ExecutionContextID {
        try await recoverPendingCommands()
        return try await client.createLocalFolderContext(spaceID: spaceID, resourceID: resourceID)
    }

    func createRepositoryCheckoutContext(spaceID: SpaceID, resourceID: ResourceID) async throws -> ExecutionContextID {
        try await recoverPendingCommands()
        return try await client.createRepositoryCheckoutContext(spaceID: spaceID, resourceID: resourceID)
    }

    func attachExecutionContext(sessionID: SessionID, contextID: ExecutionContextID) async throws {
        try await recoverPendingCommands()
        try await client.attachExecutionContext(sessionID: sessionID, contextID: contextID)
    }

    func removeExecutionContext(id: ExecutionContextID) async throws {
        try await recoverPendingCommands()
        try await client.removeExecutionContext(id: id)
    }

    func detachExecutionContext(sessionID: SessionID) async throws {
        try await recoverPendingCommands()
        try await client.detachExecutionContext(sessionID: sessionID)
    }

    func compatibility() async throws -> CapabilitiesPayload {
        if !negotiated {
            let capabilities = try await client.negotiate()
            negotiated = true
            return capabilities
        }
        return try await client.negotiate()
    }

    private func recoverPendingCommands() async throws {
        if !negotiated {
            _ = try await client.negotiate()
            negotiated = true
        }
        try await client.recoverPendingCommands()
    }

    static func defaultStorageURL(fileManager: FileManager = .default) -> URL {
        if let override = ProcessInfo.processInfo.environment["AIZEN_V2_STORE_PATH"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath).standardizedFileURL
        }

        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base
            .appendingPathComponent("win.aizen.app", isDirectory: true)
            .appendingPathComponent("Reignition", isDirectory: true)
            .appendingPathComponent("storage-v2.json")
    }
}
