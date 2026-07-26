import Foundation
import AizenCore
import AizenTransport
import Testing
@testable import AizenClient
import AizenWire

@Test func clientUsesTheWireProtocol() {
    #expect(AizenClientModule.protocolGeneration == 1)
}

@Test func clientNegotiatesThroughTheProtobufInProcessTransport() async throws {
    let client = HostClient(transport: InProcessTransport(endpoint: EchoHost()))
    let response = try await client.send(.init(
        messageID: "hello",
        connectionSequence: 1,
        kind: .hello,
        channel: .control,
        payload: .init(identifier: .init(rawValue: "aizen.control.hello@1"), schemaVersion: 1, protobufBytes: Data(), stateAffecting: false)
    ))
    #expect(response.messageID == "hello")
    #expect(await client.connectionState == .connected(protocolGeneration: 1))
}

@Test func selectingSpaceIsAnExplicitProjectionTransition() {
    let first = Space(name: "Personal")
    let second = Space(name: "Work")
    let projection = SpaceProjection(spaces: [first, second]).selecting(second.id)
    #expect(projection.activeSpaceID == second.id)
    #expect(projection.spaces.map(\.name) == ["Personal", "Work"])
}

private struct EchoHost: WireEndpoint {
    func receive(_ envelope: ProtocolEnvelope) async throws -> ProtocolEnvelope { envelope }
}
