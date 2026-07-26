import AizenCore
import AizenTransport
import AizenWire
import Foundation

/// Adds Host-runtime diagnostics to the shared snapshot envelope without exposing Host storage.
final class HostDiagnosticsEndpoint: @unchecked Sendable, RunEventEndpoint {
    static let scope = "diagnostics"

    private let endpoint: any RunEventEndpoint
    private let diagnostics: @Sendable () async -> HostDiagnosticsSnapshot

    init(endpoint: any RunEventEndpoint, diagnostics: @escaping @Sendable () async -> HostDiagnosticsSnapshot) {
        self.endpoint = endpoint
        self.diagnostics = diagnostics
    }

    func receive(_ envelope: ProtocolEnvelope) async throws -> ProtocolEnvelope {
        guard envelope.kind == .query,
              envelope.payload.identifier == SnapshotRequestPayload.identifier,
              try SnapshotRequestPayload(protobufBytes: envelope.payload.protobufBytes).scope == Self.scope else {
            return try await endpoint.receive(envelope)
        }

        let snapshot = await diagnostics()
        return try ProtocolEnvelope(
            messageID: UUID().uuidString,
            connectionSequence: envelope.connectionSequence,
            kind: .queryResponse,
            channel: .state,
            correlationID: envelope.messageID,
            payload: TypedPayload(SnapshotResponsePayload(
                scope: Self.scope,
                cursor: 0,
                snapshot: JSONEncoder().encode(snapshot)
            ))
        )
    }

    func runEvents() async -> AsyncStream<RunEvent> {
        await endpoint.runEvents()
    }
}
