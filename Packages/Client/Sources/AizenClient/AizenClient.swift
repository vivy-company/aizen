import AizenCore
import AizenTransport
import AizenWire

/// Client synchronisation and projections shared by Mac, Mobile, and CLI.
public enum AizenClientModule {
    public static let protocolGeneration = AizenWireModule.protocolGeneration
}

public enum ClientConnectionState: Sendable, Hashable {
    case disconnected
    case connected(protocolGeneration: UInt32)
}

public struct SpaceProjection: Sendable, Hashable {
    public let activeSpaceID: SpaceID?
    public let spaces: [Space]

    public init(activeSpaceID: SpaceID? = nil, spaces: [Space] = []) {
        precondition(activeSpaceID == nil || spaces.contains(where: { $0.id == activeSpaceID }), "Active Space must belong to this projection")
        self.activeSpaceID = activeSpaceID
        self.spaces = spaces
    }

    public func selecting(_ spaceID: SpaceID) -> Self {
        precondition(spaces.contains(where: { $0.id == spaceID }), "Cannot select a Space outside the current projection")
        return Self(activeSpaceID: spaceID, spaces: spaces)
    }
}

public actor HostClient {
    private let transport: any WireTransport
    public private(set) var connectionState: ClientConnectionState = .disconnected

    public init(transport: any WireTransport) {
        self.transport = transport
    }

    public func send(_ envelope: ProtocolEnvelope) async throws -> ProtocolEnvelope {
        let response = try await transport.send(envelope)
        connectionState = .connected(protocolGeneration: response.protocolGeneration)
        return response
    }

    public func disconnect() {
        connectionState = .disconnected
    }
}
