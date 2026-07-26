import Foundation
import Testing
import AizenCore
@testable import AizenStorage

@Test func moduleLoads() { _ = AizenStorageModule.self }

@Test func repositoryPersistsProjectlessSessionsAtomically() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let repository = StorageRepository(url: directory.appendingPathComponent("storage-v2.json"))
    let space = Space(name: "Personal")
    let saved = try await repository.transact { snapshot in
        snapshot.spaces.append(space)
        snapshot.sessions.append(Session(spaceID: space.id, kind: .conversation, title: "No repository needed"))
    }
    #expect(saved.sessions.first?.resourceIDs.isEmpty == true)
    #expect(try await repository.load() == saved)
}

@Test func failedTransactionsLeaveTheLastValidSnapshotIntact() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let repository = StorageRepository(url: directory.appendingPathComponent("storage-v2.json"))
    let space = Space(name: "Personal")
    _ = try await repository.transact { $0.spaces.append(space) }

    await #expect(throws: StorageError.missingSpace) {
        try await repository.transact {
            $0.sessions.append(Session(spaceID: SpaceID(), kind: .conversation, title: "Invalid containment"))
        }
    }
    #expect(try await repository.load().sessions.isEmpty)
}
