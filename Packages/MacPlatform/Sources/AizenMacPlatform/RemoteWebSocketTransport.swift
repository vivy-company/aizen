import AizenCore
import AizenSecurity
import AizenTransport
import Foundation
@preconcurrency import Network

public enum RemoteWebSocketTransportError: Swift.Error, Sendable, Equatable, LocalizedError {
    case invalidEndpoint
    case connectionFailed(String)
    case invalidFrame

    public var errorDescription: String? {
        switch self {
        case .invalidEndpoint: "Aizen remote routes must use a secure WebSocket endpoint."
        case let .connectionFailed(message): "The secure WebSocket route failed: \(message)"
        case .invalidFrame: "The remote route returned an invalid WebSocket frame."
        }
    }
}

/// Platform bridge from a user-managed WSS route to the common authenticated Wire transport.
/// Tailscale, Cloudflare, and custom proxies all use this exact bridge; they differ only by URL.
public struct RemoteWebSocketRouteConnector: Sendable {
    private let host: HostPublicIdentity
    private let device: DevicePublicIdentity
    private let deviceIdentity: LocalCryptographicIdentity

    public init(host: HostPublicIdentity, device: DevicePublicIdentity, deviceIdentity: LocalCryptographicIdentity) {
        precondition(device.cryptographicIdentity == deviceIdentity.publicIdentity(createdAt: device.cryptographicIdentity.createdAt), "Device public and private identities must match")
        self.host = host
        self.device = device
        self.deviceIdentity = deviceIdentity
    }

    public func connect(route: TransportRouteConfiguration) async throws -> TransportRouteConnection {
        guard route.endpoint.scheme?.lowercased() == "wss",
              let hostname = route.endpoint.host else {
            throw RemoteWebSocketTransportError.invalidEndpoint
        }
        let port = route.endpoint.port ?? 443
        let bridge = try RemoteWebSocketFrameExchange(
            host: hostname,
            port: port,
            tls: PairedTLSOptions.client()
        )
        try await bridge.start()
        let routeKind = connectionRoute(for: route.kind)
        let authenticator = RemoteClientAuthenticator(host: host, device: device, deviceIdentity: deviceIdentity, route: routeKind)
        let transport = try await authenticator.authenticate(
            using: { frame in try await bridge.exchange(frame) },
            frameSender: { frame in try await bridge.send(frame) },
            frameStream: { bridge.frames() }
        )
        return .init(
            transport: transport,
            authenticatedHostIdentity: host.cryptographicIdentity.fingerprint.description,
            latency: bridge.handshakeLatency
        )
    }

    private func connectionRoute(for kind: TransportRouteKind) -> ConnectionRoute {
        switch kind {
        case .lan: .lan
        case .tailscale: .tailscale
        case .cloudflare: .cloudflare
        case .custom: .custom
        }
    }
}

/// One request/reply WebSocket channel. The authenticated transport serializes calls through
/// its actor, so this bridge intentionally has no request multiplexer or unbounded buffers.
private final class RemoteWebSocketFrameExchange: @unchecked Sendable {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "win.aizen.remote-websocket")
    private let startedAt = ContinuousClock.now
    private let stateLock = NSLock()
    private var startContinuation: CheckedContinuation<Void, Error>?
    private var isStarted = false

    var handshakeLatency: Duration? {
        guard isStarted else { return nil }
        return startedAt.duration(to: .now)
    }

    init(host: String, port: Int, tls: NWProtocolTLS.Options) throws {
        guard (1...65_535).contains(port) else { throw RemoteWebSocketTransportError.invalidEndpoint }
        let parameters = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
        let websocket = NWProtocolWebSocket.Options()
        parameters.defaultProtocolStack.applicationProtocols.insert(websocket, at: 0)
        connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: UInt16(port))!, using: parameters)
    }

    deinit {
        connection.cancel()
    }

    func start() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            stateLock.lock()
            guard !isStarted else {
                stateLock.unlock()
                continuation.resume()
                return
            }
            startContinuation = continuation
            connection.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    self.completeStart()
                case let .failed(error):
                    self.failStart(error)
                case .waiting:
                    break
                case .cancelled:
                    self.failStart(RemoteWebSocketTransportError.connectionFailed("Connection cancelled."))
                default:
                    break
                }
            }
            stateLock.unlock()
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 10) { [weak self] in
                self?.failStart(RemoteWebSocketTransportError.connectionFailed("Timed out while opening the secure WebSocket route."))
            }
        }
    }

    func exchange(_ frame: Data) async throws -> Data {
        guard isStarted else { throw RemoteWebSocketTransportError.connectionFailed("Connection has not started.") }
        try await send(frame)
        return try await receive()
    }

    func send(_ frame: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [connection] in
                connection.send(
                    content: frame,
                    contentContext: .init(identifier: "aizen.binary", metadata: [NWProtocolWebSocket.Metadata(opcode: .binary)]),
                    isComplete: true,
                    completion: .contentProcessed { error in
                        if let error {
                            continuation.resume(throwing: RemoteWebSocketTransportError.connectionFailed(error.debugDescription))
                        } else {
                            continuation.resume()
                        }
                    }
                )
            }
        }
    }

    private func receive() async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            queue.async { [connection] in
                connection.receiveMessage { content, context, _, error in
                    guard error == nil,
                          let content,
                          content.count <= AuthenticatedWireFrame.maximumCiphertextLength + 12,
                          (context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata)?.opcode == .binary else {
                        continuation.resume(throwing: error.map { RemoteWebSocketTransportError.connectionFailed($0.debugDescription) } ?? .invalidFrame)
                        return
                    }
                    continuation.resume(returning: content)
                }
            }
        }
    }

    func frames() -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            queue.async { [weak self] in self?.receiveNext(continuation) }
            continuation.onTermination = { [weak self] _ in self?.connection.cancel() }
        }
    }

    private func receiveNext(_ continuation: AsyncThrowingStream<Data, Error>.Continuation) {
        connection.receiveMessage { [weak self] content, context, _, error in
            guard let self else { return }
            guard error == nil,
                  let content,
                  content.count <= AuthenticatedWireFrame.maximumCiphertextLength + 12,
                  (context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata)?.opcode == .binary else {
                continuation.finish(throwing: error.map { RemoteWebSocketTransportError.connectionFailed($0.debugDescription) } ?? .invalidFrame)
                return
            }
            continuation.yield(content)
            self.receiveNext(continuation)
        }
    }

    private func completeStart() {
        stateLock.lock()
        guard let continuation = startContinuation else {
            stateLock.unlock()
            return
        }
        startContinuation = nil
        isStarted = true
        stateLock.unlock()
        continuation.resume()
    }

    private func failStart(_ error: Error) {
        stateLock.lock()
        let continuation = startContinuation
        startContinuation = nil
        stateLock.unlock()
        continuation?.resume(throwing: RemoteWebSocketTransportError.connectionFailed(error.localizedDescription))
    }
}
