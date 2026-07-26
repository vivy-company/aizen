import AizenClient
import AizenCore
import AizenWire
import Foundation

/// The Host boundary required by Reignition conversation state.
/// Platform composition supplies the transport; feature state remains portable across clients.
protocol ReignitionConversationClient: Sendable {
    func recoverPendingCommands() async throws
    func connectionState() async -> ClientConnectionState
    func projectionSnapshot() async throws -> HostProjectionSnapshotResponse
    func journalEvents(after cursor: UInt64) async throws -> ReadJournalEventsResponsePayload
    func spaces() async throws -> [Space]
    func createSpace(name: String) async throws -> SpaceID
    func conversations(spaceID: SpaceID?) async throws -> [Session]
    func resources(spaceID: SpaceID?) async throws -> [Resource]
    func executionContexts(spaceID: SpaceID?) async throws -> [ExecutionContext]
    func contextFiles(
        executionContextID: ExecutionContextID,
        relativePath: String,
        includeHidden: Bool
    ) async throws -> [ContextFileEntry]
    func contextTextFile(executionContextID: ExecutionContextID, relativePath: String) async throws -> String
    func importLocalFolder(spaceID: SpaceID, path: String, title: String?) async throws -> ResourceID
    func importLocalRepository(spaceID: SpaceID, path: String, title: String?) async throws -> ResourceID
    func createLocalFolderContext(spaceID: SpaceID, resourceID: ResourceID) async throws -> ExecutionContextID
    func createRepositoryCheckoutContext(spaceID: SpaceID, resourceID: ResourceID) async throws -> ExecutionContextID
    func createLinkedWorktreeContext(
        spaceID: SpaceID,
        resourceID: ResourceID,
        destinationPath: String,
        branch: String,
        createBranch: Bool,
        baseBranch: String?
    ) async throws -> ExecutionContextID
    func createIndependentContext(
        spaceID: SpaceID,
        resourceID: ResourceID,
        destinationPath: String,
        mode: IndependentContextMode
    ) async throws -> ExecutionContextID
    func createTerminalSession(
        spaceID: SpaceID,
        executionContextID: ExecutionContextID,
        title: String?,
        initialCommand: String?
    ) async throws -> AizenCore.TerminalSession
    func refreshRepositoryResource(id: ResourceID) async throws -> RefreshRepositoryResourceResultPayload
    func attachExecutionContext(sessionID: SessionID, contextID: ExecutionContextID) async throws
    func detachExecutionContext(sessionID: SessionID) async throws
    func conversationTimeline(sessionID: SessionID) async throws -> [ConversationMessage]
    func createConversation(spaceID: SpaceID, title: String) async throws -> SessionID
    func sendConversation(spaceID: SpaceID, sessionID: SessionID, content: String) async throws -> RunID
    func events() async -> AsyncStream<RunEvent>
}
