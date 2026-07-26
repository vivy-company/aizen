import AizenCore
import AizenStorage
import AizenTransport
import AizenWire
import Foundation

/// Host command/query composition. Mac-only runtime adapters stay outside this package.
public enum AizenHostModule {
    public static let protocolGeneration = AizenWireModule.protocolGeneration
}

/// Explicit local Host composition. It owns Storage but exposes only Wire envelopes and Core snapshots.
public actor LocalHost: WireEndpoint {
    private let storage: StorageRepository

    public init(storage: StorageRepository) {
        self.storage = storage
    }

    public func receive(_ envelope: ProtocolEnvelope) async throws -> ProtocolEnvelope {
        let snapshot = try await storage.load()
        let payload = try JSONEncoder().encode(snapshot)
        return ProtocolEnvelope(
            messageID: envelope.messageID,
            connectionID: envelope.connectionID,
            connectionSequence: envelope.connectionSequence,
            kind: envelope.kind == .hello ? .capabilities : .snapshot,
            channel: .state,
            correlationID: envelope.correlationID,
            payload: .init(identifier: .init(rawValue: "aizen.snapshot.host@1"), schemaVersion: 1, protobufBytes: payload, stateAffecting: true)
        )
    }
}
