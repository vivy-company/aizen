import AizenCore
import AizenStorage
import Foundation

public enum SandboxPersistence: String, Codable, Sendable, Hashable {
    case temporary
    case persistent
}

/// Creates Host-private working directories only when a Conversation needs filesystem access.
public actor ManagedSandboxService {
    public enum Error: Swift.Error, Sendable, Equatable {
        case unknownSession(SessionID)
        case sessionAlreadyHasExecutionContext(SessionID)
    }

    private struct Metadata: Codable {
        let spaceID: String
        let sessionID: String
        let persistence: SandboxPersistence
    }

    private let storage: StorageRepository
    private let rootURL: URL
    private let fileManager: FileManager

    public init(storage: StorageRepository, rootURL: URL, fileManager: FileManager = .default) {
        self.storage = storage
        self.rootURL = rootURL.standardizedFileURL
        self.fileManager = fileManager
    }

    public func provision(for sessionID: SessionID, persistence: SandboxPersistence) async throws -> ExecutionContext {
        let snapshot = try await storage.load()
        guard let session = snapshot.sessions.first(where: { $0.id == sessionID }) else {
            throw Error.unknownSession(sessionID)
        }
        guard session.executionContextID == nil else {
            throw Error.sessionAlreadyHasExecutionContext(sessionID)
        }

        let contextID = ExecutionContextID()
        let context = ExecutionContext(
            id: contextID,
            spaceID: session.spaceID,
            kind: persistence == .temporary ? .managedTemporarySandbox : .managedPersistentSandbox,
            hostReference: HostPrivateReference(rawValue: "sandbox-\(contextID.description)")
        )
        let directory = directoryURL(for: context)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        do {
            let metadata = Metadata(spaceID: session.spaceID.description, sessionID: session.id.description, persistence: persistence)
            try JSONEncoder().encode(metadata).write(to: directory.appendingPathComponent("metadata.json"), options: .atomic)
            _ = try await storage.transact { snapshot in
                guard let index = snapshot.sessions.firstIndex(where: { $0.id == sessionID }) else { throw Error.unknownSession(sessionID) }
                guard snapshot.sessions[index].executionContextID == nil else { throw Error.sessionAlreadyHasExecutionContext(sessionID) }
                snapshot.executionContexts.append(context)
                snapshot.sessions[index].executionContextID = context.id
            }
            return context
        } catch {
            try? fileManager.removeItem(at: directory)
            throw error
        }
    }

    public func directoryURL(for context: ExecutionContext) -> URL {
        rootURL
            .appendingPathComponent(context.spaceID.description, isDirectory: true)
            .appendingPathComponent(context.id.description, isDirectory: true)
    }
}
