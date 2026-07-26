import CryptoKit
import AizenStorage
import Foundation

/// Host-owned, resumable temporary upload storage. Each transfer is bound to its intended
/// execution-context file, so a blob identifier alone cannot be repurposed for another target.
public actor BlobTransferStore {
    public struct Target: Sendable, Hashable {
        public let executionContextID: String
        public let relativePath: String
        public let expectedContentHash: String

        public init(executionContextID: String, relativePath: String, expectedContentHash: String) {
            self.executionContextID = executionContextID
            self.relativePath = relativePath
            self.expectedContentHash = expectedContentHash
        }
    }

    public struct Descriptor: Sendable, Hashable {
        public let id: UUID
        public let byteCount: Int
        public let sha256: Data
        public let target: Target
    }

    public struct CompletedUpload: Sendable {
        public let descriptor: Descriptor
        let url: URL
    }

    public enum Error: Swift.Error, Sendable, Equatable {
        case invalidDescriptor
        case unknown
        case targetMismatch
        case offset(expected: Int)
        case tooLarge
        case totalQuotaExceeded
        case integrity
    }

    public static let defaultMaximumBytes = 64 * 1_024 * 1_024
    private struct Transfer { let descriptor: Descriptor; let url: URL; var received: Int; var expiresAt: Date }
    private let directory: URL
    private let maximumBytes: Int
    private let maximumReservedBytes: Int
    private let fileManager: FileManager
    private let storage: StorageRepository?
    private var transfers: [UUID: Transfer] = [:]
    private var restored = false

    public init(directory: URL, storage: StorageRepository? = nil, maximumBytes: Int = 64 * 1_024 * 1_024, maximumReservedBytes: Int? = nil, fileManager: FileManager = .default) {
        precondition(maximumBytes > 0)
        precondition((maximumReservedBytes ?? maximumBytes) >= maximumBytes)
        self.directory = directory
        self.maximumBytes = maximumBytes
        self.maximumReservedBytes = maximumReservedBytes ?? maximumBytes
        self.fileManager = fileManager
        self.storage = storage
    }

    public func begin(target: Target, byteCount: Int, sha256: Data, now: Date = .now) async throws -> Descriptor {
        try await restoreIfNeeded(now: now)
        guard byteCount > 0, byteCount <= maximumBytes, sha256.count == 32 else { throw Error.invalidDescriptor }
        guard target.executionContextID.isEmpty == false, target.relativePath.isEmpty == false, target.expectedContentHash.count == 64 else { throw Error.invalidDescriptor }
        let reserved = try transfers.values.reduce(into: 0) { partialResult, transfer in
            let (sum, overflow) = partialResult.addingReportingOverflow(transfer.descriptor.byteCount)
            guard !overflow else { throw Error.totalQuotaExceeded }
            partialResult = sum
        }
        guard byteCount <= maximumReservedBytes - reserved else { throw Error.totalQuotaExceeded }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let descriptor = Descriptor(id: UUID(), byteCount: byteCount, sha256: sha256, target: target)
        let url = directory.appendingPathComponent(descriptor.id.uuidString)
        guard fileManager.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw Error.unknown }
        let transfer = Transfer(descriptor: descriptor, url: url, received: 0, expiresAt: now.addingTimeInterval(3_600))
        do {
            try await persist(transfer)
            transfers[descriptor.id] = transfer
            return descriptor
        } catch {
            try? fileManager.removeItem(at: url)
            throw error
        }
    }

    public func append(id: UUID, target: Target, offset: Int, bytes: Data, now: Date = .now) async throws -> Int {
        try await restoreIfNeeded(now: now)
        guard var transfer = transfers[id] else { throw Error.unknown }
        guard transfer.descriptor.target == target else { throw Error.targetMismatch }
        guard offset >= 0 else { throw Error.offset(expected: transfer.received) }
        if offset < transfer.received {
            guard bytes.count <= transfer.received - offset else { throw Error.offset(expected: transfer.received) }
            let handle = try FileHandle(forReadingFrom: transfer.url)
            defer { try? handle.close() }
            try handle.seek(toOffset: UInt64(offset))
            guard try handle.read(upToCount: bytes.count) == bytes else { throw Error.offset(expected: transfer.received) }
            return transfer.received
        }
        guard offset == transfer.received else { throw Error.offset(expected: transfer.received) }
        guard bytes.count <= transfer.descriptor.byteCount - transfer.received else { throw Error.tooLarge }
        let handle = try FileHandle(forWritingTo: transfer.url); defer { try? handle.close() }; try handle.seekToEnd(); try handle.write(contentsOf: bytes)
        transfer.received += bytes.count
        transfer.expiresAt = now.addingTimeInterval(3_600)
        try await persist(transfer)
        transfers[id] = transfer
        return transfer.received
    }

    public func target(id: UUID, executionContextID: String) async throws -> Target {
        try await restoreIfNeeded()
        guard let transfer = transfers[id] else { throw Error.unknown }
        guard transfer.descriptor.target.executionContextID == executionContextID else { throw Error.targetMismatch }
        return transfer.descriptor.target
    }

    public func finish(id: UUID, target: Target) async throws -> CompletedUpload {
        try await restoreIfNeeded()
        guard let transfer = transfers[id] else { throw Error.unknown }
        guard transfer.descriptor.target == target else { throw Error.targetMismatch }
        guard transfer.received == transfer.descriptor.byteCount else { throw Error.offset(expected: transfer.received) }
        guard Data(SHA256.hash(data: try Data(contentsOf: transfer.url))) == transfer.descriptor.sha256 else { await cancel(id: id); throw Error.integrity }
        return .init(descriptor: transfer.descriptor, url: transfer.url)
    }

    public func complete(id: UUID, target: Target) async throws {
        try await restoreIfNeeded()
        guard let transfer = transfers[id] else { throw Error.unknown }
        guard transfer.descriptor.target == target else { throw Error.targetMismatch }
        transfers[id] = nil
        try await removePersisted(id)
    }

    public func discard(_ upload: CompletedUpload) { try? fileManager.removeItem(at: upload.url) }
    public func cancel(id: UUID, target: Target? = nil) async {
        try? await restoreIfNeeded()
        guard let transfer = transfers[id], target == nil || transfer.descriptor.target == target else { return }
        transfers[id] = nil
        try? fileManager.removeItem(at: transfer.url)
        try? await removePersisted(id)
    }

    public func cleanup(now: Date = .now) async {
        try? await restoreIfNeeded(now: now)
        for id in transfers.filter({ $0.value.expiresAt <= now }).map(\.key) { await cancel(id: id) }
    }

    private func restoreIfNeeded(now: Date = .now) async throws {
        guard !restored else { return }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard let storage else {
            restored = true
            return
        }
        let records = try await storage.load().blobTransfers
        var stale: Set<UUID> = []
        for record in records {
            let url = directory.appendingPathComponent(record.id.uuidString)
            let size = (try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]))
            guard record.expiresAt > now,
                  record.byteCount <= maximumBytes,
                  record.sha256.count == 32,
                  size?.isRegularFile == true,
                  let received = size?.fileSize,
                  (0...record.byteCount).contains(received) else {
                stale.insert(record.id)
                try? fileManager.removeItem(at: url)
                continue
            }
            let descriptor = Descriptor(id: record.id, byteCount: record.byteCount, sha256: record.sha256, target: .init(executionContextID: record.executionContextID, relativePath: record.relativePath, expectedContentHash: record.expectedContentHash))
            transfers[record.id] = .init(descriptor: descriptor, url: url, received: received, expiresAt: record.expiresAt)
        }
        if !stale.isEmpty {
            _ = try await storage.transact { snapshot in snapshot.blobTransfers.removeAll { stale.contains($0.id) } }
        }
        restored = true
    }

    private func persist(_ transfer: Transfer) async throws {
        guard let storage else { return }
        let record = BlobTransferRecord(id: transfer.descriptor.id, executionContextID: transfer.descriptor.target.executionContextID, relativePath: transfer.descriptor.target.relativePath, expectedContentHash: transfer.descriptor.target.expectedContentHash, byteCount: transfer.descriptor.byteCount, sha256: transfer.descriptor.sha256, expiresAt: transfer.expiresAt)
        _ = try await storage.transact { snapshot in
            snapshot.blobTransfers.removeAll { $0.id == record.id }
            snapshot.blobTransfers.append(record)
        }
    }

    private func removePersisted(_ id: UUID) async throws {
        guard let storage else { return }
        _ = try await storage.transact { snapshot in snapshot.blobTransfers.removeAll { $0.id == id } }
    }
}
