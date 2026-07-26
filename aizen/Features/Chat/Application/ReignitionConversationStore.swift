import AizenCore
import AizenClient
import AizenWire
import Combine
import Foundation

/// Mac Client state for the Reignition conversation path. It owns projections only;
/// Host remains the sole owner of durable data and ACP runtime lifetime.
@MainActor
final class ReignitionConversationStore: ObservableObject {
    @Published private(set) var spaces: [Space] = []
    @Published private(set) var conversations: [Session] = []
    @Published private(set) var resources: [Resource] = []
    @Published private(set) var executionContexts: [ExecutionContext] = []
    @Published private(set) var terminalSessions: [AizenCore.TerminalSession] = []
    @Published private(set) var operations: [AizenCore.Operation] = []
    @Published private(set) var contextFiles: [ContextFileEntry] = []
    @Published private(set) var contextFileText: String?
    @Published private(set) var contextFileTextPath: String?
    @Published private(set) var repositoryStateByResourceID: [ResourceID: RefreshRepositoryResourceResultPayload] = [:]
    @Published private(set) var selectedConversationID: SessionID?
    @Published private(set) var messages: [ConversationMessage] = []
    @Published private(set) var activeRunLifecycles: [RunID: RunLifecycle] = [:]
    @Published private(set) var assistantTextByRun: [RunID: String] = [:]
    @Published private(set) var connectionState: ClientConnectionState = .disconnected
    @Published private(set) var isSynchronizing = false
    @Published private(set) var lastError: String?

    private let host: any ReignitionConversationClient
    private let journalSynchronizer: JournalEventSynchronizer
    private var sessionIDByRun: [RunID: SessionID] = [:]
    private var eventTask: Task<Void, Never>?

    init(host: any ReignitionConversationClient, journalCursorStore: any JournalCursorStore) {
        self.host = host
        journalSynchronizer = JournalEventSynchronizer(cursorStore: journalCursorStore)
        eventTask = Task { [weak self, host] in
            for await event in await host.events() {
                guard !Task.isCancelled else { return }
                await self?.consume(event)
            }
        }
    }

    deinit { eventTask?.cancel() }

    func refreshSpaces() async {
        await perform {
            try await self.host.recoverPendingCommands()
            self.spaces = try await self.host.spaces()
        }
    }

    func refresh(spaceID: SpaceID? = nil) async {
        await perform {
            try await self.recoverProjection(spaceID: spaceID)
        }
    }

    func createSpace(name: String) async -> SpaceID? {
        var createdID: SpaceID?
        await perform {
            createdID = try await self.host.createSpace(name: name)
            self.spaces = try await self.host.spaces()
            if let createdID {
                try await self.refreshProjection(spaceID: createdID)
            }
        }
        return createdID
    }

    func select(_ sessionID: SessionID?) async {
        selectedConversationID = sessionID
        messages = []
        guard let sessionID else { return }
        await refreshTimeline(sessionID: sessionID)
    }

    func createConversation(spaceID: SpaceID, title: String) async {
        await perform {
            let sessionID = try await self.host.createConversation(spaceID: spaceID, title: title)
            try await self.refreshProjection(spaceID: spaceID)
            self.selectedConversationID = sessionID
            self.messages = try await self.host.conversationTimeline(sessionID: sessionID)
        }
    }

    func send(content: String) async {
        guard let sessionID = selectedConversationID,
            let session = conversations.first(where: { $0.id == sessionID }),
            !content.isEmpty else { return }
        await perform {
            _ = try await self.host.sendConversation(spaceID: session.spaceID, sessionID: sessionID, content: content)
            self.messages = try await self.host.conversationTimeline(sessionID: sessionID)
        }
    }

    func attach(resourceID: ResourceID, to sessionID: SessionID) async {
        guard let session = conversations.first(where: { $0.id == sessionID }),
            let resource = resources.first(where: { $0.id == resourceID && $0.spaceID == session.spaceID }) else { return }
        await perform {
            let contextID: ExecutionContextID
            if let existing = self.executionContexts.first(where: { $0.resourceID == resource.id }) {
                contextID = existing.id
            } else {
                switch resource.kind {
                case .folder:
                    contextID = try await self.host.createLocalFolderContext(spaceID: session.spaceID, resourceID: resource.id)
                case .repository:
                    contextID = try await self.host.createRepositoryCheckoutContext(spaceID: session.spaceID, resourceID: resource.id)
                default:
                    return
                }
            }
            try await self.host.attachExecutionContext(sessionID: session.id, contextID: contextID)
            try await self.refreshProjection(spaceID: session.spaceID)
        }
    }

