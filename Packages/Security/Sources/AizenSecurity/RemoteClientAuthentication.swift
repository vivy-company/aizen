import AizenCore
import AizenTransport
import AizenWire
import Foundation
import Security

public enum RemoteClientAuthenticationError: Swift.Error, Sendable, Equatable {
    case malformedHandshake
    case hostIdentityMismatch
}

public enum AuthenticatedRemoteWireTransportError: Swift.Error, Sendable, Equatable {
    case queueFull(WireChannel)
}

/// A raw binary request/reply exchange used only while establishing a secure Aizen channel.
public typealias RemoteFrameExchange = @Sendable (Data) async throws -> Data

/// The post-authentication send half of a full-duplex secure route.
public typealias RemoteFrameSender = @Sendable (Data) async throws -> Void

/// Establishes a Host-pinned, mutually authenticated channel for any user-managed route.
/// Network reachability, TLS hostnames, and third-party access layers are intentionally not trust.
public struct RemoteClientAuthenticator: Sendable {
    private let host: HostPublicIdentity
    private let device: DevicePublicIdentity
    private let deviceIdentity: LocalCryptographicIdentity
    private let route: ConnectionRoute
    private let protocolGeneration: UInt32

    public init(
        host: HostPublicIdentity,
        device: DevicePublicIdentity,
        deviceIdentity: LocalCryptographicIdentity,
        route: ConnectionRoute,
        protocolGeneration: UInt32 = UInt32(AizenWireModule.protocolGeneration)
    ) {
        precondition(device.cryptographicIdentity == deviceIdentity.publicIdentity(createdAt: device.cryptographicIdentity.createdAt), "Device public and private identities must match")
        self.host = host
        self.device = device
        self.deviceIdentity = deviceIdentity
        self.route = route
        self.protocolGeneration = protocolGeneration
    }

    public func authenticate(using exchange: @escaping RemoteFrameExchange) async throws -> AuthenticatedRemoteWireTransport {
        try await authenticate(using: exchange) { channel in
            AuthenticatedRemoteWireTransport(channel: channel, exchange: exchange)
        }
    }

    /// Completes authentication, then upgrades the same route to a full-duplex Wire transport.
    public func authenticate(
        using exchange: @escaping RemoteFrameExchange,
        frameSender: @escaping RemoteFrameSender,
        frames: AsyncThrowingStream<Data, Error>
    ) async throws -> AuthenticatedRemoteWireTransport {
        let transport = try await authenticate(using: exchange) { channel in
            AuthenticatedRemoteWireTransport(channel: channel, frameSender: frameSender)
        }
        await transport.startReceiving(frames)
        return transport
    }

