import Foundation

public enum AizenCoreModule {
    public static let productVersion = "2.0.0"
    public static let protocolGeneration = 1
    public static let storageSchemaVersion = 2
}

// MARK: - Nominal identities

public protocol DomainIDKind: Sendable {}

public struct DomainID<Kind: DomainIDKind>: RawRepresentable, Codable, Sendable, Hashable, CustomStringConvertible {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    public init() {
        self.init(rawValue: UUID())
    }

    public var description: String { rawValue.uuidString }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue == rhs.rawValue
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(rawValue)
    }
}

public enum AccountIdentity: DomainIDKind {}
public enum HostIdentity: DomainIDKind {}
public enum DeviceIdentity: DomainIDKind {}
public enum SpaceIdentity: DomainIDKind {}
public enum SessionIdentity: DomainIDKind {}
public enum ConversationMessageIdentity: DomainIDKind {}
public enum ResourceIdentity: DomainIDKind {}
public enum ExecutionContextIdentity: DomainIDKind {}
public enum RunIdentity: DomainIDKind {}
public enum OperationIdentity: DomainIDKind {}
public enum ArtifactIdentity: DomainIDKind {}
public enum CommandIdentity: DomainIDKind {}

public typealias AccountID = DomainID<AccountIdentity>
public typealias HostID = DomainID<HostIdentity>
public typealias DeviceID = DomainID<DeviceIdentity>
public typealias SpaceID = DomainID<SpaceIdentity>
public typealias SessionID = DomainID<SessionIdentity>
public typealias ConversationMessageID = DomainID<ConversationMessageIdentity>
public typealias ResourceID = DomainID<ResourceIdentity>
public typealias ExecutionContextID = DomainID<ExecutionContextIdentity>
public typealias RunID = DomainID<RunIdentity>
public typealias OperationID = DomainID<OperationIdentity>
public typealias ArtifactID = DomainID<ArtifactIdentity>
public typealias CommandID = DomainID<CommandIdentity>

/// An opaque identifier to a secret or platform credential held outside Core and Storage snapshots.
public struct SecureReferenceID: RawRepresentable, Codable, Sendable, Hashable {
    public let rawValue: String

    public init(rawValue: String) {
        precondition(!rawValue.isEmpty, "Secure references require an identifier")
        self.rawValue = rawValue
    }
}

// MARK: - Extensible classifications

public protocol ExtensibleKind: RawRepresentable, Codable, Sendable, Hashable where RawValue == String {
    init(rawValue: String)
}

public struct SessionKind: ExtensibleKind {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let conversation = Self(rawValue: "conversation")
    public static let research = Self(rawValue: "research")
    public static let coding = Self(rawValue: "coding")
    public static let planning = Self(rawValue: "planning")
}

public struct ResourceKind: ExtensibleKind {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let repository = Self(rawValue: "repository")
    public static let folder = Self(rawValue: "folder")
    public static let document = Self(rawValue: "document")
    public static let file = Self(rawValue: "file")
    public static let webSource = Self(rawValue: "web-source")
    public static let dataset = Self(rawValue: "dataset")
    public static let database = Self(rawValue: "database")
    public static let server = Self(rawValue: "server")
    public static let artifact = Self(rawValue: "artifact")
}

public struct ExecutionContextKind: ExtensibleKind {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let virtual = Self(rawValue: "virtual")
    public static let managedTemporarySandbox = Self(rawValue: "managed-temporary-sandbox")
    public static let managedPersistentSandbox = Self(rawValue: "managed-persistent-sandbox")
    public static let localFolder = Self(rawValue: "local-folder")
    public static let repositoryCheckout = Self(rawValue: "repository-checkout")
    public static let gitWorktree = Self(rawValue: "git-worktree")
    public static let copiedEnvironment = Self(rawValue: "copied-environment")
    public static let remoteEnvironment = Self(rawValue: "remote-environment")
    public static let container = Self(rawValue: "container")
    public static let virtualMachine = Self(rawValue: "virtual-machine")
}

// MARK: - Space