    func importAndAttachFolder(at url: URL, to sessionID: SessionID) async {
        guard let session = conversations.first(where: { $0.id == sessionID }) else { return }
        await perform {
            let resourceID = try await self.host.importLocalFolder(
                spaceID: session.spaceID,
                path: url.path,
                title: url.lastPathComponent
            )
            let contextID = try await self.host.createLocalFolderContext(spaceID: session.spaceID, resourceID: resourceID)
            try await self.host.attachExecutionContext(sessionID: session.id, contextID: contextID)
            try await self.refreshProjection(spaceID: session.spaceID)
        }
    }

    func importAndAttachRepository(at url: URL, to sessionID: SessionID) async {
        guard let session = conversations.first(where: { $0.id == sessionID }) else { return }
        await perform {
            let resourceID = try await self.host.importLocalRepository(
                spaceID: session.spaceID,
                path: url.path,
                title: url.lastPathComponent
            )
            let contextID = try await self.host.createRepositoryCheckoutContext(spaceID: session.spaceID, resourceID: resourceID)
            try await self.host.attachExecutionContext(sessionID: session.id, contextID: contextID)
            try await self.refreshProjection(spaceID: session.spaceID)
        }
    }

    func importWebResource(spaceID: SpaceID, url: URL, title: String? = nil) async -> Resource? {
        var imported: Resource?
        await perform {
            let resourceID = try await self.host.importWebResource(spaceID: spaceID, url: url, title: title)
            try await self.refreshProjection(spaceID: spaceID)
            imported = self.resources.first(where: { $0.id == resourceID })
        }
        return imported
    }

    /// Opens an external local path through Host ownership, reusing an attached conversation when possible.
    func openLocalPath(_ url: URL, preferredSpaceID: SpaceID?) async -> SpaceID? {
        var openedSpaceID: SpaceID?
        await perform {
            let directory = Self.nearestRepositoryOrDirectory(for: url)
            let availableSpaces = try await self.host.spaces()
            let spaceID: SpaceID
            if let preferredSpaceID, availableSpaces.contains(where: { $0.id == preferredSpaceID }) {
                spaceID = preferredSpaceID
            } else if let existingSpaceID = availableSpaces.first?.id {
                spaceID = existingSpaceID
            } else {
                spaceID = try await self.host.createSpace(name: "Default")
            }

            let isRepository = FileManager.default.fileExists(
                atPath: directory.appendingPathComponent(".git", isDirectory: false).path
            )
            let resourceID: ResourceID
            if isRepository {
                resourceID = try await self.host.importLocalRepository(
                    spaceID: spaceID,
                    path: directory.path,
                    title: directory.lastPathComponent
                )
            } else {
                resourceID = try await self.host.importLocalFolder(
                    spaceID: spaceID,
                    path: directory.path,
                    title: directory.lastPathComponent
                )
            }

            let contexts = try await self.host.executionContexts(spaceID: spaceID)
            let conversations = try await self.host.conversations(spaceID: spaceID)
            if let context = contexts.first(where: { $0.resourceID == resourceID }),
                let conversation = conversations.first(where: {
                    $0.kind == .conversation && $0.executionContextID == context.id
                }) {
                self.selectedConversationID = conversation.id
                self.messages = try await self.host.conversationTimeline(sessionID: conversation.id)
            } else {
                let contextID: ExecutionContextID
                if let context = contexts.first(where: { $0.resourceID == resourceID }) {
                    contextID = context.id
                } else if isRepository {
                    contextID = try await self.host.createRepositoryCheckoutContext(spaceID: spaceID, resourceID: resourceID)
                } else {
                    contextID = try await self.host.createLocalFolderContext(spaceID: spaceID, resourceID: resourceID)
                }
                let sessionID = try await self.host.createConversation(spaceID: spaceID, title: directory.lastPathComponent)
                try await self.host.attachExecutionContext(sessionID: sessionID, contextID: contextID)
                self.selectedConversationID = sessionID
                self.messages = try await self.host.conversationTimeline(sessionID: sessionID)
            }

            self.spaces = try await self.host.spaces()
            try await self.refreshProjection(spaceID: spaceID)
            openedSpaceID = spaceID
        }
        return openedSpaceID
    }

