import CryptoKit
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
    private var transfers: [UUID: Transfer] = [:]

    public init(directory: URL, maximumBytes: Int = 64 * 1_024 * 1_024, maximumReservedBytes: Int? = nil, fileManager: FileManager = .default) {
        precondition(maximumBytes > 0)
        precondition((maximumReservedBytes ?? maximumBytes) >= maximumBytes)
        self.directory = directory
        self.maximumBytes = maximumBytes
        self.maximumReservedBytes = maximumReservedBytes ?? maximumBytes
        self.fileManager = fileManager
    }

    public func begin(target: Target, byteCount: Int, sha256: Data, now: Date = .now) throws -> Descriptor {
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
        transfers[descriptor.id] = .init(descriptor: descriptor, url: url, received: 0, expiresAt: now.addingTimeInterval(3_600)); return descriptor
    }

    public func append(id: UUID, target: Target, offset: Int, bytes: Data, now: Date = .now) throws -> Int {
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
        transfer.received += bytes.count; transfer.expiresAt = now.addingTimeInterval(3_600); transfers[id] = transfer; return transfer.received
    }

    public func target(id: UUID, executionContextID: String) throws -> Target {
        guard let transfer = transfers[id] else { throw Error.unknown }
        guard transfer.descriptor.target.executionContextID == executionContextID else { throw Error.targetMismatch }
        return transfer.descriptor.target
    }

    public func finish(id: UUID, target: Target) throws -> CompletedUpload {
        guard let transfer = transfers[id] else { throw Error.unknown }
        guard transfer.descriptor.target == target else { throw Error.targetMismatch }
        guard transfer.received == transfer.descriptor.byteCount else { throw Error.offset(expected: transfer.received) }
        guard Data(SHA256.hash(data: try Data(contentsOf: transfer.url))) == transfer.descriptor.sha256 else { cancel(id: id); throw Error.integrity }
        transfers[id] = nil
        return .init(descriptor: transfer.descriptor, url: transfer.url)
    }

    public func discard(_ upload: CompletedUpload) { try? fileManager.removeItem(at: upload.url) }
    public func cancel(id: UUID, target: Target? = nil) {
        guard let transfer = transfers[id], target == nil || transfer.descriptor.target == target else { return }
        transfers[id] = nil
        try? fileManager.removeItem(at: transfer.url)
    }
    public func cleanup(now: Date = .now) { for id in transfers.filter({ $0.value.expiresAt <= now }).map(\.key) { cancel(id: id) } }
}
