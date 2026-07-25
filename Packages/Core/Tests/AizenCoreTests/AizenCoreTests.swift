import Foundation
import Testing
@testable import AizenCore

@Test func productGenerationsStayIndependent() {
    #expect(AizenCoreModule.productVersion == "2.0.0")
    #expect(AizenCoreModule.protocolGeneration == 1)
    #expect(AizenCoreModule.storageSchemaVersion == 2)
}

@Test func projectlessConversationHasNoResourceOrExecutionContext() throws {
    let spaceID = SpaceID(rawValue: try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001")))
    let session = Session(spaceID: spaceID, kind: .conversation, title: "Plan Reignition")

    #expect(session.resourceIDs.isEmpty)
    #expect(session.executionContextID == nil)
    #expect(try JSONDecoder().decode(Session.self, from: JSONEncoder().encode(session)) == session)
}

@Test func codingSessionRetainsResourceAndWorktreeIdentity() throws {
    let spaceID = SpaceID()
    let repositoryID = ResourceID()
    let worktreeID = ExecutionContextID()
    let session = Session(
        spaceID: spaceID,
        kind: .coding,
        title: "Aizen 2.0",
        resourceIDs: [repositoryID],
        executionContextID: worktreeID
    )

    #expect(session.resourceIDs == [repositoryID])
    #expect(session.executionContextID == worktreeID)
}

@Test func extensibleKindsAndMappingsPreserveFutureCompatibility() {
    #expect(SessionKind(rawValue: "automation") != .conversation)
    #expect(ResourceKind(rawValue: "knowledge-graph").rawValue == "knowledge-graph")
    #expect(Aizen1MigrationMapping.target(for: .workspace) == .space)
    #expect(Aizen1MigrationMapping.target(for: .worktreeOrFolder) == .executionContext)
}

@Test func operationRejectsInvalidDurableState() {
    #expect(OperationLifecycle.queued.canTransition(to: .running))
    #expect(!OperationLifecycle.completed.canTransition(to: .running))
    #expect(!OperationLifecycle.running.canTransition(to: .queued))
}