public struct SpaceConfiguration: Codable, Sendable, Hashable {
    public var accountReferences: Set<SecureReferenceID>
    public var providerReferences: Set<SecureReferenceID>
    public var agentConfigurationReferences: Set<SecureReferenceID>
    public var mcpConfigurationReferences: Set<SecureReferenceID>
    public var memoryConfigurationReferences: Set<SecureReferenceID>
    public var searchConfigurationReferences: Set<SecureReferenceID>
    public var settingsReference: SecureReferenceID?
    public var appearanceReference: SecureReferenceID?

    public init(
        accountReferences: Set<SecureReferenceID> = [],
        providerReferences: Set<SecureReferenceID> = [],
        agentConfigurationReferences: Set<SecureReferenceID> = [],
        mcpConfigurationReferences: Set<SecureReferenceID> = [],
        memoryConfigurationReferences: Set<SecureReferenceID> = [],
        searchConfigurationReferences: Set<SecureReferenceID> = [],
        settingsReference: SecureReferenceID? = nil,
        appearanceReference: SecureReferenceID? = nil
    ) {
        self.accountReferences = accountReferences
        self.providerReferences = providerReferences
        self.agentConfigurationReferences = agentConfigurationReferences
        self.mcpConfigurationReferences = mcpConfigurationReferences
        self.memoryConfigurationReferences = memoryConfigurationReferences
        self.searchConfigurationReferences = searchConfigurationReferences
        self.settingsReference = settingsReference
        self.appearanceReference = appearanceReference
    }
}

public struct Space: Codable, Sendable, Hashable, Identifiable {
    public let id: SpaceID
    public var name: String
    public var icon: String?
    public var summary: String?
    public var ownerAccountID: AccountID?
    public var configuration: SpaceConfiguration

    public init(
        id: SpaceID = SpaceID(),
        name: String,
        icon: String? = nil,
        summary: String? = nil,
        ownerAccountID: AccountID? = nil,
        configuration: SpaceConfiguration = .init()
    ) {
        precondition(!name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "A Space needs a name")
        self.id = id
        self.name = name
        self.icon = icon
        self.summary = summary
        self.ownerAccountID = ownerAccountID
        self.configuration = configuration
    }
}

// MARK: - Sessions, resources, and execution contexts

public enum SessionLifecycle: String, Codable, Sendable, Hashable {
    case active
    case archived
}

public struct Session: Codable, Sendable, Hashable, Identifiable {
    public let id: SessionID
    public let spaceID: SpaceID
    public var kind: SessionKind
    public var title: String
    public var lifecycle: SessionLifecycle
    public var resourceIDs: Set<ResourceID>
    public var executionContextID: ExecutionContextID?

    public init(
        id: SessionID = SessionID(),
        spaceID: SpaceID,
        kind: SessionKind,
        title: String,
        lifecycle: SessionLifecycle = .active,
        resourceIDs: Set<ResourceID> = [],
        executionContextID: ExecutionContextID? = nil
    ) {
        precondition(!title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "A Session needs a title")
        self.id = id
        self.spaceID = spaceID
        self.kind = kind
        self.title = title
        self.lifecycle = lifecycle
        self.resourceIDs = resourceIDs
        self.executionContextID = executionContextID
    }
}

public enum ConversationMessageRole: String, Codable, Sendable, Hashable {
    case user
    case assistant
    case system
    case tool
}

/// Canonical durable turn content. Streaming deltas remain Client state until committed as a message.
public struct ConversationMessage: Codable, Sendable, Hashable, Identifiable {
    public let id: ConversationMessageID
    public let spaceID: SpaceID
    public let sessionID: SessionID
    public var runID: RunID?
    public var role: ConversationMessageRole
    public var content: String
    public let createdAt: Date

