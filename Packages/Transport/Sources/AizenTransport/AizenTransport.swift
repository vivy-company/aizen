import AizenCore
import AizenWire

/// Transport contracts and route adapters. Transports do not own domain authorisation.
public enum AizenTransportModule {}

public protocol WireEndpoint: Sendable {
    func receive(_ envelope: ProtocolEnvelope) async throws -> ProtocolEnvelope
}

public protocol WireTransport: Sendable {
    func send(_ envelope: ProtocolEnvelope) async throws -> ProtocolEnvelope
}

/// Optional transient run-event capability. Durable state remains available through normal queries
/// after a reconnect, so transports need not buffer these events forever.
public protocol RunEventEndpoint: WireEndpoint {
    func runEvents() async -> AsyncStream<RunEvent>
}

public protocol RunEventTransport: WireTransport {
    func runEvents() async throws -> AsyncStream<RunEvent>
}

public enum TransportError: Swift.Error, Sendable, Equatable {
    case eventStreamingUnavailable
}

/// Exercises exactly the same protobuf envelope codec as external transports without a socket.
public struct InProcessTransport: RunEventTransport {
    private let endpoint: any WireEndpoint

    public init(endpoint: any WireEndpoint) {
        self.endpoint = endpoint
    }

    public func send(_ envelope: ProtocolEnvelope) async throws -> ProtocolEnvelope {
        let request = try ProtocolEnvelope(serializedData: envelope.serializedData())
        let response = try await endpoint.receive(request)
        return try ProtocolEnvelope(serializedData: response.serializedData())
    }

    public func runEvents() async throws -> AsyncStream<RunEvent> {
        guard let eventEndpoint = endpoint as? any RunEventEndpoint else {
            throw TransportError.eventStreamingUnavailable
        }
        return await eventEndpoint.runEvents()
    }
}
