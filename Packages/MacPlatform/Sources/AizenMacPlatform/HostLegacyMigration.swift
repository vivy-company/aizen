import AizenCore
import AizenHost
import AizenStorage
import AizenTransport
import AizenWire
import Foundation

/// A client may request a one-time 1.x import, but only the Host reads or writes v2 Storage.
public enum HostLegacyMigrationRequestStore {
    private static let filename = "host-legacy-migration-request.json"

    public static func schedule(
        sourceStoreURL: URL,
        legacyModelURL: URL,
        storageURL: URL,
        fileManager: FileManager = .default
    ) throws {
        guard fileManager.fileExists(atPath: sourceStoreURL.path) else { return }
        let request = Request(sourceStoreURL: sourceStoreURL, legacyModelURL: legacyModelURL)
        let url = requestURL(for: storageURL)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(request).write(to: url, options: .atomic)
    }

    static func requestURL(for storageURL: URL) -> URL {
        storageURL.deletingLastPathComponent().appendingPathComponent(filename)
    }

    private struct Request: Codable, Sendable {
        let sourceStoreURL: URL
        let legacyModelURL: URL
    }
}

actor HostLegacyMigrationCoordinator {
    private let storage: StorageRepository
    private let storageURL: URL
    private let fileManager: FileManager

    init(storage: StorageRepository, storageURL: URL, fileManager: FileManager = .default) {
        self.storage = storage
        self.storageURL = storageURL
        self.fileManager = fileManager
    }

    func executeIfRequested() async throws {
        let requestURL = HostLegacyMigrationRequestStore.requestURL(for: storageURL)
        guard fileManager.fileExists(atPath: requestURL.path) else { return }
        let request = try JSONDecoder().decode(Request.self, from: Data(contentsOf: requestURL))

        guard fileManager.fileExists(atPath: request.sourceStoreURL.path) else {
            try fileManager.removeItem(at: requestURL)
            return
        }
        guard try await storage.load().isEmpty else {
            try fileManager.removeItem(at: requestURL)
            return
        }

        _ = try await LegacyCoreDataMigration.migrate(
            sourceStoreURL: request.sourceStoreURL,
            legacyModelURL: request.legacyModelURL,
            destination: storage,
            backupDirectory: request.sourceStoreURL.deletingLastPathComponent().appendingPathComponent("Reignition Backups", isDirectory: true)
        )
        try fileManager.removeItem(at: requestURL)
    }

    private struct Request: Codable, Sendable {
        let sourceStoreURL: URL
        let legacyModelURL: URL
    }
}

final class HostMigrationGate: @unchecked Sendable, RunEventEndpoint {
    private let host: LocalHost
    private let migration: HostLegacyMigrationCoordinator

    init(host: LocalHost, migration: HostLegacyMigrationCoordinator) {
        self.host = host
        self.migration = migration
    }

    func receive(_ envelope: ProtocolEnvelope) async throws -> ProtocolEnvelope {
        try await migration.executeIfRequested()
        return try await host.receive(envelope)
    }

    func runEvents() async -> AsyncStream<HostEvent> {
        await host.runEvents()
    }
}
