import AizenCore
import AizenSecurity
import AizenStorage
import AizenTransport
import AizenWire
import CryptoKit
import Foundation

/// Host command/query composition. Mac-only runtime adapters stay outside this package.
public enum AizenHostModule {
    public static let protocolGeneration = AizenWireModule.protocolGeneration
    public static let productVersion = "2.0.0"
}

/// MacPlatform owns the secure persistence implementation; Host only coordinates the command.
public protocol AgentLaunchConfigurationUpdating: Sendable {
    func updateAgentLaunchConfiguration(_ configuration: ConfigureAgentLaunchCommandPayload) async throws
}

public protocol LinkedWorktreeCreating: Sendable {
    func createLinkedWorktree(source: URL, destination: URL, branch: String, createBranch: Bool, baseBranch: String?) async throws
}

public protocol IndependentContextCreating: Sendable {
    func createIndependentContext(source: URL, destination: URL, mode: IndependentContextMode) async throws
}

public struct RepositoryStatusSnapshot: Sendable, Equatable {
    public struct Entry: Sendable, Equatable {
        public let path: String
        public let indexStatus: String
        public let worktreeStatus: String

        public init(path: String, indexStatus: String, worktreeStatus: String) {
            self.path = path
            self.indexStatus = indexStatus
            self.worktreeStatus = worktreeStatus
        }
    }

    public let repositoryRevision: String
    public let indexRevision: String
    public let entries: [Entry]
    public let truncated: Bool

    public init(repositoryRevision: String, indexRevision: String, entries: [Entry], truncated: Bool) {
        self.repositoryRevision = repositoryRevision
        self.indexRevision = indexRevision
        self.entries = entries
        self.truncated = truncated
    }
}

/// The Host passes an already-validated local repository URL; implementations must never accept a client path.
public protocol RepositoryStatusReading: Sendable {
    func status(at repositoryURL: URL, maximumEntries: Int) async throws -> RepositoryStatusSnapshot
}

public struct RepositoryDiffSnapshot: Sendable, Equatable {
    public let repositoryRevision: String
    public let indexRevision: String
    public let unifiedDiff: Data
    public let truncated: Bool
    public init(repositoryRevision: String, indexRevision: String, unifiedDiff: Data, truncated: Bool) {
        self.repositoryRevision = repositoryRevision; self.indexRevision = indexRevision; self.unifiedDiff = unifiedDiff; self.truncated = truncated
    }
}

public protocol RepositoryDiffReading: Sendable {
    func diff(at repositoryURL: URL, relativePath: String, maximumBytes: Int) async throws -> RepositoryDiffSnapshot
}

public struct RepositoryHistorySnapshot: Sendable, Equatable {
    public struct Commit: Sendable, Equatable { public let revision: String; public let subject: String; public let authorName: String; public let authoredAtUnixMilliseconds: Int64; public init(revision: String, subject: String, authorName: String, authoredAtUnixMilliseconds: Int64) { self.revision = revision; self.subject = subject; self.authorName = authorName; self.authoredAtUnixMilliseconds = authoredAtUnixMilliseconds } }
    public let repositoryRevision: String; public let indexRevision: String; public let branch: String?; public let isDetached: Bool; public let commits: [Commit]; public let truncated: Bool
    public init(repositoryRevision: String, indexRevision: String, branch: String?, isDetached: Bool, commits: [Commit], truncated: Bool) { self.repositoryRevision = repositoryRevision; self.indexRevision = indexRevision; self.branch = branch; self.isDetached = isDetached; self.commits = commits; self.truncated = truncated }
}

public protocol RepositoryHistoryReading: Sendable {
    func history(at repositoryURL: URL, maximumCommits: Int) async throws -> RepositoryHistorySnapshot
}

public struct RepositoryBranchesSnapshot: Sendable, Equatable {
    public struct Branch: Sendable, Equatable {
        public let name: String
        public let revision: String
        public let isCurrent: Bool

        public init(name: String, revision: String, isCurrent: Bool) {
            self.name = name
            self.revision = revision
            self.isCurrent = isCurrent
        }
    }

    public let repositoryRevision: String
    public let indexRevision: String
    public let branches: [Branch]
    public let truncated: Bool

    public init(repositoryRevision: String, indexRevision: String, branches: [Branch], truncated: Bool) {
        self.repositoryRevision = repositoryRevision
        self.indexRevision = indexRevision
        self.branches = branches
        self.truncated = truncated
    }
}

public protocol RepositoryBranchReading: Sendable {
    func branches(at repositoryURL: URL, maximumBranches: Int) async throws -> RepositoryBranchesSnapshot
}

public protocol RepositoryIndexUpdating: Sendable {
    func updateIndex(at repositoryURL: URL, relativePaths: [String], expectedIndexRevision: String, stage: Bool) async throws -> String
}

public struct RepositoryCommitResult: Sendable, Equatable {
    public let repositoryRevision: String
    public let indexRevision: String

    public init(repositoryRevision: String, indexRevision: String) {
        self.repositoryRevision = repositoryRevision
        self.indexRevision = indexRevision
    }
}

public protocol RepositoryCommitting: Sendable {
    func commit(
        at repositoryURL: URL,
        message: String,
        expectedRepositoryRevision: String,
        expectedIndexRevision: String,
        amend: Bool
    ) async throws -> RepositoryCommitResult
}

public struct RepositoryBranchUpdateResult: Sendable, Equatable {
    public let repositoryRevision: String
    public let indexRevision: String

    public init(repositoryRevision: String, indexRevision: String) {
        self.repositoryRevision = repositoryRevision
        self.indexRevision = indexRevision
    }
}

public protocol RepositoryBranchUpdating: Sendable {
    func updateBranch(
        at repositoryURL: URL,
        branchName: String,
        expectedRepositoryRevision: String,
        expectedIndexRevision: String,
        create: Bool
    ) async throws -> RepositoryBranchUpdateResult
}

public struct RepositoryFetchResult: Sendable, Equatable {
    public let repositoryRevision: String
    public let indexRevision: String
    public init(repositoryRevision: String, indexRevision: String) { self.repositoryRevision = repositoryRevision; self.indexRevision = indexRevision }
}

public protocol RepositoryFetching: Sendable {
    func fetch(at repositoryURL: URL, expectedRepositoryRevision: String, expectedIndexRevision: String) async throws -> RepositoryFetchResult
}

public protocol RepositoryPulling: Sendable {
    func pull(at repositoryURL: URL, expectedRepositoryRevision: String, expectedIndexRevision: String) async throws -> RepositoryFetchResult
}

public protocol RepositoryPushing: Sendable {
    func push(at repositoryURL: URL, expectedRepositoryRevision: String, expectedIndexRevision: String) async throws -> RepositoryFetchResult
}

public protocol XcodeProjectOpening: Sendable {
    func openXcodeProject(at url: URL) async throws
}

public protocol XcodeProjectInspecting: Sendable {
    func schemes(for projectURL: URL, kind: XcodeProjectDescriptor.Kind) async throws -> [String]
    func configurations(for projectURL: URL, kind: XcodeProjectDescriptor.Kind) async throws -> [String]
}

public protocol XcodeBuildRunning: Sendable {
    func waitForCompletion() async throws
    func cancel() async
    func output() async -> AsyncStream<XcodeBuildOutput>
}

public struct XcodeBuildOutput: Sendable, Hashable {
    public let stream: OperationLogChunk.Stream
    public let text: String

    public init(stream: OperationLogChunk.Stream, text: String) {
        precondition(!text.isEmpty, "Xcode build output cannot be empty")
        precondition(text.utf8.count <= OperationLogChunk.maximumTextUTF8Count, "Xcode build output must be bounded")
        self.stream = stream
        self.text = text
    }
}

public extension XcodeBuildRunning {
    func output() async -> AsyncStream<XcodeBuildOutput> {
        AsyncStream { continuation in continuation.finish() }
    }
}

public protocol XcodeProjectBuilding: Sendable {
    func startXcodeProjectBuild(at url: URL, kind: XcodeProjectDescriptor.Kind, scheme: String, destination: String, action: XcodeProjectAction) async throws -> any XcodeBuildRunning
}

