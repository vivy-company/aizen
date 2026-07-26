import AizenCore
import AizenHost
import AizenSecurity
import AizenStorage
import AizenTransport
import AizenWire
import Dispatch
import Foundation
import Network

public enum HostLANListenerError: Swift.Error, Sendable, Equatable {
    case malformedHandshake
    case invalidPairingRequest
}

/// Main-actor lifecycle owner for the Host's TLS 1.3 binary WebSocket listener.
@MainActor
public final class HostLANWebSocketListener {
    private let host: HostPublicIdentity
    private let hostIdentity: LocalCryptographicIdentity
    private let storage: StorageRepository
    private let endpoint: any WireEndpoint
    private let authenticator: RemoteSessionAuthenticator
    private let authorization: DeviceAuthorizationGate
    private let ownerConfirmation: OwnerConfirmationGate
    private let rateLimiter: RemoteRequestRateLimiter
    private let pairing: PairingRequestRegistry
    private let terminalControl: TerminalControlLeaseRegistry
    private let queue = DispatchQueue(label: "win.aizen.host.lan")
    private var listener: NWListener?
    private var advertisement: HostBonjourAdvertisement?
    private var connections: [UUID: HostLANWebSocketConnection] = [:]
    public private(set) var port: UInt16?

    public init(host: HostPublicIdentity, hostIdentity: LocalCryptographicIdentity, storage: StorageRepository, endpoint: any WireEndpoint, pairing: PairingRequestRegistry, terminalControl: TerminalControlLeaseRegistry, ownerConfirmationAuthority: any OwnerConfirmationAuthority = MacOwnerConfirmationAuthority()) {
        self.host = host
        self.hostIdentity = hostIdentity
        self.storage = storage
        self.endpoint = endpoint
        let rateLimiter = RemoteRequestRateLimiter()
        self.rateLimiter = rateLimiter
        authenticator = RemoteSessionAuthenticator(host: host, hostIdentity: hostIdentity, storage: storage, rateLimiter: rateLimiter)
        authorization = DeviceAuthorizationGate(storage: storage)
        ownerConfirmation = OwnerConfirmationGate(storage: storage, authority: ownerConfirmationAuthority)
        self.pairing = pairing
        self.terminalControl = terminalControl
    }

    public func start() async throws {
        stop()
        let tls = try PairedTLSOptions.server()
        let parameters = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
        let webSocket = NWProtocolWebSocket.Options()
        webSocket.setClientRequestHandler(queue) { _, _ in
            .init(status: .accept, subprotocol: nil)
        }
        parameters.defaultProtocolStack.applicationProtocols.insert(webSocket, at: 0)
        let listener = try NWListener(using: parameters, on: .any)
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor [weak self] in
                self?.accept(connection)
            }
        }
        listener.stateUpdateHandler = { [weak self] state in
            guard case .ready = state, let port = listener.port else { return }
            Task { @MainActor [weak self] in
                guard let self, self.advertisement == nil else { return }
                self.port = port.rawValue
                self.advertisement = HostBonjourAdvertisement(
                    host: self.host,
                    metadata: HostBonjourMetadata(host: self.host, minimumProtocolGeneration: 1, maximumProtocolGeneration: 1)
                )
                self.advertisement?.start(port: Int32(port.rawValue))
            }
        }
        self.listener = listener
        listener.start(queue: queue)
    }

    public func stop() {
        advertisement?.stop()
        advertisement = nil
        connections.values.forEach { $0.stop() }
        connections.removeAll()
        listener?.cancel()
        listener = nil
        port = nil
    }

    /// The local approval UI reads only safe device metadata from this surface.
    public func pendingPairingRequests() async -> [PendingPairingRequest] {
        await pairing.pending()
    }

    public func approvePairingRequest(tokenID: UUID, grants: Set<CapabilityGrant>) async throws -> DeviceAuthorization {
        try await pairing.approve(tokenID: tokenID, grants: grants)
    }

    public func rejectPairingRequest(tokenID: UUID) async throws {
        _ = try await pairing.reject(tokenID: tokenID)
    }

    private func accept(_ connection: NWConnection) {
        let rawSource = connection.endpoint.debugDescription
        let source = RemoteRequestSource(rawSource.isEmpty ? "unknown" : String(rawSource.prefix(256)))
        let identifier = UUID()
        let socket = HostLANWebSocketConnection(
            connection: connection,
            queue: queue,
            processor: HostLANWebSocketProcessor(
                host: host,
                hostIdentity: hostIdentity,
                authenticator: authenticator,
                endpoint: endpoint,
                storage: storage,
                authorization: authorization,
                ownerConfirmation: ownerConfirmation,
                rateLimiter: rateLimiter,
                pairing: pairing,
                terminalControl: terminalControl,
                source: source
            ),
            onClose: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.connections.removeValue(forKey: identifier)
                }
            }
        )
        connections[identifier] = socket
        socket.start()
    }
}