    func createLinkedWorktree(
        resourceID: ResourceID,
        to sessionID: SessionID,
        destinationPath: String,
        branch: String,
        createBranch: Bool = true,
        baseBranch: String? = nil
    ) async {
        guard let session = conversations.first(where: { $0.id == sessionID }),
              let resource = resources.first(where: { $0.id == resourceID && $0.spaceID == session.spaceID }),
              resource.kind == .repository else { return }
        await perform {
            let contextID = try await self.host.createLinkedWorktreeContext(
                spaceID: session.spaceID,
                resourceID: resource.id,
                destinationPath: destinationPath,
                branch: branch,
                createBranch: createBranch,
                baseBranch: baseBranch
            )
            try await self.host.attachExecutionContext(sessionID: session.id, contextID: contextID)
            try await self.refreshProjection(spaceID: session.spaceID)
        }
    }

    func createIndependentContext(
        resourceID: ResourceID,
        to sessionID: SessionID,
        destinationPath: String,
        mode: IndependentContextMode
    ) async {
        guard let session = conversations.first(where: { $0.id == sessionID }),
              let resource = resources.first(where: { $0.id == resourceID && $0.spaceID == session.spaceID }),
              resource.kind == .repository else { return }
        await perform {
            let contextID = try await self.host.createIndependentContext(
                spaceID: session.spaceID,
                resourceID: resource.id,
                destinationPath: destinationPath,
                mode: mode
            )
            try await self.host.attachExecutionContext(sessionID: session.id, contextID: contextID)
            try await self.refreshProjection(spaceID: session.spaceID)
        }
    }

    func createTerminal(for sessionID: SessionID) async -> AizenCore.TerminalSession? {
        guard let session = conversations.first(where: { $0.id == sessionID }),
              let executionContextID = session.executionContextID else { return nil }
        var terminal: AizenCore.TerminalSession?
        await perform {
            terminal = try await self.host.createTerminalSession(
                spaceID: session.spaceID,
                executionContextID: executionContextID,
                title: session.title,
                initialCommand: nil
            )
            try await self.refreshProjection(spaceID: session.spaceID)
        }
        return terminal
    }

    func refreshRepository(resourceID: ResourceID) async {
        await perform {
            let state = try await self.host.refreshRepositoryResource(id: resourceID)
            self.repositoryStateByResourceID[resourceID] = state
        }
    }

    func openXcodeProject(resourceID: ResourceID) async {
        await perform {
            guard let project = try await self.host.discoverXcodeProject(resourceID: resourceID) else { return }
            try await self.host.openXcodeProject(resourceID: resourceID, projectID: project.id)
        }
    }

    func loadContextFiles(contextID: ExecutionContextID, relativePath: String = "") async {
        await perform {
            self.contextFiles = try await self.host.contextFiles(
                executionContextID: contextID,
                relativePath: relativePath,
                includeHidden: false
            )
        }
    }

    func loadContextTextFile(contextID: ExecutionContextID, relativePath: String) async {
        contextFileText = nil
        contextFileTextPath = nil
        await perform {
            self.contextFileText = try await self.host.contextTextFile(
                executionContextID: contextID,
                relativePath: relativePath
            )
            self.contextFileTextPath = relativePath
        }
    }

    func detachExecutionContext(from sessionID: SessionID) async {
        guard let session = conversations.first(where: { $0.id == sessionID }) else { return }
        await perform {
            try await self.host.detachExecutionContext(sessionID: session.id)
            try await self.refreshProjection(spaceID: session.spaceID)
        }
    }

    func dismissError() {
        lastError = nil
    }

    var liveAssistantText: String? {
        guard let selectedConversationID else { return nil }
        let activeRunIDs = activeRunLifecycles.compactMap { runID, lifecycle in
            (lifecycle == .running || lifecycle == .waitingForPermission) && sessionIDByRun[runID] == selectedConversationID
                ? runID
                : nil
        }
        return activeRunIDs.compactMap { assistantTextByRun[$0] }.joined().nonEmpty
    }