    public init(
        id: ConversationMessageID = ConversationMessageID(),
        spaceID: SpaceID,
        sessionID: SessionID,
        runID: RunID? = nil,
        role: ConversationMessageRole,
        content: String,
        createdAt: Date = Date()
    ) {
        precondition(!content.isEmpty, "Conversation messages require content")
        self.id = id
        self.spaceID = spaceID
        self.sessionID = sessionID
        self.runID = runID
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}

/// A Host-private reference to platform details such as a bookmark, path, token, or credential.
public struct HostPrivateReference: RawRepresentable, Codable, Sendable, Hashable {
    public let rawValue: String
    public init(rawValue: String) {
        precondition(!rawValue.isEmpty, "Host references require an identifier")
        self.rawValue = rawValue
    }
}

public struct RepositoryResourceDetails: Codable, Sendable, Hashable {
    public let hostReference: HostPrivateReference
    public let defaultBranch: String?

    public init(hostReference: HostPrivateReference, defaultBranch: String? = nil) {
        self.hostReference = hostReference
        self.defaultBranch = defaultBranch
    }
}

public struct WebResourceDetails: Codable, Sendable, Hashable {
    public let url: URL
    public init(url: URL) { self.url = url }
}

public enum ResourceDetails: Codable, Sendable, Hashable {
    case repository(RepositoryResourceDetails)
    case web(WebResourceDetails)
    case hostPrivate(HostPrivateReference)
    case none
}

public struct Resource: Codable, Sendable, Hashable, Identifiable {
    public let id: ResourceID
    public let spaceID: SpaceID
    public var kind: ResourceKind
    public var title: String
    public var details: ResourceDetails

    public init(id: ResourceID = ResourceID(), spaceID: SpaceID, kind: ResourceKind, title: String, details: ResourceDetails = .none) {
        precondition(!title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "A Resource needs a title")
        self.id = id
        self.spaceID = spaceID
        self.kind = kind
        self.title = title
        self.details = details
    }
}

public struct ExecutionContext: Codable, Sendable, Hashable, Identifiable {
    public let id: ExecutionContextID
    public let spaceID: SpaceID
    public var kind: ExecutionContextKind
    public var resourceID: ResourceID?
    public var hostReference: HostPrivateReference?

    public init(
        id: ExecutionContextID = ExecutionContextID(),
        spaceID: SpaceID,
        kind: ExecutionContextKind,
        resourceID: ResourceID? = nil,
        hostReference: HostPrivateReference? = nil
    ) {
        self.id = id
        self.spaceID = spaceID
        self.kind = kind
        self.resourceID = resourceID
        self.hostReference = hostReference
    }
}

/// The client-safe, recoverable portion of Host state.
///
/// Storage may retain additional operational and security records, but clients rebuild feature
/// projections only from these stable domain snapshots.
public struct HostProjectionSnapshot: Codable, Sendable, Hashable {
    public let spaces: [Space]
    public let sessions: [Session]
    public let resources: [Resource]
    public let executionContexts: [ExecutionContext]
    public let terminalSessions: [TerminalSession]
    public let operations: [Operation]

    public init(
        spaces: [Space] = [],
        sessions: [Session] = [],
        resources: [Resource] = [],
        executionContexts: [ExecutionContext] = [],
        terminalSessions: [TerminalSession] = [],
        operations: [Operation] = []
    ) {
        self.spaces = spaces
        self.sessions = sessions
        self.resources = resources
        self.executionContexts = executionContexts
        self.terminalSessions = terminalSessions
        self.operations = operations
    }
}

/// A path-relative entry returned by a Host-owned execution-context filesystem.
public struct ContextFileEntry: Codable, Sendable, Hashable, Identifiable {
    public let relativePath: String
    public let name: String
    public let isDirectory: Bool

    public var id: String { relativePath }

    public init(relativePath: String, name: String, isDirectory: Bool) {
        precondition(!relativePath.hasPrefix("/"), "Context file entries must be relative")
        precondition(!name.isEmpty, "Context file entries need a name")
        self.relativePath = relativePath
        self.name = name
        self.isDirectory = isDirectory
    }
}

/// Host-owned metadata for a persistent terminal runtime. The tmux identity is opaque to clients;
/// they use it only when asking the host/platform adapter to attach.
public struct TerminalSession: Codable, Sendable, Hashable, Identifiable {
    public let id: SessionID
    public let spaceID: SpaceID
    public let executionContextID: ExecutionContextID?
    public var title: String?
    public let tmuxSessionName: String
    public let paneID: String
    public var initialCommand: String?
    public let createdAt: Date