actor HostLANWebSocketProcessor {
    private enum Phase {
        case awaitingStart
        case awaitingProof(AuthenticationMode)
        case authenticated(AuthenticatedWireChannel, RemoteHostEndpoint)
        case awaitingPairingRequest(AuthenticatedWireChannel, DeviceID, PublicCryptographicIdentity)
    }

    private enum AuthenticationMode {
        case paired
        case pairing
    }

    private let authenticator: RemoteSessionAuthenticator
    private let endpoint: any WireEndpoint
    private let storage: StorageRepository
    private let authorization: DeviceAuthorizationGate
    private let ownerConfirmation: OwnerConfirmationGate
    private let rateLimiter: RemoteRequestRateLimiter
    private let pairing: PairingRequestRegistry
    private let terminalControl: TerminalControlLeaseRegistry
    private let pairingAuthenticator: PairingSessionAuthenticator
    private let source: RemoteRequestSource
    private var phase = Phase.awaitingStart

    init(host: HostPublicIdentity, hostIdentity: LocalCryptographicIdentity, authenticator: RemoteSessionAuthenticator, endpoint: any WireEndpoint, storage: StorageRepository, authorization: DeviceAuthorizationGate, ownerConfirmation: OwnerConfirmationGate? = nil, rateLimiter: RemoteRequestRateLimiter, pairing: PairingRequestRegistry, terminalControl: TerminalControlLeaseRegistry, source: RemoteRequestSource) {
        self.authenticator = authenticator
        self.endpoint = endpoint
        self.storage = storage
        self.authorization = authorization
        self.ownerConfirmation = ownerConfirmation ?? OwnerConfirmationGate(storage: storage)
        self.rateLimiter = rateLimiter
        self.pairing = pairing
        self.terminalControl = terminalControl
        pairingAuthenticator = PairingSessionAuthenticator(host: host, hostIdentity: hostIdentity)
        self.source = source
    }

    func receive(_ data: Data) async throws -> Data {
        switch phase {
        case .awaitingStart:
            let envelope = try ProtocolEnvelope(serializedData: data)
            guard envelope.kind == .authentication, envelope.payload.identifier == AuthenticationStartPayload.identifier else { throw HostLANListenerError.malformedHandshake }
            let start = try AuthenticationStartPayload(protobufBytes: envelope.payload.protobufBytes)
            let challenge: AuthenticationChallengePayload
            if let authorization = try await storage.deviceAuthorization(for: start.deviceID), authorization.revokedAt == nil {
                challenge = try await authenticator.begin(start, source: source, protocolGeneration: envelope.protocolGeneration)
                phase = .awaitingProof(.paired)
            } else {
                try await rateLimiter.require(kind: .pairing, source: source, deviceID: start.deviceID)
                challenge = try await pairingAuthenticator.begin(start, protocolGeneration: envelope.protocolGeneration)
                phase = .awaitingProof(.pairing)
            }
            return try ProtocolEnvelope(messageID: UUID().uuidString, connectionID: envelope.connectionID, connectionSequence: envelope.connectionSequence, kind: .authentication, channel: .control, correlationID: envelope.messageID, payload: .init(challenge)).serializedData()
        case let .awaitingProof(mode):
            let envelope = try ProtocolEnvelope(serializedData: data)
            guard envelope.kind == .authentication, envelope.payload.identifier == AuthenticationProofPayload.identifier else { throw HostLANListenerError.malformedHandshake }
            switch mode {
            case .paired:
                let session = try await authenticator.finish(try AuthenticationProofPayload(protobufBytes: envelope.payload.protobufBytes))
                let channel = AuthenticatedWireChannel(keys: session.keys, binding: session.binding)
                let endpoint = RemoteHostEndpoint(endpoint: endpoint, storage: storage, authorization: authorization, ownerConfirmation: ownerConfirmation, rateLimiter: rateLimiter, terminalControl: terminalControl, session: session, source: source)
                phase = .authenticated(channel, endpoint)
                return try await channel.seal(ProtocolEnvelope(messageID: UUID().uuidString, connectionID: session.connectionID.uuidString, connectionSequence: 1, kind: .capabilities, channel: .control, correlationID: envelope.messageID, payload: .init(CapabilitiesPayload(identifiers: [HelloPayload.identifier, CapabilitiesPayload.identifier]))))
            case .pairing:
                let session = try await pairingAuthenticator.finish(try AuthenticationProofPayload(protobufBytes: envelope.payload.protobufBytes))
                let channel = AuthenticatedWireChannel(keys: session.keys, binding: session.binding)
                phase = .awaitingPairingRequest(channel, session.deviceID, session.deviceIdentity)
                return try await channel.seal(ProtocolEnvelope(messageID: UUID().uuidString, connectionID: envelope.connectionID, connectionSequence: 1, kind: .capabilities, channel: .control, correlationID: envelope.messageID, payload: .init(CapabilitiesPayload(identifiers: [PairingRequestPayload.identifier, PairingPendingPayload.identifier]))))
            }
        case let .authenticated(channel, endpoint):
            let request = try await channel.open(data)
            return try await channel.seal(try await endpoint.receive(request))
        case let .awaitingPairingRequest(channel, deviceID, deviceIdentity):
            let request = try await channel.open(data)
            guard request.kind == .command, request.channel == .control, request.payload.identifier == PairingRequestPayload.identifier else { throw HostLANListenerError.invalidPairingRequest }
            let pairingRequest = try PairingRequestPayload(protobufBytes: request.payload.protobufBytes)
            guard pairingRequest.deviceID == deviceID,
                  pairingRequest.deviceSigningPublicKey == deviceIdentity.signingPublicKey,
                  pairingRequest.deviceKeyAgreementPublicKey == deviceIdentity.keyAgreementPublicKey else {
                throw HostLANListenerError.invalidPairingRequest
            }
            try await rateLimiter.require(kind: .pairing, source: source, deviceID: deviceID)
            let pending = try await pairing.submit(pairingRequest)
            return try await channel.seal(ProtocolEnvelope(messageID: UUID().uuidString, connectionID: request.connectionID, connectionSequence: request.connectionSequence, kind: .commandReceipt, channel: .control, correlationID: request.messageID, payload: .init(PairingPendingPayload(tokenID: pending.tokenID))))
        }
    }
}