/// Explicit local Host composition. It owns Storage but exposes only Wire envelopes and Core snapshots.
public actor LocalHost: WireEndpoint {
    private let storage: StorageRepository
    private let conversationRuns: ConversationRunCoordinator?
    private let managedSandboxes: ManagedSandboxService?
    private let runEventPublisher: RunEventPublisher?
    private let terminalRuntime: (any TerminalRuntime)?
    private let terminalTranscripts: TerminalTranscriptRegistry
    private let agentLaunchConfiguration: (any AgentLaunchConfigurationUpdating)?
    private let pairingRegistry: PairingRequestRegistry?
    private let linkedWorktrees: (any LinkedWorktreeCreating)?
    private let independentContexts: (any IndependentContextCreating)?
    private let repositoryStatusReader: (any RepositoryStatusReading)?
    private let repositoryDiffReader: (any RepositoryDiffReading)?
    private let repositoryHistoryReader: (any RepositoryHistoryReading)?
    private let repositoryBranchReader: (any RepositoryBranchReading)?
    private let repositoryIndexUpdater: (any RepositoryIndexUpdating)?
    private let repositoryCommitter: (any RepositoryCommitting)?
    private let repositoryBranchUpdater: (any RepositoryBranchUpdating)?
    private let repositoryFetcher: (any RepositoryFetching)?
    private let repositoryPuller: (any RepositoryPulling)?
    private let repositoryPusher: (any RepositoryPushing)?
    private let xcodeProjectOpener: (any XcodeProjectOpening)?
    private let xcodeProjectInspector: (any XcodeProjectInspecting)?
    private let xcodeProjectBuilder: (any XcodeProjectBuilding)?
    private let contextFiles: ExecutionContextFileService
    private var xcodeBuilds: [OperationID: any XcodeBuildRunning] = [:]

    public init(
        storage: StorageRepository,
        conversationRuns: ConversationRunCoordinator? = nil,
        managedSandboxes: ManagedSandboxService? = nil,
        runEventPublisher: RunEventPublisher? = nil,
        terminalRuntime: (any TerminalRuntime)? = nil,
        terminalTranscripts: TerminalTranscriptRegistry = .init(),
        agentLaunchConfiguration: (any AgentLaunchConfigurationUpdating)? = nil,
        pairingRegistry: PairingRequestRegistry? = nil,
        linkedWorktrees: (any LinkedWorktreeCreating)? = nil,
        independentContexts: (any IndependentContextCreating)? = nil,
        repositoryStatusReader: (any RepositoryStatusReading)? = nil,
        repositoryDiffReader: (any RepositoryDiffReading)? = nil,
        repositoryHistoryReader: (any RepositoryHistoryReading)? = nil,
        repositoryBranchReader: (any RepositoryBranchReading)? = nil,
        repositoryIndexUpdater: (any RepositoryIndexUpdating)? = nil,
        repositoryCommitter: (any RepositoryCommitting)? = nil,
        repositoryBranchUpdater: (any RepositoryBranchUpdating)? = nil,
        repositoryFetcher: (any RepositoryFetching)? = nil,
        repositoryPuller: (any RepositoryPulling)? = nil,
        repositoryPusher: (any RepositoryPushing)? = nil,
        xcodeProjectOpener: (any XcodeProjectOpening)? = nil,
        xcodeProjectInspector: (any XcodeProjectInspecting)? = nil,
        xcodeProjectBuilder: (any XcodeProjectBuilding)? = nil
    ) {
        self.storage = storage
        self.conversationRuns = conversationRuns
        self.managedSandboxes = managedSandboxes
        self.runEventPublisher = runEventPublisher
        self.terminalRuntime = terminalRuntime
        self.terminalTranscripts = terminalTranscripts
        self.agentLaunchConfiguration = agentLaunchConfiguration
        self.pairingRegistry = pairingRegistry
        self.linkedWorktrees = linkedWorktrees
        self.independentContexts = independentContexts
        self.repositoryStatusReader = repositoryStatusReader
        self.repositoryDiffReader = repositoryDiffReader
        self.repositoryHistoryReader = repositoryHistoryReader
        self.repositoryBranchReader = repositoryBranchReader
        self.repositoryIndexUpdater = repositoryIndexUpdater
        self.repositoryCommitter = repositoryCommitter
        self.repositoryBranchUpdater = repositoryBranchUpdater
        self.repositoryFetcher = repositoryFetcher
        self.repositoryPuller = repositoryPuller
        self.repositoryPusher = repositoryPusher
        self.xcodeProjectOpener = xcodeProjectOpener
        self.xcodeProjectInspector = xcodeProjectInspector
        self.xcodeProjectBuilder = xcodeProjectBuilder
        self.contextFiles = .init(storage: storage)
    }

    public func runEvents() async -> AsyncStream<RunEvent> {
        guard let runEventPublisher else { return AsyncStream { $0.finish() } }
        return await runEventPublisher.events()
    }

    public func receive(_ envelope: ProtocolEnvelope) async throws -> ProtocolEnvelope {
        let payload: TypedPayload
        let kind: WireMessageKind
        switch envelope.kind {
        case .hello:
            let hello = try HelloPayload(protobufBytes: envelope.payload.protobufBytes)
            guard hello.minimumProtocolGeneration <= AizenHostModule.protocolGeneration,
                  hello.maximumProtocolGeneration >= AizenHostModule.protocolGeneration else {
                throw HostProtocolError.unsupportedRequest(kind: envelope.kind, payload: envelope.payload.identifier)
            }
            kind = .capabilities
            payload = try TypedPayload(CapabilitiesPayload(identifiers: [
                HelloPayload.identifier,
                CapabilitiesPayload.identifier,
                SnapshotRequestPayload.identifier,
                SnapshotResponsePayload.identifier,
                ReadJournalEventsQueryPayload.identifier,
                ReadJournalEventsResponsePayload.identifier,
                ListSpacesQueryPayload.identifier,
                ListSpacesResponsePayload.identifier,
                ListConversationsQueryPayload.identifier,
                ListConversationsResponsePayload.identifier,
                GetConversationTimelineQueryPayload.identifier,
                GetConversationTimelineResponsePayload.identifier,
                ListRunsQueryPayload.identifier,
                ListRunsResponsePayload.identifier,
                ListOperationsQueryPayload.identifier,
                ListOperationsResponsePayload.identifier,
                ReadOperationLogQueryPayload.identifier,
                ReadOperationLogResponsePayload.identifier,
                ListResourcesQueryPayload.identifier,
                ListResourcesResponsePayload.identifier,
                DiscoverXcodeProjectQueryPayload.identifier,
                DiscoverXcodeProjectResponsePayload.identifier,
                OpenXcodeProjectCommandPayload.identifier,
                OpenXcodeProjectResultPayload.identifier,
                BuildXcodeProjectCommandPayload.identifier,
                BuildXcodeProjectResultPayload.identifier,
                CancelOperationCommandPayload.identifier,
                CancelOperationResultPayload.identifier,
                ListExecutionContextsQueryPayload.identifier,
                ListExecutionContextsResponsePayload.identifier,
                ListTerminalSessionsQueryPayload.identifier,
                ListTerminalSessionsResponsePayload.identifier,
                AttachTerminalQueryPayload.identifier,
                AttachTerminalResponsePayload.identifier,
                ListContextFilesQueryPayload.identifier,
                ListContextFilesResponsePayload.identifier,
                ReadContextTextFileQueryPayload.identifier,
                ReadContextTextFileResponsePayload.identifier,
                ReplaceContextTextFileCommandPayload.identifier,
                ReplaceContextTextFileResultPayload.identifier,
                CreateTerminalSessionCommandPayload.identifier,
                CreateTerminalSessionResultPayload.identifier,
                TerminalInputCommandPayload.identifier,
                TerminalResizeCommandPayload.identifier,
                TerminalOperationResultPayload.identifier,
                CreateSpaceCommandPayload.identifier,
                CreateSpaceResultPayload.identifier,
                RenameSpaceCommandPayload.identifier,
                DeleteSpaceCommandPayload.identifier,
                SpaceMutationResultPayload.identifier,
                CreateConversationCommandPayload.identifier,
                CreateConversationResultPayload.identifier,
                SendConversationCommandPayload.identifier,
                SendConversationResultPayload.identifier,
                CancelRunCommandPayload.identifier,
                CancelRunResultPayload.identifier,
                ConfigureAgentLaunchCommandPayload.identifier,
                ConfigureAgentLaunchResultPayload.identifier,
                ImportLocalFolderCommandPayload.identifier,
                ImportLocalFolderResultPayload.identifier,
                ImportLocalRepositoryCommandPayload.identifier,
                ImportLocalRepositoryResultPayload.identifier,
                ImportWebResourceCommandPayload.identifier,
                ImportWebResourceResultPayload.identifier,
                RemoveResourceCommandPayload.identifier,
                ResourceMutationResultPayload.identifier,
                RefreshRepositoryResourceCommandPayload.identifier,
                RefreshRepositoryResourceResultPayload.identifier,
                ReadRepositoryStatusQueryPayload.identifier,
                ReadRepositoryStatusResponsePayload.identifier,
                ReadRepositoryDiffQueryPayload.identifier,
                ReadRepositoryDiffResponsePayload.identifier,
                ReadRepositoryHistoryQueryPayload.identifier,
                ReadRepositoryHistoryResponsePayload.identifier,
                ReadRepositoryBranchesQueryPayload.identifier,
                ReadRepositoryBranchesResponsePayload.identifier,
                UpdateRepositoryIndexCommandPayload.identifier,
                UpdateRepositoryIndexResultPayload.identifier,
                CommitRepositoryCommandPayload.identifier,
                CommitRepositoryResultPayload.identifier,
                UpdateRepositoryBranchCommandPayload.identifier,
                UpdateRepositoryBranchResultPayload.identifier,
                FetchRepositoryCommandPayload.identifier,
                FetchRepositoryResultPayload.identifier,
                PullRepositoryCommandPayload.identifier,
                PullRepositoryResultPayload.identifier,
                PushRepositoryCommandPayload.identifier,
                PushRepositoryResultPayload.identifier,
                CreateLocalFolderContextCommandPayload.identifier,
                CreateLocalFolderContextResultPayload.identifier,
                CreateRepositoryCheckoutContextCommandPayload.identifier,
                CreateRepositoryCheckoutContextResultPayload.identifier,
                CreateLinkedWorktreeContextCommandPayload.identifier,
                CreateLinkedWorktreeContextResultPayload.identifier,
                CreateIndependentContextCommandPayload.identifier,
                CreateIndependentContextResultPayload.identifier,
                AttachExecutionContextCommandPayload.identifier,
                DetachExecutionContextCommandPayload.identifier,
                RemoveExecutionContextCommandPayload.identifier,
                ExecutionContextMutationResultPayload.identifier
                , ListPendingPairingRequestsQueryPayload.identifier, ListPendingPairingRequestsResponsePayload.identifier, ApprovePairingRequestCommandPayload.identifier, RejectPairingRequestCommandPayload.identifier, PairingApprovalResultPayload.identifier
            ], productVersion: AizenHostModule.productVersion, minimumCompatibleProductVersion: "2.0.0"))
        case .query where envelope.payload.identifier == ListPendingPairingRequestsQueryPayload.identifier:
            guard let pairingRegistry else { throw HostProtocolError.unsupportedRequest(kind: envelope.kind, payload: envelope.payload.identifier) }
            _ = try ListPendingPairingRequestsQueryPayload(protobufBytes: envelope.payload.protobufBytes)
            kind = .queryResponse
            payload = try TypedPayload(ListPendingPairingRequestsResponsePayload(requests: await pairingRegistry.pending().map { .init(tokenID: $0.tokenID, deviceID: $0.device.deviceID, deviceDisplayName: $0.device.displayName, devicePlatform: $0.device.platform, fingerprint: $0.device.cryptographicIdentity.fingerprint.description, route: $0.route, receivedAt: $0.receivedAt) }))
        case .command where envelope.payload.identifier == ApprovePairingRequestCommandPayload.identifier:
            guard let pairingRegistry else { throw HostProtocolError.unsupportedRequest(kind: envelope.kind, payload: envelope.payload.identifier) }
            let command = try ApprovePairingRequestCommandPayload(protobufBytes: envelope.payload.protobufBytes)
            let grants = try Set(command.capabilities.map { raw -> CapabilityGrant in guard let capability = HostCapability(rawValue: raw) else { throw HostProtocolError.unsupportedRequest(kind: envelope.kind, payload: envelope.payload.identifier) }; return .init(capability: capability) })
            let authorization = try await pairingRegistry.approve(tokenID: command.tokenID, grants: grants)
            kind = .commandResult; payload = try TypedPayload(PairingApprovalResultPayload(deviceID: authorization.device.deviceID))
        case .command where envelope.payload.identifier == RejectPairingRequestCommandPayload.identifier:
            guard let pairingRegistry else { throw HostProtocolError.unsupportedRequest(kind: envelope.kind, payload: envelope.payload.identifier) }
            let deviceID = try await pairingRegistry.reject(tokenID: try RejectPairingRequestCommandPayload(protobufBytes: envelope.payload.protobufBytes).tokenID)
            kind = .commandResult; payload = try TypedPayload(PairingApprovalResultPayload(deviceID: deviceID))
        case .query where envelope.payload.identifier == SnapshotRequestPayload.identifier:
            let request = try SnapshotRequestPayload(protobufBytes: envelope.payload.protobufBytes)
            let snapshot = try await storage.load()
            kind = .queryResponse
            payload = try TypedPayload(SnapshotResponsePayload(
                scope: request.scope,
                cursor: snapshot.journalEvents.last?.cursor ?? 0,
                snapshot: JSONEncoder().encode(Self.clientProjection(from: snapshot))
            ))
        case .query where envelope.payload.identifier == ReadJournalEventsQueryPayload.identifier:
            let query = try ReadJournalEventsQueryPayload(protobufBytes: envelope.payload.protobufBytes)
            let spaceID = try query.spaceID.map(Self.spaceID(from:))
            let bounds = try await storage.journalCursorBounds()
            let snapshotRequired = bounds.oldest.map { query.afterCursor < $0 - 1 } ?? false
            let events = snapshotRequired ? [] : try await storage.journalEvents(after: query.afterCursor, spaceID: spaceID)
            kind = .queryResponse
            payload = try TypedPayload(ReadJournalEventsResponsePayload(
                events: events,
                oldestCursor: bounds.oldest ?? 0,
                latestCursor: bounds.latest,
                snapshotRequired: snapshotRequired
            ))
        case .query where envelope.payload.identifier == ListSpacesQueryPayload.identifier:
            _ = try ListSpacesQueryPayload(protobufBytes: envelope.payload.protobufBytes)
            let spaces = try await storage.load().spaces
            kind = .queryResponse
            payload = try TypedPayload(ListSpacesResponsePayload(spaces: spaces))
        case .query where envelope.payload.identifier == ListConversationsQueryPayload.identifier:
            let query = try ListConversationsQueryPayload(protobufBytes: envelope.payload.protobufBytes)
            let spaceID = try query.spaceID.map(Self.spaceID(from:))
            let conversations = try await storage.load().sessions.filter {
                $0.kind == .conversation && (spaceID == nil || $0.spaceID == spaceID)
            }
            kind = .queryResponse
            payload = try TypedPayload(ListConversationsResponsePayload(conversations: conversations))
        case .query where envelope.payload.identifier == GetConversationTimelineQueryPayload.identifier:
            let query = try GetConversationTimelineQueryPayload(protobufBytes: envelope.payload.protobufBytes)
            let sessionID = try Self.sessionID(from: query.sessionID)
            let messages = try await storage.load().conversationMessages
                .filter { $0.sessionID == sessionID }
                .sorted { $0.createdAt < $1.createdAt }
            kind = .queryResponse
            payload = try TypedPayload(GetConversationTimelineResponsePayload(messages: messages))
        case .query where envelope.payload.identifier == ListRunsQueryPayload.identifier:
            let query = try ListRunsQueryPayload(protobufBytes: envelope.payload.protobufBytes)
            let spaceID = try query.spaceID.map(Self.spaceID(from:))
            let runs = try await storage.load().runs.filter { spaceID == nil || $0.spaceID == spaceID }
            kind = .queryResponse
            payload = try TypedPayload(ListRunsResponsePayload(runs: runs))
        case .query where envelope.payload.identifier == ListOperationsQueryPayload.identifier:
            let query = try ListOperationsQueryPayload(protobufBytes: envelope.payload.protobufBytes)
            let spaceID = try query.spaceID.map(Self.spaceID(from:))
            let operationID = try query.operationID.map(Self.operationID(from:))
            let operations = try await storage.load().operations.filter {
                (spaceID == nil || $0.spaceID == spaceID) && (operationID == nil || $0.id == operationID)
            }
            kind = .queryResponse
            payload = try TypedPayload(ListOperationsResponsePayload(operations: operations))
        case .query where envelope.payload.identifier == ReadOperationLogQueryPayload.identifier:
            let query = try ReadOperationLogQueryPayload(protobufBytes: envelope.payload.protobufBytes)
            let operationID = try Self.operationID(from: query.operationID)
            guard try await storage.load().operations.contains(where: { $0.id == operationID }) else {
                throw HostProtocolError.unknownOperation(operationID)
            }
            let chunks = try await storage.operationLogChunks(
                operationID: operationID,
                afterSequence: query.afterSequence,
                maximumBytes: query.maximumBytes
            )
            let lastSequence = chunks.last?.sequence ?? query.afterSequence
            let truncated = !(try await storage.operationLogChunks(
                operationID: operationID,
                afterSequence: lastSequence,
                maximumBytes: 1_024 * 1_024
            )).isEmpty
            kind = .queryResponse
            payload = try TypedPayload(ReadOperationLogResponsePayload(chunks: chunks, truncated: truncated))
        case .query where envelope.payload.identifier == ListResourcesQueryPayload.identifier:
            let query = try ListResourcesQueryPayload(protobufBytes: envelope.payload.protobufBytes)
            let spaceID = try query.spaceID.map(Self.spaceID(from:))
            let resources = try await storage.load().resources.filter { spaceID == nil || $0.spaceID == spaceID }
            kind = .queryResponse
            payload = try TypedPayload(ListResourcesResponsePayload(resources: resources))
        case .query where envelope.payload.identifier == DiscoverXcodeProjectQueryPayload.identifier:
            let query = try DiscoverXcodeProjectQueryPayload(protobufBytes: envelope.payload.protobufBytes)
            let resourceID = try Self.resourceID(from: query.resourceID)
            let snapshot = try await storage.load()
            guard let resource = snapshot.resources.first(where: { $0.id == resourceID }) else {
                throw HostProtocolError.unknownResource(resourceID)
            }
            kind = .queryResponse
            payload = try TypedPayload(DiscoverXcodeProjectResponsePayload(project: try await xcodeProject(for: resource)))
        case .command where envelope.payload.identifier == OpenXcodeProjectCommandPayload.identifier:
            guard let xcodeProjectOpener else { throw HostProtocolError.runtimeUnavailable }
            let command = try OpenXcodeProjectCommandPayload(protobufBytes: envelope.payload.protobufBytes)
            let resourceID = try Self.resourceID(from: command.resourceID)
            let snapshot = try await storage.load()
            guard let resource = snapshot.resources.first(where: { $0.id == resourceID }) else {
                throw HostProtocolError.unknownResource(resourceID)
            }
            payload = try await executeDurably(envelope: envelope, spaceID: resource.spaceID) {
                let snapshot = try await self.storage.load()
                guard let resource = snapshot.resources.first(where: { $0.id == resourceID }),
                      let project = try await self.xcodeProject(for: resource), project.id == command.projectID,
                      let directory = try Self.localResourceDirectory(for: resource) else {
                    throw HostProtocolError.unknownResource(resourceID)
                }
                try await xcodeProjectOpener.openXcodeProject(at: directory.appendingPathComponent(project.id))
                return try TypedPayload(OpenXcodeProjectResultPayload())
            }
            kind = .commandResult
        case .command where envelope.payload.identifier == BuildXcodeProjectCommandPayload.identifier:
            guard let xcodeProjectBuilder else { throw HostProtocolError.runtimeUnavailable }
            let command = try BuildXcodeProjectCommandPayload(protobufBytes: envelope.payload.protobufBytes)
            let resourceID = try Self.resourceID(from: command.resourceID)
            let snapshot = try await storage.load()
            guard let resource = snapshot.resources.first(where: { $0.id == resourceID }) else { throw HostProtocolError.unknownResource(resourceID) }
            payload = try await executeDurably(envelope: envelope, spaceID: resource.spaceID) {
                guard let project = try await self.xcodeProject(for: resource), project.id == command.projectID, project.schemes.contains(command.scheme),
                      let directory = try Self.localResourceDirectory(for: resource) else { throw HostProtocolError.unknownResource(resourceID) }
                let operation = Operation(spaceID: resource.spaceID, resourceID: resource.id, lifecycle: .running, progress: 0)
                _ = try await self.storage.transact { $0.operations.append(operation) }
                let build = try await xcodeProjectBuilder.startXcodeProjectBuild(
                    at: directory.appendingPathComponent(project.id),
                    kind: project.kind,
                    scheme: command.scheme,
                    destination: command.destination,
                    action: command.action
                )
                self.xcodeBuilds[operation.id] = build
                Task { [weak self] in
                    await self?.persistXcodeBuildOutput(operationID: operation.id, build: build)
                }
                Task { [weak self] in
                    await self?.runXcodeProjectBuild(
                        operationID: operation.id,
                        build: build,
                        action: command.action
                    )
                }
                return try TypedPayload(BuildXcodeProjectResultPayload(operationID: operation.id.description))
            }
            kind = .commandResult
        case .command where envelope.payload.identifier == CancelOperationCommandPayload.identifier:
            let command = try CancelOperationCommandPayload(protobufBytes: envelope.payload.protobufBytes)
            let operationID = try Self.operationID(from: command.operationID)
            payload = try await executeDurably(envelope: envelope, spaceID: nil) {
                guard let build = self.xcodeBuilds[operationID] else { throw HostProtocolError.unknownOperation(operationID) }
                await build.cancel()
                _ = try await self.storage.transact { snapshot in
                    guard let index = snapshot.operations.firstIndex(where: { $0.id == operationID }), snapshot.operations[index].lifecycle == .running else { return }
                    snapshot.operations[index].lifecycle = .cancelled
                }
                return try TypedPayload(CancelOperationResultPayload(operationID: operationID.description))
            }
            kind = .commandResult
        case .query where envelope.payload.identifier == ListExecutionContextsQueryPayload.identifier:
            let query = try ListExecutionContextsQueryPayload(protobufBytes: envelope.payload.protobufBytes)
            let spaceID = try query.spaceID.map(Self.spaceID(from:))
            let resourceID = try query.resourceID.map(Self.resourceID(from:))
            let contexts = try await storage.load().executionContexts.filter {
                (spaceID == nil || $0.spaceID == spaceID) && (resourceID == nil || $0.resourceID == resourceID)
            }
            kind = .queryResponse
            payload = try TypedPayload(ListExecutionContextsResponsePayload(contexts: contexts))
        case .query where envelope.payload.identifier == ListTerminalSessionsQueryPayload.identifier:
            let query = try ListTerminalSessionsQueryPayload(protobufBytes: envelope.payload.protobufBytes)
            let spaceID = try query.spaceID.map(Self.spaceID(from:))
            let sessions = try await storage.load().terminalSessions.filter { spaceID == nil || $0.spaceID == spaceID }
            kind = .queryResponse
            payload = try TypedPayload(ListTerminalSessionsResponsePayload(sessions: sessions))
        case .query where envelope.payload.identifier == AttachTerminalQueryPayload.identifier:
            let query = try AttachTerminalQueryPayload(protobufBytes: envelope.payload.protobufBytes)
            let terminalSessionID = try Self.sessionID(from: query.terminalSessionID)
            guard let terminalRuntime else { throw HostProtocolError.runtimeUnavailable }
            guard let session = try await storage.load().terminalSessions.first(where: { $0.id == terminalSessionID }) else {
                throw HostProtocolError.unknownSession(terminalSessionID)
            }
            if query.columns > 0, let columns = Int(exactly: query.columns), let rows = Int(exactly: query.rows) {
                try await terminalRuntime.resize(session: session, columns: columns, rows: rows)
            }
            let capture = try await terminalRuntime.captureOutput(for: session, maximumBytes: Int(query.scrollbackBytes))
            _ = await terminalTranscripts.record(terminalID: terminalSessionID, capture: capture)
            let transcript = await terminalTranscripts.snapshot(terminalID: terminalSessionID, after: query.afterSequence)
            kind = .queryResponse
            payload = try TypedPayload(AttachTerminalResponsePayload(terminalSessionID: query.terminalSessionID, sequence: transcript.sequence, output: transcript.bytes, truncated: transcript.truncated))
        case .query where envelope.payload.identifier == ListContextFilesQueryPayload.identifier:
            let query = try ListContextFilesQueryPayload(protobufBytes: envelope.payload.protobufBytes)
            let contextID = try Self.executionContextID(from: query.executionContextID)
            let entries = try await contextFiles.listDirectory(
                contextID: contextID,
                relativePath: query.relativePath,
                includeHidden: query.includeHidden
            )
            kind = .queryResponse
            payload = try TypedPayload(ListContextFilesResponsePayload(entries: entries))
        case .query where envelope.payload.identifier == ReadContextTextFileQueryPayload.identifier:
            let query = try ReadContextTextFileQueryPayload(protobufBytes: envelope.payload.protobufBytes)
            let contextID = try Self.executionContextID(from: query.executionContextID)
            let text = try await contextFiles.readTextFile(contextID: contextID, relativePath: query.relativePath)
            kind = .queryResponse
            let contentHash = SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
            payload = try TypedPayload(ReadContextTextFileResponsePayload(relativePath: query.relativePath, text: text, contentHash: contentHash))
        case .command where envelope.payload.identifier == ReplaceContextTextFileCommandPayload.identifier:
            let command = try ReplaceContextTextFileCommandPayload(protobufBytes: envelope.payload.protobufBytes)
            let contextID = try Self.executionContextID(from: command.executionContextID)
            let contentHash = try await contextFiles.replaceTextFile(contextID: contextID, relativePath: command.relativePath, expectedContentHash: command.expectedContentHash, text: command.text)
            kind = .commandResult
            payload = try TypedPayload(ReplaceContextTextFileResultPayload(relativePath: command.relativePath, contentHash: contentHash))
        case .command where envelope.payload.identifier == TerminalInputCommandPayload.identifier:
            let command = try TerminalInputCommandPayload(protobufBytes: envelope.payload.protobufBytes)
            let terminalSessionID = try Self.sessionID(from: command.terminalSessionID)
            guard let terminalRuntime else { throw HostProtocolError.runtimeUnavailable }
            guard let session = try await storage.load().terminalSessions.first(where: { $0.id == terminalSessionID }) else {
                throw HostProtocolError.unknownSession(terminalSessionID)
            }
            try await terminalRuntime.sendInput(to: session, input: command.input)
            payload = try TypedPayload(TerminalOperationResultPayload(terminalSessionID: command.terminalSessionID, sequence: command.sequence))
            kind = .commandResult
        case .command where envelope.payload.identifier == TerminalResizeCommandPayload.identifier:
            let command = try TerminalResizeCommandPayload(protobufBytes: envelope.payload.protobufBytes)
            guard let columns = Int(exactly: command.columns), let rows = Int(exactly: command.rows),
                  (1...1_000).contains(columns), (1...1_000).contains(rows) else {
                throw HostProtocolError.invalidTerminalDimensions
            }
            let terminalSessionID = try Self.sessionID(from: command.terminalSessionID)
            guard let terminalRuntime else { throw HostProtocolError.runtimeUnavailable }
            guard let session = try await storage.load().terminalSessions.first(where: { $0.id == terminalSessionID }) else {
                throw HostProtocolError.unknownSession(terminalSessionID)
            }
            try await terminalRuntime.resize(session: session, columns: columns, rows: rows)
            payload = try TypedPayload(TerminalOperationResultPayload(terminalSessionID: command.terminalSessionID, sequence: command.sequence))
            kind = .commandResult
        case .command where envelope.payload.identifier == CreateTerminalSessionCommandPayload.identifier:
            let command = try CreateTerminalSessionCommandPayload(protobufBytes: envelope.payload.protobufBytes)
            let terminalSessionID = try Self.sessionID(from: command.terminalSessionID)
            let spaceID = try Self.spaceID(from: command.spaceID)
            let executionContextID = try Self.executionContextID(from: command.executionContextID)
            payload = try await executeDurably(envelope: envelope, spaceID: spaceID) {
                guard let terminalRuntime = self.terminalRuntime else { throw HostProtocolError.runtimeUnavailable }
                let snapshot = try await self.storage.load()
                guard snapshot.spaces.contains(where: { $0.id == spaceID }) else { throw HostProtocolError.unknownSpace(spaceID) }
                guard !snapshot.terminalSessions.contains(where: { $0.id == terminalSessionID }) else {
                    throw HostProtocolError.duplicateTerminalSession(terminalSessionID)
                }
                guard let executionContext = snapshot.executionContexts.first(where: { $0.id == executionContextID && $0.spaceID == spaceID }) else {
                    throw HostProtocolError.unknownExecutionContext(executionContextID)
                }
                let resource = executionContext.resourceID.flatMap { resourceID in
                    snapshot.resources.first(where: { $0.id == resourceID && $0.spaceID == spaceID })
                }
                let launch = try await terminalRuntime.createTerminal(
                    id: terminalSessionID,
                    spaceID: spaceID,
                    executionContext: executionContext,
                    resource: resource,
                    title: command.title,
                    initialCommand: command.initialCommand
                )
                let session = TerminalSession(
                    id: terminalSessionID,
                    spaceID: spaceID,
                    executionContextID: executionContextID,
                    title: command.title,
                    tmuxSessionName: launch.tmuxSessionName,
                    paneID: launch.paneID,
                    initialCommand: command.initialCommand
                )
                _ = try await self.storage.transact { $0.terminalSessions.append(session) }
                return try TypedPayload(CreateTerminalSessionResultPayload(session: session))
            }
            kind = .commandResult
        case .command where envelope.payload.identifier == CreateSpaceCommandPayload.identifier:
            let command = try CreateSpaceCommandPayload(protobufBytes: envelope.payload.protobufBytes)
            payload = try await executeDurably(envelope: envelope, spaceID: nil) {
                let space = Space(name: command.name, icon: command.icon, summary: command.summary)
                _ = try await self.storage.transact { $0.spaces.append(space) }
                return try TypedPayload(CreateSpaceResultPayload(spaceID: space.id.description))
            }
            kind = .commandResult
        case .command where envelope.payload.identifier == RenameSpaceCommandPayload.identifier:
            let command = try RenameSpaceCommandPayload(protobufBytes: envelope.payload.protobufBytes)
            let spaceID = try Self.spaceID(from: command.spaceID)
            payload = try await executeDurably(envelope: envelope, spaceID: spaceID) {
                _ = try await self.storage.transact { snapshot in
                    guard let index = snapshot.spaces.firstIndex(where: { $0.id == spaceID }) else { throw HostProtocolError.unknownSpace(spaceID) }
                    snapshot.spaces[index].name = command.name
                }
                return try TypedPayload(SpaceMutationResultPayload())
            }
            kind = .commandResult
        case .command where envelope.payload.identifier == DeleteSpaceCommandPayload.identifier:
            let command = try DeleteSpaceCommandPayload(protobufBytes: envelope.payload.protobufBytes)
            let spaceID = try Self.spaceID(from: command.spaceID)
            if let replayed = try await durableReplayResult(for: envelope) {
                payload = replayed
            } else {
                payload = try await executeDurably(envelope: envelope, spaceID: spaceID) {
                    _ = try await self.storage.transact { snapshot in
                        guard snapshot.spaces.contains(where: { $0.id == spaceID }) else { throw HostProtocolError.unknownSpace(spaceID) }
                        guard !snapshot.sessions.contains(where: { $0.spaceID == spaceID }) &&
                            !snapshot.resources.contains(where: { $0.spaceID == spaceID }) &&
                            !snapshot.executionContexts.contains(where: { $0.spaceID == spaceID }) &&
                            !snapshot.runs.contains(where: { $0.spaceID == spaceID }) &&
                            !snapshot.operations.contains(where: { $0.spaceID == spaceID }) &&
                            !snapshot.artifacts.contains(where: { $0.spaceID == spaceID }) else {
                            throw HostProtocolError.spaceNotEmpty(spaceID)
                        }
                        snapshot.spaces.removeAll(where: { $0.id == spaceID })
                    }
                    return try TypedPayload(SpaceMutationResultPayload())
                }
            }
            kind = .commandResult
        case .command where envelope.payload.identifier == CreateConversationCommandPayload.identifier:
            let command = try CreateConversationCommandPayload(protobufBytes: envelope.payload.protobufBytes)
            let spaceID = try Self.spaceID(from: command.spaceID)
            payload = try await executeDurably(envelope: envelope, spaceID: spaceID) {
                let session = Session(spaceID: spaceID, kind: .conversation, title: command.title)
                _ = try await self.storage.transact { snapshot in
                    guard snapshot.spaces.contains(where: { $0.id == spaceID }) else { throw HostProtocolError.unknownSpace(spaceID) }
                    snapshot.sessions.append(session)
                }
                return try TypedPayload(CreateConversationResultPayload(sessionID: session.id.description))
            }
            kind = .commandResult
        case .command where envelope.payload.identifier == SendConversationCommandPayload.identifier:
            guard let conversationRuns else { throw HostProtocolError.runtimeUnavailable }
            let command = try SendConversationCommandPayload(protobufBytes: envelope.payload.protobufBytes)
            guard let rawSpaceID = UUID(uuidString: command.spaceID),
                let rawSessionID = UUID(uuidString: command.sessionID),
                let rawMessageID = UUID(uuidString: command.messageID),
                let rawRunID = UUID(uuidString: command.runID) else {
                throw HostProtocolError.invalidIdentity("Conversation send")
            }
            let spaceID = SpaceID(rawValue: rawSpaceID)
            let sessionID = SessionID(rawValue: rawSessionID)
            let runID = RunID(rawValue: rawRunID)
            let message = ConversationMessage(
                id: ConversationMessageID(rawValue: rawMessageID),
                spaceID: spaceID,
                sessionID: sessionID,
                role: .user,
                content: command.content
            )
            payload = try await executeDurably(envelope: envelope, spaceID: spaceID) {
                let executionContextID = try await self.executionContext(for: sessionID, in: spaceID)
                try await conversationRuns.submit(
                    message: message,
                    run: Run(id: runID, spaceID: spaceID, sessionID: sessionID, executionContextID: executionContextID)
                )
                return try TypedPayload(SendConversationResultPayload(runID: runID.description))
            }
            kind = .commandResult
        case .command where envelope.payload.identifier == CancelRunCommandPayload.identifier:
            guard let conversationRuns else { throw HostProtocolError.runtimeUnavailable }
            let command = try CancelRunCommandPayload(protobufBytes: envelope.payload.protobufBytes)
            guard let rawRunID = UUID(uuidString: command.runID) else { throw HostProtocolError.invalidIdentity(command.runID) }
            let runID = RunID(rawValue: rawRunID)
            guard let spaceID = try await storage.load().runs.first(where: { $0.id == runID })?.spaceID else {
                throw HostProtocolError.unknownRun(runID)
            }
            payload = try await executeDurably(envelope: envelope, spaceID: spaceID) {
                try await conversationRuns.cancel(runID: runID)
                return try TypedPayload(CancelRunResultPayload())
            }
            kind = .commandResult
        case .command where envelope.payload.identifier == ConfigureAgentLaunchCommandPayload.identifier:
            let command = try ConfigureAgentLaunchCommandPayload(protobufBytes: envelope.payload.protobufBytes)
            guard let agentLaunchConfiguration else { throw HostProtocolError.runtimeUnavailable }
            payload = try await executeDurably(envelope: envelope, spaceID: nil) {
                try await agentLaunchConfiguration.updateAgentLaunchConfiguration(command)
                return try TypedPayload(ConfigureAgentLaunchResultPayload())
            }
            kind = .commandResult
        case .command where envelope.payload.identifier == ImportLocalFolderCommandPayload.identifier:
            let command = try ImportLocalFolderCommandPayload(protobufBytes: envelope.payload.protobufBytes)
            let spaceID = try Self.spaceID(from: command.spaceID)
            payload = try await executeDurably(envelope: envelope, spaceID: spaceID) {
                let directory = try Self.localDirectory(from: command.path)
                let resource = Resource(
                    spaceID: spaceID,
                    kind: .folder,
                    title: command.title ?? directory.lastPathComponent,
                    details: .hostPrivate(HostPrivateReference(rawValue: "local-folder:\(directory.path)"))
                )
                let snapshot = try await self.storage.transact { snapshot in
                    guard snapshot.spaces.contains(where: { $0.id == spaceID }) else { throw HostProtocolError.unknownSpace(spaceID) }
                    if let existing = snapshot.resources.first(where: { $0.details == resource.details }) {
                        guard existing.spaceID == spaceID else {
                            throw HostProtocolError.duplicateResource(existing.id)
                        }
                        return
                    }
                    snapshot.resources.append(resource)
                }
                guard let importedResource = snapshot.resources.first(where: { $0.details == resource.details }) else {
                    throw HostProtocolError.unknownResource(resource.id)
                }
                return try TypedPayload(ImportLocalFolderResultPayload(resourceID: importedResource.id.description))
            }
            kind = .commandResult
        case .command where envelope.payload.identifier == ImportLocalRepositoryCommandPayload.identifier:
            let command = try ImportLocalRepositoryCommandPayload(protobufBytes: envelope.payload.protobufBytes)
            let spaceID = try Self.spaceID(from: command.spaceID)
            payload = try await executeDurably(envelope: envelope, spaceID: spaceID) {
                let directory = try Self.localDirectory(from: command.path)
                guard Self.isGitRepository(directory) else { throw HostProtocolError.invalidResourcePath(directory.path) }
                let resource = Resource(spaceID: spaceID, kind: .repository, title: command.title ?? directory.lastPathComponent, details: .hostPrivate(.init(rawValue: "local-repository:\(directory.path)")))
                let snapshot = try await self.storage.transact { snapshot in
                    guard snapshot.spaces.contains(where: { $0.id == spaceID }) else { throw HostProtocolError.unknownSpace(spaceID) }
                    if let existing = snapshot.resources.first(where: { $0.details == resource.details }) {
                        guard existing.spaceID == spaceID else { throw HostProtocolError.duplicateResource(existing.id) }
                        return
                    }
                    snapshot.resources.append(resource)
                }
                guard let imported = snapshot.resources.first(where: { $0.details == resource.details }) else { throw HostProtocolError.unknownResource(resource.id) }
                return try TypedPayload(ImportLocalRepositoryResultPayload(resourceID: imported.id.description))
            }
            kind = .commandResult
        case .command where envelope.payload.identifier == ImportWebResourceCommandPayload.identifier:
            let command = try ImportWebResourceCommandPayload(protobufBytes: envelope.payload.protobufBytes)
            let spaceID = try Self.spaceID(from: command.spaceID)
            payload = try await executeDurably(envelope: envelope, spaceID: spaceID) {
                guard let scheme = command.url.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
                    throw HostProtocolError.invalidResourcePath(command.url.absoluteString)
                }
                let resource = Resource(
                    spaceID: spaceID,
                    kind: .webSource,
                    title: command.title ?? command.url.host ?? command.url.absoluteString,
                    details: .web(WebResourceDetails(url: command.url))
                )
                let snapshot = try await self.storage.transact { snapshot in
                    guard snapshot.spaces.contains(where: { $0.id == spaceID }) else {
                        throw HostProtocolError.unknownSpace(spaceID)
                    }
                    if let existing = snapshot.resources.first(where: { $0.details == resource.details }) {
                        guard existing.spaceID == spaceID else {
                            throw HostProtocolError.duplicateResource(existing.id)
                        }
                        return
                    }
                    snapshot.resources.append(resource)
                }
                guard let imported = snapshot.resources.first(where: { $0.details == resource.details }) else {
                    throw HostProtocolError.unknownResource(resource.id)
                }
                return try TypedPayload(ImportWebResourceResultPayload(resourceID: imported.id.description))
            }
            kind = .commandResult
        case .command where envelope.payload.identifier == RemoveResourceCommandPayload.identifier:
            let command = try RemoveResourceCommandPayload(protobufBytes: envelope.payload.protobufBytes)
            guard let uuid = UUID(uuidString: command.resourceID) else { throw HostProtocolError.invalidIdentity(command.resourceID) }
            let resourceID = ResourceID(rawValue: uuid)
            if let replayed = try await durableReplayResult(for: envelope) {
                payload = replayed
            } else {
                guard let spaceID = try await storage.load().resources.first(where: { $0.id == resourceID })?.spaceID else {
                    throw HostProtocolError.unknownResource(resourceID)
                }
                payload = try await executeDurably(envelope: envelope, spaceID: spaceID) {
                    _ = try await self.storage.transact { snapshot in
                        guard snapshot.resources.contains(where: { $0.id == resourceID }) else { throw HostProtocolError.unknownResource(resourceID) }
                        guard !snapshot.executionContexts.contains(where: { $0.resourceID == resourceID }) else {
                            throw HostProtocolError.resourceInUse(resourceID)
                        }
                        snapshot.resources.removeAll(where: { $0.id == resourceID })
                    }
                    return try TypedPayload(ResourceMutationResultPayload())
                }
            }
            kind = .commandResult
        case .command where envelope.payload.identifier == RefreshRepositoryResourceCommandPayload.identifier:
            let command = try RefreshRepositoryResourceCommandPayload(protobufBytes: envelope.payload.protobufBytes)
            let resourceID = try Self.resourceID(from: command.resourceID)
            guard let resource = try await storage.load().resources.first(where: { $0.id == resourceID }) else {
                throw HostProtocolError.unknownResource(resourceID)
            }
            payload = try await executeDurably(envelope: envelope, spaceID: resource.spaceID) {
                guard resource.kind == .repository,
                      case let .hostPrivate(reference) = resource.details,
                      reference.rawValue.hasPrefix("local-repository:") else {
                    throw HostProtocolError.invalidResourcePath(resource.title)
                }
                let path = String(reference.rawValue.dropFirst("local-repository:".count))
                let state = Self.repositoryState(at: path)
                return try TypedPayload(RefreshRepositoryResourceResultPayload(
                    resourceID: resourceID.description,
                    availability: state.availability,
                    branch: state.branch,
                    isDetached: state.isDetached,
                    hasSubmodules: state.hasSubmodules,
                    isRebaseInProgress: state.isRebaseInProgress
                ))
            }
            kind = .commandResult
        case .query where envelope.payload.identifier == ReadRepositoryStatusQueryPayload.identifier:
            guard let repositoryStatusReader else { throw HostProtocolError.runtimeUnavailable }
            let query = try ReadRepositoryStatusQueryPayload(protobufBytes: envelope.payload.protobufBytes)
            let resourceID = try Self.resourceID(from: query.resourceID)
            guard let resource = try await storage.load().resources.first(where: { $0.id == resourceID }) else {
                throw HostProtocolError.unknownResource(resourceID)
            }
            guard resource.kind == .repository, let repositoryURL = try Self.localResourceDirectory(for: resource) else {
                throw HostProtocolError.invalidResourcePath(resource.title)
            }
            let status = try await repositoryStatusReader.status(at: repositoryURL, maximumEntries: Int(query.maximumEntries))
            kind = .queryResponse
            payload = try TypedPayload(ReadRepositoryStatusResponsePayload(
                resourceID: resourceID.description,
                repositoryRevision: status.repositoryRevision,
                indexRevision: status.indexRevision,
                entries: status.entries.map { .init(path: $0.path, indexStatus: $0.indexStatus, worktreeStatus: $0.worktreeStatus) },
                truncated: status.truncated
            ))
        case .query where envelope.payload.identifier == ReadRepositoryDiffQueryPayload.identifier:
            guard let repositoryDiffReader else { throw HostProtocolError.runtimeUnavailable }
            let query = try ReadRepositoryDiffQueryPayload(protobufBytes: envelope.payload.protobufBytes)
            let resourceID = try Self.resourceID(from: query.resourceID)
            guard let resource = try await storage.load().resources.first(where: { $0.id == resourceID }) else { throw HostProtocolError.unknownResource(resourceID) }
            guard resource.kind == .repository, let repositoryURL = try Self.localResourceDirectory(for: resource) else { throw HostProtocolError.invalidResourcePath(resource.title) }
            let diff = try await repositoryDiffReader.diff(at: repositoryURL, relativePath: query.relativePath, maximumBytes: Int(query.maximumBytes))
            kind = .queryResponse
            payload = try TypedPayload(ReadRepositoryDiffResponsePayload(resourceID: resourceID.description, repositoryRevision: diff.repositoryRevision, indexRevision: diff.indexRevision, unifiedDiff: diff.unifiedDiff, truncated: diff.truncated))
        case .query where envelope.payload.identifier == ReadRepositoryHistoryQueryPayload.identifier:
            guard let repositoryHistoryReader else { throw HostProtocolError.runtimeUnavailable }
            let query = try ReadRepositoryHistoryQueryPayload(protobufBytes: envelope.payload.protobufBytes)
            let resourceID = try Self.resourceID(from: query.resourceID)
            guard let resource = try await storage.load().resources.first(where: { $0.id == resourceID }), resource.kind == .repository, let repositoryURL = try Self.localResourceDirectory(for: resource) else { throw HostProtocolError.unknownResource(resourceID) }
            let history = try await repositoryHistoryReader.history(at: repositoryURL, maximumCommits: Int(query.maximumCommits))
            kind = .queryResponse
            payload = try TypedPayload(ReadRepositoryHistoryResponsePayload(resourceID: resourceID.description, repositoryRevision: history.repositoryRevision, indexRevision: history.indexRevision, branch: history.branch, isDetached: history.isDetached, commits: history.commits.map { .init(revision: $0.revision, subject: $0.subject, authorName: $0.authorName, authoredAtUnixMilliseconds: $0.authoredAtUnixMilliseconds) }, truncated: history.truncated))
        case .query where envelope.payload.identifier == ReadRepositoryBranchesQueryPayload.identifier:
            guard let repositoryBranchReader else { throw HostProtocolError.runtimeUnavailable }
            let query = try ReadRepositoryBranchesQueryPayload(protobufBytes: envelope.payload.protobufBytes)
            let resourceID = try Self.resourceID(from: query.resourceID)
            guard let resource = try await storage.load().resources.first(where: { $0.id == resourceID }), resource.kind == .repository, let repositoryURL = try Self.localResourceDirectory(for: resource) else { throw HostProtocolError.unknownResource(resourceID) }
            let branches = try await repositoryBranchReader.branches(at: repositoryURL, maximumBranches: Int(query.maximumBranches))
            kind = .queryResponse
            payload = try TypedPayload(ReadRepositoryBranchesResponsePayload(resourceID: resourceID.description, repositoryRevision: branches.repositoryRevision, indexRevision: branches.indexRevision, branches: branches.branches.map { .init(name: $0.name, revision: $0.revision, isCurrent: $0.isCurrent) }, truncated: branches.truncated))
        case .command where envelope.payload.identifier == UpdateRepositoryIndexCommandPayload.identifier:
            guard let repositoryIndexUpdater else { throw HostProtocolError.runtimeUnavailable }
            let command = try UpdateRepositoryIndexCommandPayload(protobufBytes: envelope.payload.protobufBytes)
            let resourceID = try Self.resourceID(from: command.resourceID)
            guard let resource = try await storage.load().resources.first(where: { $0.id == resourceID }), resource.kind == .repository, let repositoryURL = try Self.localResourceDirectory(for: resource) else { throw HostProtocolError.unknownResource(resourceID) }
            payload = try await executeDurably(envelope: envelope, spaceID: resource.spaceID) {
                let operation = Operation(spaceID: resource.spaceID, lifecycle: .running, progress: 0)
                _ = try await self.storage.transact { $0.operations.append(operation) }
                do {
                    let revision = try await repositoryIndexUpdater.updateIndex(
                        at: repositoryURL,
                        relativePaths: command.relativePaths,
                        expectedIndexRevision: command.expectedIndexRevision,
                        stage: command.stage
                    )
                    _ = try await self.storage.transact { snapshot in
                        guard let index = snapshot.operations.firstIndex(where: { $0.id == operation.id }) else { return }
                        snapshot.operations[index].lifecycle = .completed
                        snapshot.operations[index].progress = 1
                    }
                    return try TypedPayload(UpdateRepositoryIndexResultPayload(indexRevision: revision, operationID: operation.id.description))
                } catch {
                    _ = try? await self.storage.transact { snapshot in
                        guard let index = snapshot.operations.firstIndex(where: { $0.id == operation.id }) else { return }
                        snapshot.operations[index].lifecycle = .failed
                        snapshot.operations[index].failureDescription = error.localizedDescription
                    }
                    throw error
                }
            }
            kind = .commandResult
        case .command where envelope.payload.identifier == CommitRepositoryCommandPayload.identifier:
            guard let repositoryCommitter else { throw HostProtocolError.runtimeUnavailable }
            let command = try CommitRepositoryCommandPayload(protobufBytes: envelope.payload.protobufBytes)
            let resourceID = try Self.resourceID(from: command.resourceID)
            guard let resource = try await storage.load().resources.first(where: { $0.id == resourceID }), resource.kind == .repository, let repositoryURL = try Self.localResourceDirectory(for: resource) else { throw HostProtocolError.unknownResource(resourceID) }
            payload = try await executeDurably(envelope: envelope, spaceID: resource.spaceID) {
                let operation = Operation(spaceID: resource.spaceID, lifecycle: .running, progress: 0)
                _ = try await self.storage.transact { $0.operations.append(operation) }
                do {
                    let result = try await repositoryCommitter.commit(at: repositoryURL, message: command.message, expectedRepositoryRevision: command.expectedRepositoryRevision, expectedIndexRevision: command.expectedIndexRevision, amend: command.amend)
                    _ = try await self.storage.transact { snapshot in
                        guard let index = snapshot.operations.firstIndex(where: { $0.id == operation.id }) else { return }
                        snapshot.operations[index].lifecycle = .completed
                        snapshot.operations[index].progress = 1
                    }
                    return try TypedPayload(CommitRepositoryResultPayload(repositoryRevision: result.repositoryRevision, indexRevision: result.indexRevision, operationID: operation.id.description))
                } catch {
                    _ = try? await self.storage.transact { snapshot in
                        guard let index = snapshot.operations.firstIndex(where: { $0.id == operation.id }) else { return }
                        snapshot.operations[index].lifecycle = .failed
                        snapshot.operations[index].failureDescription = error.localizedDescription
                    }
                    throw error
                }
            }
            kind = .commandResult
        case .command where envelope.payload.identifier == UpdateRepositoryBranchCommandPayload.identifier:
            guard let repositoryBranchUpdater else { throw HostProtocolError.runtimeUnavailable }
            let command = try UpdateRepositoryBranchCommandPayload(protobufBytes: envelope.payload.protobufBytes)
            let resourceID = try Self.resourceID(from: command.resourceID)
            guard let resource = try await storage.load().resources.first(where: { $0.id == resourceID }), resource.kind == .repository, let repositoryURL = try Self.localResourceDirectory(for: resource) else { throw HostProtocolError.unknownResource(resourceID) }
            payload = try await executeDurably(envelope: envelope, spaceID: resource.spaceID) {
                let operation = Operation(spaceID: resource.spaceID, lifecycle: .running, progress: 0)
                _ = try await self.storage.transact { $0.operations.append(operation) }
                do {
                    let result = try await repositoryBranchUpdater.updateBranch(at: repositoryURL, branchName: command.branchName, expectedRepositoryRevision: command.expectedRepositoryRevision, expectedIndexRevision: command.expectedIndexRevision, create: command.create)
                    _ = try await self.storage.transact { snapshot in
                        guard let index = snapshot.operations.firstIndex(where: { $0.id == operation.id }) else { return }
                        snapshot.operations[index].lifecycle = .completed
                        snapshot.operations[index].progress = 1
                    }
                    return try TypedPayload(UpdateRepositoryBranchResultPayload(repositoryRevision: result.repositoryRevision, indexRevision: result.indexRevision, operationID: operation.id.description))
                } catch {
                    _ = try? await self.storage.transact { snapshot in
                        guard let index = snapshot.operations.firstIndex(where: { $0.id == operation.id }) else { return }
                        snapshot.operations[index].lifecycle = .failed
                        snapshot.operations[index].failureDescription = error.localizedDescription
                    }
                    throw error
                }
            }
            kind = .commandResult
        case .command where envelope.payload.identifier == FetchRepositoryCommandPayload.identifier:
            guard let repositoryFetcher else { throw HostProtocolError.runtimeUnavailable }
            let command = try FetchRepositoryCommandPayload(protobufBytes: envelope.payload.protobufBytes)
            let resourceID = try Self.resourceID(from: command.resourceID)
            guard let resource = try await storage.load().resources.first(where: { $0.id == resourceID }), resource.kind == .repository, let repositoryURL = try Self.localResourceDirectory(for: resource) else { throw HostProtocolError.unknownResource(resourceID) }
            payload = try await executeDurably(envelope: envelope, spaceID: resource.spaceID) {
                let operation = Operation(spaceID: resource.spaceID, lifecycle: .running, progress: 0)
                _ = try await self.storage.transact { $0.operations.append(operation) }
                do {
                    let result = try await repositoryFetcher.fetch(at: repositoryURL, expectedRepositoryRevision: command.expectedRepositoryRevision, expectedIndexRevision: command.expectedIndexRevision)
                    _ = try await self.storage.transact { snapshot in guard let index = snapshot.operations.firstIndex(where: { $0.id == operation.id }) else { return }; snapshot.operations[index].lifecycle = .completed; snapshot.operations[index].progress = 1 }
                    return try TypedPayload(FetchRepositoryResultPayload(repositoryRevision: result.repositoryRevision, indexRevision: result.indexRevision, operationID: operation.id.description))
                } catch {
                    _ = try? await self.storage.transact { snapshot in guard let index = snapshot.operations.firstIndex(where: { $0.id == operation.id }) else { return }; snapshot.operations[index].lifecycle = .failed; snapshot.operations[index].failureDescription = error.localizedDescription }
                    throw error
                }
            }
            kind = .commandResult
        case .command where envelope.payload.identifier == PullRepositoryCommandPayload.identifier:
            guard let repositoryPuller else { throw HostProtocolError.runtimeUnavailable }
            let command = try PullRepositoryCommandPayload(protobufBytes: envelope.payload.protobufBytes)
            let resourceID = try Self.resourceID(from: command.resourceID)
            guard let resource = try await storage.load().resources.first(where: { $0.id == resourceID }), resource.kind == .repository, let repositoryURL = try Self.localResourceDirectory(for: resource) else { throw HostProtocolError.unknownResource(resourceID) }
            payload = try await executeDurably(envelope: envelope, spaceID: resource.spaceID) {
                let operation = Operation(spaceID: resource.spaceID, lifecycle: .running, progress: 0)
                _ = try await self.storage.transact { $0.operations.append(operation) }
                do {
                    let result = try await repositoryPuller.pull(at: repositoryURL, expectedRepositoryRevision: command.expectedRepositoryRevision, expectedIndexRevision: command.expectedIndexRevision)
                    _ = try await self.storage.transact { snapshot in guard let index = snapshot.operations.firstIndex(where: { $0.id == operation.id }) else { return }; snapshot.operations[index].lifecycle = .completed; snapshot.operations[index].progress = 1 }
                    return try TypedPayload(PullRepositoryResultPayload(repositoryRevision: result.repositoryRevision, indexRevision: result.indexRevision, operationID: operation.id.description))
                } catch { _ = try? await self.storage.transact { snapshot in guard let index = snapshot.operations.firstIndex(where: { $0.id == operation.id }) else { return }; snapshot.operations[index].lifecycle = .failed; snapshot.operations[index].failureDescription = error.localizedDescription }; throw error }
            }
            kind = .commandResult
        case .command where envelope.payload.identifier == PushRepositoryCommandPayload.identifier:
            guard let repositoryPusher else { throw HostProtocolError.runtimeUnavailable }
            let command = try PushRepositoryCommandPayload(protobufBytes: envelope.payload.protobufBytes)
            let resourceID = try Self.resourceID(from: command.resourceID)
            guard let resource = try await storage.load().resources.first(where: { $0.id == resourceID }), resource.kind == .repository, let repositoryURL = try Self.localResourceDirectory(for: resource) else { throw HostProtocolError.unknownResource(resourceID) }
            payload = try await executeDurably(envelope: envelope, spaceID: resource.spaceID) {
                let operation = Operation(spaceID: resource.spaceID, lifecycle: .running, progress: 0)
                _ = try await self.storage.transact { $0.operations.append(operation) }
                do {
                    let result = try await repositoryPusher.push(at: repositoryURL, expectedRepositoryRevision: command.expectedRepositoryRevision, expectedIndexRevision: command.expectedIndexRevision)
                    _ = try await self.storage.transact { snapshot in guard let index = snapshot.operations.firstIndex(where: { $0.id == operation.id }) else { return }; snapshot.operations[index].lifecycle = .completed; snapshot.operations[index].progress = 1 }
                    return try TypedPayload(PushRepositoryResultPayload(repositoryRevision: result.repositoryRevision, indexRevision: result.indexRevision, operationID: operation.id.description))
                } catch {
                    _ = try? await self.storage.transact { snapshot in guard let index = snapshot.operations.firstIndex(where: { $0.id == operation.id }) else { return }; snapshot.operations[index].lifecycle = .failed; snapshot.operations[index].failureDescription = error.localizedDescription }
                    throw error
                }
            }
            kind = .commandResult
        case .command where envelope.payload.identifier == CreateLocalFolderContextCommandPayload.identifier:
            let command = try CreateLocalFolderContextCommandPayload(protobufBytes: envelope.payload.protobufBytes)
            let spaceID = try Self.spaceID(from: command.spaceID)
            let resourceID = try Self.resourceID(from: command.resourceID)
            payload = try await executeDurably(envelope: envelope, spaceID: spaceID) {
                let context = ExecutionContext(
                    spaceID: spaceID,
                    kind: .localFolder,
                    resourceID: resourceID,
                    hostReference: HostPrivateReference(rawValue: "resource-context:\(resourceID.description)")
                )
                _ = try await self.storage.transact { snapshot in
                    guard let resource = snapshot.resources.first(where: { $0.id == resourceID && $0.spaceID == spaceID }), resource.kind == .folder else {
                        throw HostProtocolError.unknownResource(resourceID)
                    }
                    guard !snapshot.executionContexts.contains(where: { $0.resourceID == resourceID && $0.kind == .localFolder }) else {
                        throw HostProtocolError.resourceInUse(resourceID)
                    }
                    snapshot.executionContexts.append(context)
                }
                return try TypedPayload(CreateLocalFolderContextResultPayload(contextID: context.id.description))
            }
            kind = .commandResult
        case .command where envelope.payload.identifier == AttachExecutionContextCommandPayload.identifier:
            let command = try AttachExecutionContextCommandPayload(protobufBytes: envelope.payload.protobufBytes)
            let sessionID = try Self.sessionID(from: command.sessionID)
            let contextID = try Self.executionContextID(from: command.contextID)
            guard let spaceID = try await storage.load().executionContexts.first(where: { $0.id == contextID })?.spaceID else {
                throw HostProtocolError.unknownExecutionContext(contextID)
            }
            payload = try await executeDurably(envelope: envelope, spaceID: spaceID) {
                _ = try await self.storage.transact { snapshot in
                    guard let context = snapshot.executionContexts.first(where: { $0.id == contextID }) else {
                        throw HostProtocolError.unknownExecutionContext(contextID)
                    }
                    guard let index = snapshot.sessions.firstIndex(where: { $0.id == sessionID }) else {
                        throw HostProtocolError.unknownSession(sessionID)
                    }
                    guard snapshot.sessions[index].spaceID == context.spaceID else {
                        throw HostProtocolError.invalidExecutionContext(contextID)
                    }
                    snapshot.sessions[index].executionContextID = contextID
                }
                return try TypedPayload(ExecutionContextMutationResultPayload())
            }
            kind = .commandResult
        case .command where envelope.payload.identifier == CreateRepositoryCheckoutContextCommandPayload.identifier:
            let command = try CreateRepositoryCheckoutContextCommandPayload(protobufBytes: envelope.payload.protobufBytes)
            let spaceID = try Self.spaceID(from: command.spaceID)
            let resourceID = try Self.resourceID(from: command.resourceID)
            payload = try await executeDurably(envelope: envelope, spaceID: spaceID) {
                let context = ExecutionContext(spaceID: spaceID, kind: .repositoryCheckout, resourceID: resourceID, hostReference: .init(rawValue: "repository-checkout:\(resourceID.description)"))
                _ = try await self.storage.transact { snapshot in
                    guard let resource = snapshot.resources.first(where: { $0.id == resourceID && $0.spaceID == spaceID }), resource.kind == .repository else { throw HostProtocolError.unknownResource(resourceID) }
                    guard !snapshot.executionContexts.contains(where: { $0.resourceID == resourceID && $0.kind == .repositoryCheckout }) else { throw HostProtocolError.resourceInUse(resourceID) }
                    snapshot.executionContexts.append(context)
                }
                return try TypedPayload(CreateRepositoryCheckoutContextResultPayload(contextID: context.id.description))
            }
            kind = .commandResult
        case .command where envelope.payload.identifier == CreateLinkedWorktreeContextCommandPayload.identifier:
            guard let linkedWorktrees else { throw HostProtocolError.runtimeUnavailable }
            let command = try CreateLinkedWorktreeContextCommandPayload(protobufBytes: envelope.payload.protobufBytes)
            let spaceID = try Self.spaceID(from: command.spaceID)
            let resourceID = try Self.resourceID(from: command.resourceID)
            payload = try await executeDurably(envelope: envelope, spaceID: spaceID) {
                let snapshot = try await self.storage.load()
                guard let resource = snapshot.resources.first(where: { $0.id == resourceID && $0.spaceID == spaceID }),
                      resource.kind == .repository,
                      case let .hostPrivate(reference) = resource.details,
                      reference.rawValue.hasPrefix("local-repository:") else { throw HostProtocolError.unknownResource(resourceID) }
                let source = try Self.localDirectory(from: String(reference.rawValue.dropFirst("local-repository:".count)))
                let destination = URL(fileURLWithPath: command.destinationPath).standardizedFileURL
                guard !FileManager.default.fileExists(atPath: destination.path) else { throw HostProtocolError.invalidResourcePath(command.destinationPath) }
                let operation = Operation(spaceID: spaceID, lifecycle: .running, progress: 0)
                _ = try await self.storage.transact { $0.operations.append(operation) }
                do {
                    try await linkedWorktrees.createLinkedWorktree(source: source, destination: destination, branch: command.branch, createBranch: command.createBranch, baseBranch: command.baseBranch)
                    let context = ExecutionContext(spaceID: spaceID, kind: .gitWorktree, resourceID: resourceID, hostReference: .init(rawValue: "local-worktree:\(destination.path)"))
                    _ = try await self.storage.transact { snapshot in
                        guard !snapshot.executionContexts.contains(where: { $0.hostReference == context.hostReference }) else { throw HostProtocolError.resourceInUse(resourceID) }
                        snapshot.executionContexts.append(context)
                        guard let index = snapshot.operations.firstIndex(where: { $0.id == operation.id }) else { return }
                        snapshot.operations[index].lifecycle = .completed; snapshot.operations[index].progress = 1
                    }
                    return try TypedPayload(CreateLinkedWorktreeContextResultPayload(contextID: context.id.description, operationID: operation.id.description))
                } catch {
                    _ = try? await self.storage.transact { snapshot in
                        guard let index = snapshot.operations.firstIndex(where: { $0.id == operation.id }) else { return }
                        snapshot.operations[index].lifecycle = .failed; snapshot.operations[index].failureDescription = error.localizedDescription
                    }
                    throw error
                }
            }
            kind = .commandResult
        case .command where envelope.payload.identifier == CreateIndependentContextCommandPayload.identifier:
            guard let independentContexts else { throw HostProtocolError.runtimeUnavailable }
            let command = try CreateIndependentContextCommandPayload(protobufBytes: envelope.payload.protobufBytes)
            let spaceID = try Self.spaceID(from: command.spaceID)
            let resourceID = try Self.resourceID(from: command.resourceID)
            payload = try await executeDurably(envelope: envelope, spaceID: spaceID) {
                let snapshot = try await self.storage.load()
                guard let resource = snapshot.resources.first(where: { $0.id == resourceID && $0.spaceID == spaceID }),
                      case let .hostPrivate(reference) = resource.details else { throw HostProtocolError.unknownResource(resourceID) }
                let prefix = resource.kind == .repository ? "local-repository:" : "local-folder:"
                guard reference.rawValue.hasPrefix(prefix) else { throw HostProtocolError.invalidResourcePath(resource.title) }
                let source = try Self.localDirectory(from: String(reference.rawValue.dropFirst(prefix.count)))
                let destination = URL(fileURLWithPath: command.destinationPath).standardizedFileURL
                guard !FileManager.default.fileExists(atPath: destination.path) else { throw HostProtocolError.invalidResourcePath(command.destinationPath) }
                let operation = Operation(spaceID: spaceID, lifecycle: .running, progress: 0)
                _ = try await self.storage.transact { $0.operations.append(operation) }
                do {
                    try await independentContexts.createIndependentContext(source: source, destination: destination, mode: command.mode)
                    let kind: ExecutionContextKind = command.mode == .clone ? .repositoryCheckout : .copiedEnvironment
                    let context = ExecutionContext(spaceID: spaceID, kind: kind, resourceID: resourceID, hostReference: .init(rawValue: "local-independent:\(destination.path)"))
                    _ = try await self.storage.transact { snapshot in
                        snapshot.executionContexts.append(context)
                        guard let index = snapshot.operations.firstIndex(where: { $0.id == operation.id }) else { return }
                        snapshot.operations[index].lifecycle = .completed; snapshot.operations[index].progress = 1
                    }
                    return try TypedPayload(CreateIndependentContextResultPayload(contextID: context.id.description, operationID: operation.id.description))
                } catch {
                    _ = try? await self.storage.transact { snapshot in guard let index = snapshot.operations.firstIndex(where: { $0.id == operation.id }) else { return }; snapshot.operations[index].lifecycle = .failed; snapshot.operations[index].failureDescription = error.localizedDescription }
                    throw error
                }
            }
            kind = .commandResult
        case .command where envelope.payload.identifier == RemoveExecutionContextCommandPayload.identifier:
            let command = try RemoveExecutionContextCommandPayload(protobufBytes: envelope.payload.protobufBytes)
            let contextID = try Self.executionContextID(from: command.contextID)
            if let replayed = try await durableReplayResult(for: envelope) {
                payload = replayed
            } else {
                guard let spaceID = try await storage.load().executionContexts.first(where: { $0.id == contextID })?.spaceID else {
                    throw HostProtocolError.unknownExecutionContext(contextID)
                }
                payload = try await executeDurably(envelope: envelope, spaceID: spaceID) {
                    _ = try await self.storage.transact { snapshot in
                        guard snapshot.executionContexts.contains(where: { $0.id == contextID }) else {
                            throw HostProtocolError.unknownExecutionContext(contextID)
                        }
                        guard !snapshot.sessions.contains(where: { $0.executionContextID == contextID }) else {
                            throw HostProtocolError.executionContextInUse(contextID)
                        }
                        snapshot.executionContexts.removeAll(where: { $0.id == contextID })
                    }
                    return try TypedPayload(ExecutionContextMutationResultPayload())
                }
            }
            kind = .commandResult
        case .command where envelope.payload.identifier == DetachExecutionContextCommandPayload.identifier:
            let command = try DetachExecutionContextCommandPayload(protobufBytes: envelope.payload.protobufBytes)
            let sessionID = try Self.sessionID(from: command.sessionID)
            guard let spaceID = try await storage.load().sessions.first(where: { $0.id == sessionID })?.spaceID else {
                throw HostProtocolError.unknownSession(sessionID)
            }
            payload = try await executeDurably(envelope: envelope, spaceID: spaceID) {
                _ = try await self.storage.transact { snapshot in
                    guard let index = snapshot.sessions.firstIndex(where: { $0.id == sessionID }) else {
                        throw HostProtocolError.unknownSession(sessionID)
                    }
                    snapshot.sessions[index].executionContextID = nil
                }
                return try TypedPayload(ExecutionContextMutationResultPayload())
            }
            kind = .commandResult
        default:
            throw HostProtocolError.unsupportedRequest(kind: envelope.kind, payload: envelope.payload.identifier)
        }
        return ProtocolEnvelope(
            messageID: envelope.messageID,
            connectionID: envelope.connectionID,
            connectionSequence: envelope.connectionSequence,
            kind: kind,
            channel: .state,
            correlationID: envelope.correlationID,
            payload: payload
        )
    }

    private static func clientProjection(from snapshot: StorageSnapshot) -> HostProjectionSnapshot {
        HostProjectionSnapshot(
            spaces: snapshot.spaces,
            sessions: snapshot.sessions,
            resources: snapshot.resources.map {
                Resource(id: $0.id, spaceID: $0.spaceID, kind: $0.kind, title: $0.title)
            },
            executionContexts: snapshot.executionContexts.map {
                ExecutionContext(id: $0.id, spaceID: $0.spaceID, kind: $0.kind, resourceID: $0.resourceID)
            },
            terminalSessions: snapshot.terminalSessions,
            operations: snapshot.operations
        )
    }

    private static func spaceID(from value: String) throws -> SpaceID {
        guard let rawValue = UUID(uuidString: value) else { throw HostProtocolError.invalidIdentity(value) }
        return SpaceID(rawValue: rawValue)
    }

    private func executeDurably(
        envelope: ProtocolEnvelope,
        spaceID: SpaceID?,
        operation: () async throws -> TypedPayload
    ) async throws -> TypedPayload {
        if let replayed = try await durableReplayResult(for: envelope) {
            return replayed
        }
        guard let rawCommandID = UUID(uuidString: envelope.messageID) else {
            return try await operation()
        }
        let command = DurableCommand(
            id: CommandID(rawValue: rawCommandID),
            spaceID: spaceID,
            payloadDigest: Self.payloadDigest(envelope.payload)
        )
        switch try await storage.acceptCommand(command) {
        case .accepted:
            _ = try await storage.transitionCommand(id: command.id, to: .executing)
            do {
                let payload = try await operation()
                let result = DurableCommandResult(
                    payloadIdentifier: payload.identifier.rawValue,
                    schemaVersion: payload.schemaVersion,
                    protobufBytes: payload.protobufBytes
                )
                _ = try await storage.transitionCommand(id: command.id, to: .succeeded, result: result)
                _ = try await storage.appendJournalEvent(
                    spaceID: spaceID,
                    aggregateID: command.id.description,
                    aggregateType: "command",
                    aggregateRevision: 1,
                    payloadIdentifier: result.payloadIdentifier,
                    payloadSchemaVersion: result.schemaVersion,
                    payloadBytes: result.protobufBytes,
                    durability: .durable
                )
                return payload
            } catch {
                _ = try? await storage.transitionCommand(id: command.id, to: .failed)
                throw error
            }
        case .duplicate(let stored):
            guard stored.lifecycle == .succeeded, let result = stored.result else {
                throw HostProtocolError.commandIncomplete(command.id)
            }
            return TypedPayload(
                identifier: PayloadIdentifier(rawValue: result.payloadIdentifier),
                schemaVersion: result.schemaVersion,
                protobufBytes: result.protobufBytes,
                stateAffecting: true
            )
        case .conflict:
            throw HostProtocolError.commandIDConflict(command.id)
        }
    }

    private func durableReplayResult(for envelope: ProtocolEnvelope) async throws -> TypedPayload? {
        guard let rawCommandID = UUID(uuidString: envelope.messageID) else { return nil }
        let commandID = CommandID(rawValue: rawCommandID)
        guard let stored = try await storage.load().commands.first(where: { $0.id == commandID }) else { return nil }
        guard stored.payloadDigest == Self.payloadDigest(envelope.payload) else {
            throw HostProtocolError.commandIDConflict(commandID)
        }
        guard stored.lifecycle == .succeeded, let result = stored.result else {
            throw HostProtocolError.commandIncomplete(commandID)
        }
        return TypedPayload(
            identifier: PayloadIdentifier(rawValue: result.payloadIdentifier),
            schemaVersion: result.schemaVersion,
            protobufBytes: result.protobufBytes,
            stateAffecting: true
        )
    }

    private static func payloadDigest(_ payload: TypedPayload) -> String {
        let digest = SHA256.hash(data: payload.protobufBytes)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func sessionID(from value: String) throws -> SessionID {
        guard let rawValue = UUID(uuidString: value) else { throw HostProtocolError.invalidIdentity(value) }
        return SessionID(rawValue: rawValue)
    }

    private static func resourceID(from value: String) throws -> ResourceID {
        guard let rawValue = UUID(uuidString: value) else { throw HostProtocolError.invalidIdentity(value) }
        return ResourceID(rawValue: rawValue)
    }

    private static func operationID(from value: String) throws -> OperationID {
        guard let rawValue = UUID(uuidString: value) else { throw HostProtocolError.invalidIdentity(value) }
        return OperationID(rawValue: rawValue)
    }

    private static func executionContextID(from value: String) throws -> ExecutionContextID {
        guard let rawValue = UUID(uuidString: value) else { throw HostProtocolError.invalidIdentity(value) }
        return ExecutionContextID(rawValue: rawValue)
    }

    private static func localDirectory(from path: String) throws -> URL {
        guard path.hasPrefix("/") else { throw HostProtocolError.invalidResourcePath(path) }
        let directory = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw HostProtocolError.invalidResourcePath(path)
        }
        return directory
    }

    private static func discoverXcodeProject(for resource: Resource) throws -> XcodeProjectDescriptor? {
        guard let directory = try localResourceDirectory(for: resource) else { return nil }
        let entries = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        let candidates = entries.compactMap { url -> (url: URL, kind: XcodeProjectDescriptor.Kind)? in
            switch url.pathExtension {
            case "xcworkspace": return (url, .workspace)
            case "xcodeproj": return (url, .project)
            default: return nil
            }
        }.sorted {
            if $0.kind != $1.kind { return $0.kind == .workspace }
            return $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending
        }
        guard let candidate = candidates.first else { return nil }
        return XcodeProjectDescriptor(resourceID: resource.id, id: candidate.url.lastPathComponent, name: candidate.url.deletingPathExtension().lastPathComponent, kind: candidate.kind, schemes: [])
    }

    private func runXcodeProjectBuild(
        operationID: OperationID,
        build: any XcodeBuildRunning,
        action: XcodeProjectAction
    ) async {
        do {
            try await build.waitForCompletion()
            _ = try await storage.transact { snapshot in
                guard let index = snapshot.operations.firstIndex(where: { $0.id == operationID }) else { return }
                guard snapshot.operations[index].lifecycle == .running else { return }
                snapshot.operations[index].lifecycle = .completed
                snapshot.operations[index].progress = 1
                snapshot.operations[index].result = OperationResult(
                    summary: action == .build ? "Xcode build completed successfully." : "Xcode tests completed successfully."
                )
            }
        } catch {
            _ = try? await storage.transact { snapshot in
                guard let index = snapshot.operations.firstIndex(where: { $0.id == operationID }) else { return }
                guard snapshot.operations[index].lifecycle == .running else { return }
                snapshot.operations[index].lifecycle = .failed
                snapshot.operations[index].failureDescription = error.localizedDescription
            }
        }
        xcodeBuilds.removeValue(forKey: operationID)
    }

    private func persistXcodeBuildOutput(operationID: OperationID, build: any XcodeBuildRunning) async {
        let output = await build.output()
        for await chunk in output {
            _ = try? await storage.appendOperationLogChunk(
                operationID: operationID,
                stream: chunk.stream,
                text: chunk.text
            )
        }
    }

    private func xcodeProject(for resource: Resource) async throws -> XcodeProjectDescriptor? {
        guard let project = try Self.discoverXcodeProject(for: resource) else { return nil }
        guard let xcodeProjectInspector,
              let directory = try Self.localResourceDirectory(for: resource) else { return project }
        let projectURL = directory.appendingPathComponent(project.id)
        async let schemes = xcodeProjectInspector.schemes(for: projectURL, kind: project.kind)
        async let configurations = xcodeProjectInspector.configurations(for: projectURL, kind: project.kind)
        return try await .init(resourceID: project.resourceID, id: project.id, name: project.name, kind: project.kind, schemes: schemes, configurations: configurations)
    }

    private static func localResourceDirectory(for resource: Resource) throws -> URL? {
        guard case let .hostPrivate(reference) = resource.details else { return nil }
        let prefixes = resource.kind == .repository ? ["local-repository:"] : resource.kind == .folder ? ["local-folder:"] : []
        guard let prefix = prefixes.first(where: { reference.rawValue.hasPrefix($0) }) else { return nil }
        return try localDirectory(from: String(reference.rawValue.dropFirst(prefix.count)))
    }

    private static func isGitRepository(_ directory: URL) -> Bool {
        FileManager.default.fileExists(atPath: directory.appendingPathComponent(".git").path)
    }

    private static func repositoryState(at path: String) -> RepositoryFilesystemState {
        guard path.hasPrefix("/") else { return .notRepository }
        let directory = URL(fileURLWithPath: path).standardizedFileURL
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return .missing
        }
        let git = directory.appendingPathComponent(".git")
        guard FileManager.default.fileExists(atPath: git.path) else { return .notRepository }
        let gitDirectory = resolvedGitDirectory(git)
        let head = (try? String(contentsOf: gitDirectory.appendingPathComponent("HEAD"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let branchPrefix = "ref: refs/heads/"
        let branch = head?.hasPrefix(branchPrefix) == true
            ? String(head!.dropFirst(branchPrefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            : nil
        return .init(
            availability: .available,
            branch: branch,
            isDetached: head?.hasPrefix(branchPrefix) == false,
            hasSubmodules: FileManager.default.fileExists(atPath: directory.appendingPathComponent(".gitmodules").path),
            isRebaseInProgress: FileManager.default.fileExists(atPath: gitDirectory.appendingPathComponent("rebase-merge").path) ||
                FileManager.default.fileExists(atPath: gitDirectory.appendingPathComponent("rebase-apply").path)
        )
    }

    private static func resolvedGitDirectory(_ git: URL) -> URL {
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: git.path, isDirectory: &isDirectory), !isDirectory.boolValue,
              let value = try? String(contentsOf: git, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines),
              value.hasPrefix("gitdir: ") else { return git }
        let location = String(value.dropFirst("gitdir: ".count))
        return URL(fileURLWithPath: location, relativeTo: git.deletingLastPathComponent()).standardizedFileURL
    }

    private struct RepositoryFilesystemState {
        let availability: RepositoryResourceAvailability
        let branch: String?
        let isDetached: Bool
        let hasSubmodules: Bool
        let isRebaseInProgress: Bool

        static let missing = Self(availability: .missing, branch: nil, isDetached: false, hasSubmodules: false, isRebaseInProgress: false)
        static let notRepository = Self(availability: .notRepository, branch: nil, isDetached: false, hasSubmodules: false, isRebaseInProgress: false)
    }

    private func executionContext(for sessionID: SessionID, in spaceID: SpaceID) async throws -> ExecutionContextID {
        let snapshot = try await storage.load()
        guard let session = snapshot.sessions.first(where: { $0.id == sessionID && $0.spaceID == spaceID }) else {
            throw HostProtocolError.unknownSession(sessionID)
        }
        if let executionContextID = session.executionContextID {
            if let context = snapshot.executionContexts.first(where: { $0.id == executionContextID }),
                context.kind == .managedTemporarySandbox || context.kind == .managedPersistentSandbox {
                try await managedSandboxes?.touch(context)
            }
            return executionContextID
        }
        guard let managedSandboxes else { throw HostProtocolError.runtimeUnavailable }
        do {
            return try await managedSandboxes.provision(for: sessionID, persistence: .temporary).id
        } catch ManagedSandboxService.Error.sessionAlreadyHasExecutionContext {
            guard let executionContextID = try await storage.load().sessions.first(where: { $0.id == sessionID })?.executionContextID else {
                throw HostProtocolError.unknownSession(sessionID)
            }
            return executionContextID
        }
    }
}

public enum HostProtocolError: Swift.Error, Sendable, Equatable {
    case unsupportedRequest(kind: WireMessageKind, payload: PayloadIdentifier)
    case invalidIdentity(String)
    case unknownSpace(SpaceID)
    case unknownSession(SessionID)
    case unknownRun(RunID)
    case unknownResource(ResourceID)
    case unknownExecutionContext(ExecutionContextID)
    case unknownOperation(OperationID)
    case duplicateTerminalSession(SessionID)
    case duplicateResource(ResourceID)
    case resourceInUse(ResourceID)
    case executionContextInUse(ExecutionContextID)
    case commandIDConflict(CommandID)
    case commandIncomplete(CommandID)
    case invalidResourcePath(String)
    case invalidExecutionContext(ExecutionContextID)
    case invalidTerminalDimensions
    case spaceNotEmpty(SpaceID)
    case runtimeUnavailable

    public var errorCode: HostErrorCode {
        switch self {
        case .unsupportedRequest:
            .unsupportedRequest
        case .invalidIdentity, .invalidResourcePath, .invalidExecutionContext, .invalidTerminalDimensions:
            .invalidRequest
        case .unknownSpace:
            .unknownSpace
        case .unknownSession:
            .unknownSession
        case .unknownRun:
            .unknownRun
        case .unknownResource:
            .unknownResource
        case .unknownExecutionContext:
            .unknownExecutionContext
        case .unknownOperation:
            .unknownOperation
        case .duplicateTerminalSession, .duplicateResource, .resourceInUse, .executionContextInUse, .commandIDConflict, .spaceNotEmpty:
            .conflict
        case .commandIncomplete:
            .commandIncomplete
        case .runtimeUnavailable:
            .unavailable
        }
    }
}

extension LocalHost: RunEventEndpoint {}

/// Host-facing runtime contract. ACP, Process, and UI concerns remain in a macOS adapter.
public protocol RunRuntime: Sendable {
    func start(run: Run) async throws
    func cancel(runID: RunID) async throws
}

/// macOS terminal process management belongs in a platform adapter; the Host owns validation and persistence.
public protocol TerminalRuntime: Sendable {
    func createTerminal(
        id: SessionID,
        spaceID: SpaceID,
        executionContext: ExecutionContext,
        resource: Resource?,
        title: String?,
        initialCommand: String?
    ) async throws -> TerminalLaunch

    /// Returns the persisted sessions that remain attachable after the Host starts again.
    func recoverableTerminalSessionIDs(_ sessions: [TerminalSession]) async throws -> Set<SessionID>

    /// Sends literal bytes to an existing Host-owned terminal. The caller never supplies a shell command.
    func sendInput(to session: TerminalSession, input: Data) async throws

    /// Resizes an existing Host-owned terminal after the Host has validated the requested bounds.
    func resize(session: TerminalSession, columns: Int, rows: Int) async throws

    /// Captures the current bounded terminal scrollback from the Host-owned runtime.
    func captureOutput(for session: TerminalSession, maximumBytes: Int) async throws -> Data
}

public enum TerminalRuntimeError: Swift.Error, Sendable, Equatable {
    case remoteInteractionUnavailable
    case invalidDimensions
}

public extension TerminalRuntime {
    func recoverableTerminalSessionIDs(_ sessions: [TerminalSession]) async throws -> Set<SessionID> {
        Set(sessions.map(\.id))
    }

    func sendInput(to session: TerminalSession, input: Data) async throws {
        throw TerminalRuntimeError.remoteInteractionUnavailable
    }

    func resize(session: TerminalSession, columns: Int, rows: Int) async throws {
        throw TerminalRuntimeError.remoteInteractionUnavailable
    }

    func captureOutput(for session: TerminalSession, maximumBytes: Int) async throws -> Data {
        throw TerminalRuntimeError.remoteInteractionUnavailable
    }
}

public struct TerminalLaunch: Sendable, Equatable {
    public let tmuxSessionName: String
    public let paneID: String

    public init(tmuxSessionName: String, paneID: String) {
        precondition(!tmuxSessionName.isEmpty && !paneID.isEmpty, "Terminal launch requires tmux identities")
        self.tmuxSessionName = tmuxSessionName
        self.paneID = paneID
    }
}

public protocol PromptRunRuntime: RunRuntime {
    func send(
        message: String,
        to runID: RunID,
        onAssistantTextDelta: @escaping @Sendable (String) async -> Void
    ) async throws -> String?
}

public actor RunCoordinator {
    public enum Error: Swift.Error, Sendable, Equatable {
        case duplicateRun(RunID)
        case unknownRun(RunID)
        case invalidTransition(from: RunLifecycle, to: RunLifecycle)
    }

    private let storage: StorageRepository
    private let runtime: any RunRuntime
    private let eventPublisher: RunEventPublisher?

    public init(
        storage: StorageRepository,
        runtime: any RunRuntime,
        eventPublisher: RunEventPublisher? = nil
    ) {
        self.storage = storage
        self.runtime = runtime
        self.eventPublisher = eventPublisher
    }

    public func start(_ run: Run) async throws {
        guard run.lifecycle == .queued else { throw Error.invalidTransition(from: run.lifecycle, to: .running) }
        _ = try await storage.transact { snapshot in
            guard !snapshot.runs.contains(where: { $0.id == run.id }) else { throw Error.duplicateRun(run.id) }
            snapshot.runs.append(run)
        }
        try await updateLifecycle(.preparingContext, for: run.id)
        do {
            try await runtime.start(run: run)
            try await updateLifecycle(.startingAgent, for: run.id)
            try await updateLifecycle(.running, for: run.id)
        } catch {
            try? await updateLifecycle(.failed, for: run.id)
            throw error
        }
    }

    /// Starts a Run that was atomically persisted with another Host-owned command.
    public func startPersisted(_ run: Run) async throws {
        guard try await self.run(for: run.id)?.lifecycle == .queued else { throw Error.invalidTransition(from: run.lifecycle, to: .running) }
        try await updateLifecycle(.preparingContext, for: run.id)
        do {
            try await runtime.start(run: run)
            try await updateLifecycle(.startingAgent, for: run.id)
            try await updateLifecycle(.running, for: run.id)
        } catch {
            try? await updateLifecycle(.failed, for: run.id)
            throw error
        }
    }

    public func complete(_ runID: RunID) async throws {
        try await updateLifecycle(.succeeded, for: runID)
    }

    public func cancel(_ runID: RunID) async throws {
        guard let run = try await run(for: runID) else { throw Error.unknownRun(runID) }
        guard run.lifecycle.canTransition(to: .cancelling) else {
            throw Error.invalidTransition(from: run.lifecycle, to: .cancelling)
        }
        try await updateLifecycle(.cancelling, for: runID)
        do {
            try await runtime.cancel(runID: runID)
            try await updateLifecycle(.cancelled, for: runID)
        } catch {
            try? await updateLifecycle(.failed, for: runID)
            throw error
        }
    }

    public func run(for id: RunID) async throws -> Run? {
        try await storage.load().runs.first(where: { $0.id == id })
    }

    private func updateLifecycle(_ lifecycle: RunLifecycle, for id: RunID) async throws {
        let snapshot = try await storage.transact { snapshot in
            guard let index = snapshot.runs.firstIndex(where: { $0.id == id }) else { throw Error.unknownRun(id) }
            let current = snapshot.runs[index].lifecycle
            guard current.canTransition(to: lifecycle) else {
                throw Error.invalidTransition(from: current, to: lifecycle)
            }
            snapshot.runs[index].lifecycle = lifecycle
        }
        guard let run = snapshot.runs.first(where: { $0.id == id }) else { throw Error.unknownRun(id) }
        await eventPublisher?.publish(for: run, kind: .lifecycle(lifecycle))
    }
}
