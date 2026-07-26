import CryptoKit
import Foundation

/// Host-owned, resumable temporary upload storage. Wire routing is added separately so no client can bypass these invariants.
public actor BlobTransferStore {
    public struct Descriptor: Sendable, Hashable { public let id: UUID; public let byteCount: Int; public let sha256: Data }
    public enum Error: Swift.Error, Sendable, Equatable { case invalidDescriptor, unknown, offset(expected: Int), tooLarge, integrity }
    private struct Transfer { let descriptor: Descriptor; let url: URL; var received: Int; var expiresAt: Date }
    private let directory: URL; private let maximumBytes: Int; private var transfers: [UUID: Transfer] = [:]

    public init(directory: URL, maximumBytes: Int = 64 * 1_024 * 1_024) throws {
        guard maximumBytes > 0 else { throw Error.tooLarge }; self.directory = directory; self.maximumBytes = maximumBytes
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }

    public func begin(byteCount: Int, sha256: Data, now: Date = .now) throws -> Descriptor {
        guard (0...maximumBytes).contains(byteCount), sha256.count == 32 else { throw Error.invalidDescriptor }
        let descriptor = Descriptor(id: UUID(), byteCount: byteCount, sha256: sha256); let url = directory.appendingPathComponent(descriptor.id.uuidString)
        FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
        transfers[descriptor.id] = .init(descriptor: descriptor, url: url, received: 0, expiresAt: now.addingTimeInterval(3_600)); return descriptor
    }

    public func append(id: UUID, offset: Int, bytes: Data, now: Date = .now) throws -> Int {
        guard var transfer = transfers[id] else { throw Error.unknown }; guard offset == transfer.received else { throw Error.offset(expected: transfer.received) }
        guard bytes.count <= transfer.descriptor.byteCount - transfer.received else { throw Error.tooLarge }
        let handle = try FileHandle(forWritingTo: transfer.url); defer { try? handle.close() }; try handle.seekToEnd(); try handle.write(contentsOf: bytes)
        transfer.received += bytes.count; transfer.expiresAt = now.addingTimeInterval(3_600); transfers[id] = transfer; return transfer.received
    }

    public func finish(id: UUID) throws -> URL {
        guard let transfer = transfers[id] else { throw Error.unknown }; guard transfer.received == transfer.descriptor.byteCount else { throw Error.offset(expected: transfer.received) }
        guard Data(SHA256.hash(data: try Data(contentsOf: transfer.url))) == transfer.descriptor.sha256 else { try? FileManager.default.removeItem(at: transfer.url); transfers[id] = nil; throw Error.integrity }
        transfers[id] = nil; return transfer.url
    }

    public func cancel(id: UUID) { guard let transfer = transfers.removeValue(forKey: id) else { return }; try? FileManager.default.removeItem(at: transfer.url) }
    public func cleanup(now: Date = .now) { for id in transfers.filter({ $0.value.expiresAt <= now }).map(\.key) { cancel(id: id) } }
}