    private func authenticate(
        using exchange: @escaping RemoteFrameExchange,
        makeTransport: (AuthenticatedWireChannel) -> AuthenticatedRemoteWireTransport
    ) async throws -> AuthenticatedRemoteWireTransport {
        let connectionID = UUID()
        let ephemeralKey = ConnectionEphemeralKey()
        let clientNonce = try randomNonce()
        let start = AuthenticationStartPayload(
            hostID: host.hostID,
            deviceID: device.deviceID,
            connectionID: connectionID,
            clientNonce: clientNonce,
            deviceSigningPublicKey: device.cryptographicIdentity.signingPublicKey,
            deviceKeyAgreementPublicKey: device.cryptographicIdentity.keyAgreementPublicKey,
            clientEphemeralPublicKey: ephemeralKey.publicKey,
            route: route.rawValue
        )
        let startEnvelope = try ProtocolEnvelope(
            messageID: UUID().uuidString,
            connectionID: connectionID.uuidString,
            connectionSequence: 1,
            kind: .authentication,
            channel: .control,
            payload: .init(start)
        )
        let challengeEnvelope = try ProtocolEnvelope(serializedData: try await exchange(startEnvelope.serializedData()))
        guard challengeEnvelope.kind == .authentication,
              challengeEnvelope.payload.identifier == AuthenticationChallengePayload.identifier else {
            throw RemoteClientAuthenticationError.malformedHandshake
        }
        let challenge = try AuthenticationChallengePayload(protobufBytes: challengeEnvelope.payload.protobufBytes)
        guard challenge.hostID == host.hostID,
              challenge.deviceID == device.deviceID,
              challenge.connectionID == connectionID,
              challenge.clientNonce == clientNonce,
              challenge.hostSigningPublicKey == host.cryptographicIdentity.signingPublicKey,
              challenge.hostKeyAgreementPublicKey == host.cryptographicIdentity.keyAgreementPublicKey,
              challenge.route == route.rawValue else {
            throw RemoteClientAuthenticationError.hostIdentityMismatch
        }
        let binding = try ConnectionAuthenticationBinding(
            protocolGeneration: challengeEnvelope.protocolGeneration,
            hostID: host.hostID,
            deviceID: device.deviceID,
            connectionID: connectionID,
            clientNonce: clientNonce,
            serverNonce: challenge.serverNonce,
            clientEphemeralPublicKey: ephemeralKey.publicKey,
            serverEphemeralPublicKey: challenge.serverEphemeralPublicKey,
            route: route
        )
        try ConnectionAuthenticator.verify(
            .init(participant: .host, signature: challenge.hostSignature),
            expectedParticipant: .host,
            identity: host.cryptographicIdentity,
            binding: binding
        )
        let keys = try ConnectionAuthenticator.deriveKeys(
            participant: .device,
            ephemeralKey: ephemeralKey,
            peerEphemeralPublicKey: challenge.serverEphemeralPublicKey,
            binding: binding
        )
        let channel = AuthenticatedWireChannel(keys: keys, binding: binding)
        let proof = ConnectionAuthenticator.makeProof(participant: .device, identity: deviceIdentity, binding: binding)
        let proofEnvelope = try ProtocolEnvelope(
            messageID: UUID().uuidString,
            connectionID: connectionID.uuidString,
            connectionSequence: 2,
            kind: .authentication,
            channel: .control,
            payload: .init(AuthenticationProofPayload(connectionID: connectionID, deviceSignature: proof.signature))
        )
        let readyEnvelope = try await channel.open(try await exchange(proofEnvelope.serializedData()))
        guard readyEnvelope.kind == .capabilities else {
            throw RemoteClientAuthenticationError.malformedHandshake
        }
        return makeTransport(channel)
    }

    private func randomNonce() throws -> Data {
        var nonce = Data(count: ConnectionAuthenticationBinding.nonceLength)
        let status = nonce.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, bytes.count, bytes.baseAddress!)
        }
        guard status == errSecSuccess else { throw RemoteClientAuthenticationError.malformedHandshake }
        return nonce
    }
}

