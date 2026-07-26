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
        case invalidManagedContext(ExecutionContextID)
    }

    private struct Metadata: Codable {
        let spaceID: String
        let sessionID: String
        let persistence: SandboxPersistence
        var lastUsedAt: Date

        init(spaceID: String, sessionID: String, persistence: SandboxPersistence, lastUsedAt: Date) {
            self.spaceID = spaceID
            self.sessionID = sessionID
            self.persistence = persistence
            self.lastUsedAt = lastUsedAt
        }

        private enum CodingKeys: String, CodingKey {
            case spaceID, sessionID, persistence, lastUsedAt
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            spaceID = try values.decode(String.self, forKey: .spaceID)
            sessionID = try values.decode(String.self, forKey: .sessionID)
            persistence = try values.decode(SandboxPersistence.self, forKey: .persistence)
            lastUsedAt = try values.decodeIfPresent(Date.self, forKey: .lastUsedAt) ?? .distantPast
        }
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
            try writeMetadata(
                Metadata(
                    spaceID: session.spaceID.description,
                    sessionID: session.id.description,
                    persistence: persistence,
                    lastUsedAt: .now
                ),
                to: directory
            )
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

    /// Records real Host use without putting a filesystem path or timestamp into the protocol model.
    public func touch(_ context: ExecutionContext) throws {
        guard persistence(for: context) != nil else { throw Error.invalidManagedContext(context.id) }
        let directory = directoryURL(for: context)
        var metadata = try readMetadata(from: directory)
        guard metadata.spaceID == context.spaceID.description else { throw Error.invalidManagedContext(context.id) }
        metadata.lastUsedAt = .now
        try writeMetadata(metadata, to: directory)
    }

    /// Reclaims temporary contexts that are no longer executing. The durable relationship is
    /// removed before the directory, so a failed filesystem deletion becomes a harmless orphan.
    public func cleanupTemporarySandboxes(
        lastUsedBefore cutoff: Date,
        activeContextIDs: Set<ExecutionContextID> = []
    ) async throws -> [ExecutionContextID] {
        let snapshot = try await storage.load()
        let runtimeContextIDs = Set(snapshot.runs.compactMap { run in
            run.lifecycle.isTerminal ? nil : run.executionContextID
        })
        let candidates = snapshot.executionContexts.filter { context in
            guard persistence(for: context) == .temporary,
                !activeContextIDs.contains(context.id),
                !runtimeContextIDs.contains(context.id) else {
                return false
            }
            guard let metadata = try? readMetadata(from: directoryURL(for: context)) else { return true }
            return metadata.lastUsedAt < cutoff
        }

        for context in candidates {
            _ = try await storage.transact { snapshot in
                snapshot.executionContexts.removeAll { $0.id == context.id }
                for index in snapshot.sessions.indices where snapshot.sessions[index].executionContextID == context.id {
                    snapshot.sessions[index].executionContextID = nil
                }
                for index in snapshot.runs.indices where snapshot.runs[index].executionContextID == context.id {
                    snapshot.runs[index].executionContextID = nil
                }
            }
            try? fileManager.removeItem(at: directoryURL(for: context))
        }
        return candidates.map(\.id)
    }

    /// Deletes only two-level UUID directories that have no durable managed context. It is safe to
    /// run at Host startup after a crash or an interrupted directory deletion.
    public func cleanupOrphanedDirectories() async throws -> [URL] {
        let snapshot = try await storage.load()
        let managedDirectories = Set(snapshot.executionContexts.compactMap { context -> URL? in
            persistence(for: context) == nil ? nil : directoryURL(for: context).standardizedFileURL
        })
        guard fileManager.fileExists(atPath: rootURL.path) else { return [] }
        var removed: [URL] = []
        for spaceDirectory in try fileManager.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: [.isDirectoryKey]) {
            guard UUID(uuidString: spaceDirectory.lastPathComponent) != nil else { continue }
            for contextDirectory in try fileManager.contentsOfDirectory(at: spaceDirectory, includingPropertiesForKeys: [.isDirectoryKey]) {
                let directory = contextDirectory.standardizedFileURL
                guard UUID(uuidString: directory.lastPathComponent) != nil,
                    directory.path.hasPrefix(rootURL.path + "/"),
                    !managedDirectories.contains(directory) else {
                    continue
                }
                try fileManager.removeItem(at: directory)
                removed.append(directory)
            }
        }
        return removed
    }

    private func persistence(for context: ExecutionContext) -> SandboxPersistence? {
        if context.kind == .managedTemporarySandbox { return .temporary }
        if context.kind == .managedPersistentSandbox { return .persistent }
        return nil
    }

    private func readMetadata(from directory: URL) throws -> Metadata {
        try JSONDecoder().decode(Metadata.self, from: Data(contentsOf: directory.appendingPathComponent("metadata.json")))
    }

    private func writeMetadata(_ metadata: Metadata, to directory: URL) throws {
        try JSONEncoder().encode(metadata).write(to: directory.appendingPathComponent("metadata.json"), options: .atomic)
    }
}

private extension RunLifecycle {
    var isTerminal: Bool {
        switch self {
        case .completed, .succeeded, .failed, .cancelled: true
        case .queued, .preparingContext, .startingAgent, .running, .waitingForPermission, .cancelling, .interrupted: false
        }
    }
}