    public init(
        id: SessionID = SessionID(),
        spaceID: SpaceID,
        executionContextID: ExecutionContextID? = nil,
        title: String? = nil,
        tmuxSessionName: String,
        paneID: String,
        initialCommand: String? = nil,
        createdAt: Date = Date()
    ) {
        precondition(!tmuxSessionName.isEmpty && !paneID.isEmpty, "Terminal sessions require tmux and pane identities")
        self.id = id
        self.spaceID = spaceID
        self.executionContextID = executionContextID
        self.title = title
        self.tmuxSessionName = tmuxSessionName
        self.paneID = paneID
        self.initialCommand = initialCommand
        self.createdAt = createdAt
    }
}

// MARK: - Host work

public enum RunLifecycle: String, Codable, Sendable, Hashable {
    case queued
    case preparingContext
    case startingAgent
    case running
    case waitingForPermission
    case cancelling
    case completed
    case succeeded
    case failed
    case cancelled
    case interrupted

    public func canTransition(to next: Self) -> Bool {
        switch (self, next) {
        case (.queued, .preparingContext), (.queued, .failed), (.queued, .cancelled),
             (.preparingContext, .startingAgent), (.preparingContext, .failed), (.preparingContext, .cancelling),
             (.startingAgent, .running), (.startingAgent, .failed), (.startingAgent, .cancelling),
             (.running, .waitingForPermission), (.running, .cancelling), (.running, .succeeded), (.running, .completed), (.running, .failed), (.running, .interrupted),
             (.waitingForPermission, .running), (.waitingForPermission, .cancelling), (.waitingForPermission, .failed), (.waitingForPermission, .interrupted),
             (.cancelling, .cancelled), (.cancelling, .failed),
             (.interrupted, .preparingContext), (.interrupted, .cancelling), (.interrupted, .failed):
            true
        default:
            false
        }
    }
}

public struct Run: Codable, Sendable, Hashable, Identifiable {
    public let id: RunID
    public let spaceID: SpaceID
    public let sessionID: SessionID
    public var executionContextID: ExecutionContextID?
    public var lifecycle: RunLifecycle

    public init(id: RunID = RunID(), spaceID: SpaceID, sessionID: SessionID, executionContextID: ExecutionContextID? = nil, lifecycle: RunLifecycle = .queued) {
        self.id = id
        self.spaceID = spaceID
        self.sessionID = sessionID
        self.executionContextID = executionContextID
        self.lifecycle = lifecycle
    }
}

/// A transient, ordered update from the Host-owned runtime. Durable history stays in Storage;
/// clients may reconnect and reload it independently of this event stream.
public enum RunEventKind: Codable, Sendable, Hashable {
    case lifecycle(RunLifecycle)
    case assistantTextDelta(String)
}

public struct RunEvent: Sendable, Hashable, Identifiable {
    public let id: UUID
    public let sequence: UInt64
    public let spaceID: SpaceID
    public let sessionID: SessionID
    public let runID: RunID
    public let kind: RunEventKind

    public init(
        id: UUID = UUID(),
        sequence: UInt64,
        spaceID: SpaceID,
        sessionID: SessionID,
        runID: RunID,
        kind: RunEventKind
    ) {
        self.id = id
        self.sequence = sequence
        self.spaceID = spaceID
        self.sessionID = sessionID
        self.runID = runID
        self.kind = kind
    }
}

// MARK: - Durable event journal

public enum EventDurability: String, Codable, Sendable, Hashable {
    case durable
    case recoverable
    case ephemeral
}

/// A transport-independent event retained by the Host for replay and snapshot consistency.
public struct JournalEvent: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public let cursor: UInt64
    public let spaceID: SpaceID?
    public let aggregateID: String
    public let aggregateType: String
    public let aggregateRevision: UInt64
    public let occurredAt: Date
    public let payloadIdentifier: String
    public let payloadSchemaVersion: UInt32
    public let payloadBytes: Data
    public let durability: EventDurability