/// Turns a Host-pinned authenticated channel into the common Wire transport contract.
public actor AuthenticatedRemoteWireTransport: WireTransport, RunEventTransport {
    private struct PendingRequest: Sendable {
        let envelope: ProtocolEnvelope
        let continuation: CheckedContinuation<ProtocolEnvelope, Error>
    }

    private let channel: AuthenticatedWireChannel
    private let exchange: RemoteFrameExchange?
    private let frameSender: RemoteFrameSender?
    private var pending: [WireChannel: [PendingRequest]] = [:]
    private var responseContinuations: [String: CheckedContinuation<ProtocolEnvelope, Error>] = [:]
    private var eventContinuations: [UUID: AsyncStream<HostEvent>.Continuation] = [:]
    private var receiveTask: Task<Void, Never>?
    private var isDraining = false

    public init(channel: AuthenticatedWireChannel, exchange: @escaping RemoteFrameExchange) {
        self.channel = channel
        self.exchange = exchange
        frameSender = nil
    }

    /// Creates a transport over a full-duplex route. Call `startReceiving(_:)` exactly once after
    /// the authentication handshake has completed.
    public init(channel: AuthenticatedWireChannel, frameSender: @escaping RemoteFrameSender) {
        self.channel = channel
        exchange = nil
        self.frameSender = frameSender
    }

    deinit {
        receiveTask?.cancel()
    }

    public func send(_ envelope: ProtocolEnvelope) async throws -> ProtocolEnvelope {
        try await withCheckedThrowingContinuation { continuation in
            let requests = pending[envelope.channel, default: []]
            guard requests.count < Self.maximumPendingRequests(for: envelope.channel) else {
                continuation.resume(throwing: AuthenticatedRemoteWireTransportError.queueFull(envelope.channel))
                return
            }
            pending[envelope.channel] = requests + [.init(envelope: envelope, continuation: continuation)]
            startDrainingIfNeeded()
        }
    }

    public func runEvents() async throws -> AsyncStream<HostEvent> {
        guard receiveTask != nil else { throw TransportError.eventStreamingUnavailable }
        let subscriberID = UUID()
        let stream = AsyncStream.makeStream(of: HostEvent.self, bufferingPolicy: .bufferingNewest(100))
        eventContinuations[subscriberID] = stream.continuation
        stream.continuation.onTermination = { [weak self] _ in
            Task { await self?.removeEventSubscriber(subscriberID) }
        }
        return stream.stream
    }

    /// Starts the one receive loop for a full-duplex route. Each frame is decrypted in transport
    /// order, then dispatched either to its request continuation or to Host-event subscribers.
    public func startReceiving(_ frames: AsyncThrowingStream<Data, Error>) {
        precondition(receiveTask == nil, "A remote transport has one receive loop")
        receiveTask = Task { [weak self] in
            do {
                for try await frame in frames {
                    guard !Task.isCancelled else { return }
                    await self?.receive(frame)
                }
                await self?.finishReceiving(nil)
            } catch {
                await self?.finishReceiving(error)
            }
        }
    }

    private func startDrainingIfNeeded() {
        guard !isDraining else { return }
        isDraining = true
        Task { await drain() }
    }

    private func drain() async {
        while let request = dequeueNext() {
            do {
                let frame = try await channel.seal(request.envelope)
                if let exchange {
                    let response = try await channel.open(try await exchange(frame))
                    request.continuation.resume(returning: response)
                } else if let frameSender {
                    responseContinuations[request.envelope.messageID] = request.continuation
                    do {
                        try await frameSender(frame)
                    } catch {
                        responseContinuations.removeValue(forKey: request.envelope.messageID)?.resume(throwing: error)
                    }
                } else {
                    request.continuation.resume(throwing: TransportError.eventStreamingUnavailable)
                }
            } catch {
                request.continuation.resume(throwing: error)
            }
        }
        isDraining = false
    }

    private func dequeueNext() -> PendingRequest? {
        for channel in Self.priorityOrder {
            guard var requests = pending[channel], !requests.isEmpty else { continue }
            let next = requests.removeFirst()
            pending[channel] = requests
            return next
        }
        return nil
    }

    private func receive(_ frame: Data) async {
        do {
            let envelope = try await channel.open(frame)
            switch envelope.payload.identifier {
            case RunEventPayload.identifier:
                let event = try RunEventPayload(protobufBytes: envelope.payload.protobufBytes).event
                eventContinuations.values.forEach { $0.yield(.run(event)) }
            case TerminalOutputEventPayload.identifier:
                let event = try TerminalOutputEventPayload(protobufBytes: envelope.payload.protobufBytes).event
                eventContinuations.values.forEach { $0.yield(.terminalOutput(event)) }
            default:
                let requestID = envelope.correlationID ?? envelope.messageID
                responseContinuations.removeValue(forKey: requestID)?.resume(returning: envelope)
            }
        } catch {
            finishReceiving(error)
        }
    }

    private func finishReceiving(_ error: Error?) {
        receiveTask?.cancel()
        receiveTask = nil
        for continuation in responseContinuations.values {
            if let error { continuation.resume(throwing: error) }
            else { continuation.resume(throwing: TransportError.eventStreamingUnavailable) }
        }
        responseContinuations.removeAll()
        for requests in pending.values {
            for request in requests {
                if let error { request.continuation.resume(throwing: error) }
                else { request.continuation.resume(throwing: TransportError.eventStreamingUnavailable) }
            }
        }
        pending.removeAll()
        eventContinuations.values.forEach { $0.finish() }
        eventContinuations.removeAll()
    }

    private func removeEventSubscriber(_ id: UUID) {
        eventContinuations.removeValue(forKey: id)
    }

    private static let priorityOrder: [WireChannel] = [.control, .terminal, .state, .runStream, .blob]

    private static func maximumPendingRequests(for channel: WireChannel) -> Int {
        switch channel {
        case .blob: 8
        case .runStream: 16
        case .terminal, .state: 32
        case .control: 64
        }
    }
}