    func resource(for session: Session) -> Resource? {
        guard let contextID = session.executionContextID,
            let resourceID = executionContexts.first(where: { $0.id == contextID })?.resourceID else { return nil }
        return resources.first(where: { $0.id == resourceID })
    }

    private func refreshTimeline(sessionID: SessionID) async {
        await perform {
            self.messages = try await self.host.conversationTimeline(sessionID: sessionID)
        }
    }

    private func refreshProjection(spaceID: SpaceID?) async throws {
        async let conversations = host.conversations(spaceID: spaceID)
        async let resources = host.resources(spaceID: spaceID)
        async let executionContexts = host.executionContexts(spaceID: spaceID)
        let (loadedConversations, loadedResources, loadedContexts) = try await (conversations, resources, executionContexts)
        self.conversations = loadedConversations
        self.resources = loadedResources
        self.executionContexts = loadedContexts
        if let selectedConversationID,
            !loadedConversations.contains(where: { $0.id == selectedConversationID }) {
            self.selectedConversationID = nil
            messages = []
        }
    }

    /// Recovery replays durable cursors when possible, then takes one Host consistency snapshot for the UI projection.
    private func recoverProjection(spaceID: SpaceID?) async throws {
        let cursor = try await journalSynchronizer.lastAppliedCursor()
        if cursor > 0 {
            let replay = try await host.journalEvents(after: cursor)
            do {
                _ = try await journalSynchronizer.apply(replay) { _ in }
                if replay.events.isEmpty { return }
            } catch let error as JournalSynchronizationError {
                switch error {
                case .snapshotRequired, .gap:
                    // A retained snapshot is the only safe recovery for an expired or discontinuous journal.
                    break
                }
            }
        }
        let response = try await host.projectionSnapshot()
        let snapshot = response.snapshot
        spaces = snapshot.spaces
        conversations = snapshot.sessions.filter { $0.kind == .conversation && (spaceID == nil || $0.spaceID == spaceID) }
        resources = snapshot.resources.filter { spaceID == nil || $0.spaceID == spaceID }
        executionContexts = snapshot.executionContexts.filter { spaceID == nil || $0.spaceID == spaceID }
        terminalSessions = snapshot.terminalSessions.filter { spaceID == nil || $0.spaceID == spaceID }
        operations = snapshot.operations.filter { spaceID == nil || $0.spaceID == spaceID }
        if let selectedConversationID, !conversations.contains(where: { $0.id == selectedConversationID }) {
            self.selectedConversationID = nil
            messages = []
        }
        try await journalSynchronizer.reset(to: response.cursor)
    }

    private func consume(_ event: RunEvent) async {
        sessionIDByRun[event.runID] = event.sessionID
        switch event.kind {
        case .lifecycle(let lifecycle):
            activeRunLifecycles[event.runID] = lifecycle
            guard lifecycle == .succeeded || lifecycle == .failed || lifecycle == .cancelled else { return }
            assistantTextByRun.removeValue(forKey: event.runID)
            sessionIDByRun.removeValue(forKey: event.runID)
            if event.sessionID == selectedConversationID {
                await refreshTimeline(sessionID: event.sessionID)
            }
        case .assistantTextDelta(let text):
            assistantTextByRun[event.runID, default: ""] += text
        }
    }

    private func perform(_ operation: () async throws -> Void) async {
        isSynchronizing = true
        lastError = nil
        do {
            try await operation()
        } catch {
            lastError = error.localizedDescription
        }
        isSynchronizing = false
        connectionState = await host.connectionState()
    }

    private static func nearestRepositoryOrDirectory(for url: URL) -> URL {
        let fileManager = FileManager.default
        var directory = url.standardizedFileURL
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory), !isDirectory.boolValue {
            directory.deleteLastPathComponent()
        }

        while directory.path != "/" {
            if fileManager.fileExists(atPath: directory.appendingPathComponent(".git", isDirectory: false).path) {
                return directory
            }
            let parent = directory.deletingLastPathComponent()
            guard parent.path != directory.path else { break }
            directory = parent
        }
        return url.standardizedFileURL
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