/// All Network access is confined to `queue`; the processor actor owns protocol state.
private final class HostLANWebSocketConnection: @unchecked Sendable {
    private let connection: NWConnection
    private let queue: DispatchQueue
    private let processor: HostLANWebSocketProcessor
    private let onClose: @Sendable () -> Void
    private var closed = false

    init(connection: NWConnection, queue: DispatchQueue, processor: HostLANWebSocketProcessor, onClose: @escaping @Sendable () -> Void) {
        self.connection = connection
        self.queue = queue
        self.processor = processor
        self.onClose = onClose
    }

    func start() {
        queue.async { [self] in
            connection.start(queue: queue)
            receiveNext()
        }
    }

    func stop() {
        queue.async { [self] in close() }
    }

    private func receiveNext() {
        connection.receiveMessage { [weak self] content, context, _, error in
            guard let self, error == nil, let content else {
                self?.close()
                return
            }
            guard content.count <= AuthenticatedWireFrame.maximumCiphertextLength + 12,
                  (context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata)?.opcode == .binary else {
                self.close()
                return
            }
            Task { [weak self] in
                do {
                    guard let self else { return }
                    let response = try await self.processor.receive(content)
                    self.queue.async { [weak self] in self?.send(response) }
                } catch {
                    self?.queue.async { [weak self] in self?.close() }
                }
            }
        }
    }

    private func send(_ response: Data) {
        connection.send(content: response, contentContext: .init(identifier: "aizen.binary", metadata: [NWProtocolWebSocket.Metadata(opcode: .binary)]), isComplete: true, completion: .contentProcessed { [weak self] error in
            if error == nil {
                self?.receiveNext()
            } else {
                self?.close()
            }
        })
    }

    private func close() {
        guard !closed else { return }
        closed = true
        connection.cancel()
        onClose()
    }
}