    public init(
        id: UUID = UUID(),
        cursor: UInt64,
        spaceID: SpaceID? = nil,
        aggregateID: String,
        aggregateType: String,
        aggregateRevision: UInt64,
        occurredAt: Date = Date(),
        payloadIdentifier: String,
        payloadSchemaVersion: UInt32,
        payloadBytes: Data,
        durability: EventDurability
    ) {
        precondition(cursor > 0, "Journal cursors start at one")
        precondition(!aggregateID.isEmpty, "Journal events require an aggregate identity")
        precondition(!aggregateType.isEmpty, "Journal events require an aggregate type")
        precondition(!payloadIdentifier.isEmpty, "Journal events require a payload identifier")
        precondition(payloadSchemaVersion > 0, "Journal payload schemas start at one")
        self.id = id
        self.cursor = cursor
        self.spaceID = spaceID
        self.aggregateID = aggregateID
        self.aggregateType = aggregateType
        self.aggregateRevision = aggregateRevision
        self.occurredAt = occurredAt
        self.payloadIdentifier = payloadIdentifier
        self.payloadSchemaVersion = payloadSchemaVersion
        self.payloadBytes = payloadBytes
        self.durability = durability
    }
}

public enum OperationLifecycle: String, Codable, Sendable, Hashable {
    case queued
    case running
    case completed
    case failed
    case cancelled

    public func canTransition(to next: Self) -> Bool {
        switch (self, next) {
        case (.queued, .running), (.queued, .cancelled),
             (.running, .completed), (.running, .failed), (.running, .cancelled):
            true
        default:
            false
        }
    }
}

public struct Operation: Codable, Sendable, Hashable, Identifiable {
    public let id: OperationID
    public let spaceID: SpaceID
    public let sessionID: SessionID?
    public var lifecycle: OperationLifecycle
    public var progress: Double?
    public var failureDescription: String?

    public init(
        id: OperationID = OperationID(),
        spaceID: SpaceID,
        sessionID: SessionID? = nil,
        lifecycle: OperationLifecycle = .queued,
        progress: Double? = nil,
        failureDescription: String? = nil
    ) {
        if let progress { precondition((0...1).contains(progress), "Operation progress must be between zero and one") }
        precondition(lifecycle != .failed || failureDescription != nil, "Failed operations need a failure description")
        self.id = id
        self.spaceID = spaceID
        self.sessionID = sessionID
        self.lifecycle = lifecycle
        self.progress = progress
        self.failureDescription = failureDescription
    }
}

public enum CommandLifecycle: String, Codable, Sendable, Hashable {
    case accepted
    case executing
    case succeeded
    case failed
    case cancelled

    public func canTransition(to next: Self) -> Bool {
        switch (self, next) {
        case (.accepted, .executing), (.accepted, .cancelled),
             (.executing, .succeeded), (.executing, .failed), (.executing, .cancelled): true
        default: false
        }
    }
}

/// A transport-neutral copy of a typed Host result, retained for idempotent command replay.
public struct DurableCommandResult: Codable, Sendable, Hashable {
    public let payloadIdentifier: String
    public let schemaVersion: UInt32
    public let protobufBytes: Data

    public init(payloadIdentifier: String, schemaVersion: UInt32, protobufBytes: Data) {
        precondition(!payloadIdentifier.isEmpty, "Durable command results require a payload identifier")
        precondition(schemaVersion > 0, "Payload schema versions start at one")
        self.payloadIdentifier = payloadIdentifier
        self.schemaVersion = schemaVersion
        self.protobufBytes = protobufBytes
    }
}

