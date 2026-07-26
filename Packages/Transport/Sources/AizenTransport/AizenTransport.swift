import AizenWire

/// Transport contracts and route adapters. Transports do not own domain authorisation.
public enum AizenTransportModule {}

public protocol WireEndpoint: Sendable {
    func receive(_ envelope: ProtocolEnvelope) async throws -> ProtocolEnvelope
}

public protocol WireTransport: Sendable {
    func send(_ envelope: ProtocolEnvelope) async throws -> ProtocolEnvelope
}

/// Exercises exactly the same protobuf envelope codec as external transports without a socket.
public struct InProcessTransport: WireTransport {
    private let endpoint: any WireEndpoint

    public init(endpoint: any WireEndpoint) {
        self.endpoint = endpoint
    }

    public func send(_ envelope: ProtocolEnvelope) async throws -> ProtocolEnvelope {
        let request = try ProtocolEnvelope(serializedData: envelope.serializedData())
        let response = try await endpoint.receive(request)
        return try ProtocolEnvelope(serializedData: response.serializedData())
    }
}