/// Host-owned command receipt used to make mutating Client requests retry-safe across connections.
public struct DurableCommand: Codable, Sendable, Hashable, Identifiable {
    public let id: CommandID
    /// Nil scopes commands that create or administer Host-wide state before a Space exists.
    public let spaceID: SpaceID?
    public let deviceID: DeviceID?
    public let payloadDigest: String
    public var lifecycle: CommandLifecycle
    public var result: DurableCommandResult?
    public var operationID: OperationID?
    public var runID: RunID?
    public let acceptedAt: Date
    public var startedAt: Date?
    public var completedAt: Date?

    public init(
        id: CommandID = CommandID(),
        spaceID: SpaceID? = nil,
        deviceID: DeviceID? = nil,
        payloadDigest: String,
        lifecycle: CommandLifecycle = .accepted,
        result: DurableCommandResult? = nil,
        operationID: OperationID? = nil,
        runID: RunID? = nil,
        acceptedAt: Date = Date(),
        startedAt: Date? = nil,
        completedAt: Date? = nil
    ) {
        precondition(!payloadDigest.isEmpty, "Durable commands require a canonical payload digest")
        self.id = id
        self.spaceID = spaceID
        self.deviceID = deviceID
        self.payloadDigest = payloadDigest
        self.lifecycle = lifecycle
        self.result = result
        self.operationID = operationID
        self.runID = runID
        self.acceptedAt = acceptedAt
        self.startedAt = startedAt
        self.completedAt = completedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, spaceID, deviceID, payloadDigest, lifecycle, result, operationID, runID, acceptedAt, startedAt, completedAt
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try values.decode(CommandID.self, forKey: .id),
            spaceID: try values.decodeIfPresent(SpaceID.self, forKey: .spaceID),
            deviceID: try values.decodeIfPresent(DeviceID.self, forKey: .deviceID),
            payloadDigest: try values.decode(String.self, forKey: .payloadDigest),
            lifecycle: try values.decode(CommandLifecycle.self, forKey: .lifecycle),
            result: try values.decodeIfPresent(DurableCommandResult.self, forKey: .result),
            operationID: try values.decodeIfPresent(OperationID.self, forKey: .operationID),
            runID: try values.decodeIfPresent(RunID.self, forKey: .runID),
            acceptedAt: try values.decodeIfPresent(Date.self, forKey: .acceptedAt) ?? .distantPast,
            startedAt: try values.decodeIfPresent(Date.self, forKey: .startedAt),
            completedAt: try values.decodeIfPresent(Date.self, forKey: .completedAt)
        )
    }
}

public struct Artifact: Codable, Sendable, Hashable, Identifiable {
    public let id: ArtifactID
    public let spaceID: SpaceID
    public let sessionID: SessionID?
    public let runID: RunID?
    public let resourceID: ResourceID?
    public let producerReference: HostPrivateReference
    public var title: String

    public init(
        id: ArtifactID = ArtifactID(),
        spaceID: SpaceID,
        sessionID: SessionID? = nil,
        runID: RunID? = nil,
        resourceID: ResourceID? = nil,
        producerReference: HostPrivateReference,
        title: String
    ) {
        precondition(!title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "An Artifact needs a title")
        self.id = id
        self.spaceID = spaceID
        self.sessionID = sessionID
        self.runID = runID
        self.resourceID = resourceID
        self.producerReference = producerReference
        self.title = title
    }
}

// MARK: - 1.x concept mapping

public enum Aizen1Concept: String, CaseIterable, Codable, Sendable, Hashable {
    case workspace
    case repository
    case worktreeOrFolder
    case chatSession
    case chatAgentSession
    case terminalSession
}

public enum ReignitionConcept: String, Codable, Sendable, Hashable {
    case space
    case resource
    case executionContext
    case session
    case hostRuntimeForRun
    case sessionSurfaceOrContextRuntimeDescriptor
}

public enum Aizen1MigrationMapping {
    public static func target(for source: Aizen1Concept) -> ReignitionConcept {
        switch source {
        case .workspace: .space
        case .repository: .resource
        case .worktreeOrFolder: .executionContext
        case .chatSession: .session
        case .chatAgentSession: .hostRuntimeForRun
        case .terminalSession: .sessionSurfaceOrContextRuntimeDescriptor
        }
    }
}
