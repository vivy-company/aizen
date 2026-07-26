import AizenCore
import AizenHost
import AizenTransport
import AizenWire
import Dispatch
import Foundation
@preconcurrency import XPC

/// Errors surfaced by the authenticated production Mach XPC transport.
public enum MachWireTransportError: Swift.Error, Sendable, Equatable, LocalizedError {
    case invalidResponse
    case unavailable
    case blocked
    case timeout
    case invalidCodeSigningRequirement(Int32)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "Aizen Host returned an invalid response."
        case .unavailable:
            "Aizen Host is unavailable. Start or repair the Host service, then try again."
        case .blocked:
            "Aizen Host rejected this client. Check the app installation and code-signing identity."
        case .timeout:
            "Aizen Host did not respond before the command deadline. Retry the command or inspect its operation."
        case .invalidCodeSigningRequirement:
            "Aizen Host could not validate its trusted client signature requirement."
        }
    }
}

public enum HostMachServiceConfigurationError: Swift.Error, Sendable, Equatable {
    case invalidTeamIdentifier
}

/// Stable identity of the user-level Host Mach service and its accepted signed peers.
public struct HostMachServiceConfiguration: Sendable, Equatable {
    public let machServiceName: String
    public let teamIdentifier: String
    public let allowsDevelopmentClients: Bool

    public init(machServiceName: String, teamIdentifier: String, allowsDevelopmentClients: Bool = false) throws {
        guard !machServiceName.isEmpty,
              !teamIdentifier.isEmpty,
              teamIdentifier.unicodeScalars.allSatisfy({ $0.isASCII && ($0.properties.isAlphabetic || $0.properties.numericType != nil) }) else {
            throw HostMachServiceConfigurationError.invalidTeamIdentifier
        }
        self.machServiceName = machServiceName
        self.teamIdentifier = teamIdentifier
        self.allowsDevelopmentClients = allowsDevelopmentClients
    }

    public var peerCodeSigningRequirement: String {
        if allowsDevelopmentClients {
            // Debug products are ad-hoc signed, so development must opt in to the exact bundled
            // product identifiers rather than silently disabling peer authentication altogether.
            return "identifier \"Aizen\" or identifier \"aizen-cli\""
        }
        return "anchor apple generic and certificate leaf[subject.OU] = \"\(teamIdentifier)\""
    }
}

/// Client transport for the user-level Host Mach service.
public final class MachWireTransport: @unchecked Sendable, RunEventTransport {
    private let connection: xpc_connection_t
    private let events = MachRunEventHub()
    private let responseTimeout: TimeInterval

    public init(machServiceName: String, responseTimeout: TimeInterval = 30) {
        precondition(responseTimeout > 0, "Mach response timeout must be positive")
        self.responseTimeout = responseTimeout
        connection = xpc_connection_create_mach_service(machServiceName, nil, 0)
        xpc_connection_set_event_handler(connection) { [events] message in
            guard xpc_get_type(message) == XPC_TYPE_DICTIONARY else {
                if xpc_get_type(message) == XPC_TYPE_ERROR {
                    Task { await events.finish() }
                }
                return
            }
            var length = 0
            guard let bytes = xpc_dictionary_get_data(message, "event", &length) else { return }
            let data = Data(bytes: bytes, count: length)
            Task { await events.receive(data) }
        }
        xpc_connection_activate(connection)
    }

    deinit {
        xpc_connection_cancel(connection)
    }

    public func send(_ envelope: ProtocolEnvelope) async throws -> ProtocolEnvelope {
        let request = try envelope.serializedData()
        let message = xpc_dictionary_create_empty()
        request.withUnsafeBytes { bytes in
            xpc_dictionary_set_data(message, "request", bytes.baseAddress, bytes.count)
        }

        let response = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            let reply = MachResponseContinuation(continuation: continuation)
            DispatchQueue.global().asyncAfter(deadline: .now() + responseTimeout) {
                reply.resume(throwing: MachWireTransportError.timeout)
            }
            xpc_connection_send_message_with_reply(connection, message, nil) { response in
                guard xpc_get_type(response) == XPC_TYPE_DICTIONARY else {
                    if xpc_equal(response, XPC_ERROR_CONNECTION_INVALID) {
                        reply.resume(throwing: MachWireTransportError.blocked)
                    } else {
                        reply.resume(throwing: MachWireTransportError.unavailable)
                    }
                    return
                }
                var length = 0
                guard let bytes = xpc_dictionary_get_data(response, "response", &length) else {
                    reply.resume(throwing: MachWireTransportError.invalidResponse)
                    return
                }
                reply.resume(returning: Data(bytes: bytes, count: length))
            }
        }
        return try ProtocolEnvelope(serializedData: response)
    }

    public func runEvents() async throws -> AsyncStream<RunEvent> {
        await events.stream()
    }
}

/// Ensures a late XPC reply cannot resume a timed-out Swift continuation twice.
final class MachResponseContinuation: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data, Error>?

    init(continuation: CheckedContinuation<Data, Error>) {
        self.continuation = continuation
    }

    func resume(returning value: Data) {
        finish { $0.resume(returning: value) }
    }

    func resume(throwing error: Error) {
        finish { $0.resume(throwing: error) }
    }

    private func finish(_ action: (CheckedContinuation<Data, Error>) -> Void) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        if let continuation { action(continuation) }
    }
}

/// Server listener for the user-level Host Mach service. XPC verifies the peer's code signature
/// before it delivers any request to the Host endpoint.
public final class MachWireHostListener: @unchecked Sendable {
    private let listener: xpc_connection_t
    private let service: MachWireService

    public init(
        configuration: HostMachServiceConfiguration,
        endpoint: any WireEndpoint,
        connectionRegistry: HostConnectionRegistry = .init()
    ) throws {
        listener = xpc_connection_create_mach_service(
            configuration.machServiceName,
            nil,
            UInt64(XPC_CONNECTION_MACH_SERVICE_LISTENER)
        )
        let status = xpc_connection_set_peer_code_signing_requirement(listener, configuration.peerCodeSigningRequirement)
        guard status == 0 else {
            throw MachWireTransportError.invalidCodeSigningRequirement(status)
        }
        service = MachWireService(endpoint: endpoint, connectionRegistry: connectionRegistry)
        xpc_connection_set_event_handler(listener) { [service] event in
            guard xpc_get_type(event) == XPC_TYPE_CONNECTION else { return }
            service.accept(event)
        }
        xpc_connection_activate(listener)
    }

    deinit {
        xpc_connection_cancel(listener)
    }
}

/// Tracks only live local XPC peers for Host diagnostics. Peer identities remain enforced by XPC.
public final class HostConnectionRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var identifiers: Set<UUID> = []

    public init() {}

    @discardableResult
    func connect() -> UUID {
        let identifier = UUID()
        lock.lock()
        identifiers.insert(identifier)
        lock.unlock()
        return identifier
    }

    func disconnect(_ identifier: UUID) {
        lock.lock()
        identifiers.remove(identifier)
        lock.unlock()
    }

    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return identifiers.count
    }
}

private final class MachWireService: @unchecked Sendable {
    private let endpoint: any WireEndpoint
    private let connectionRegistry: HostConnectionRegistry

    init(endpoint: any WireEndpoint, connectionRegistry: HostConnectionRegistry) {
        self.endpoint = endpoint
        self.connectionRegistry = connectionRegistry
    }

    func accept(_ connection: xpc_object_t) {
        let connectionID = connectionRegistry.connect()
        let peer = MachConnection(connection) { [connectionRegistry] in
            connectionRegistry.disconnect(connectionID)
        }
        if let eventEndpoint = endpoint as? any RunEventEndpoint {
            peer.startEventForwarding(Task { [peer] in
                let stream = await eventEndpoint.runEvents()
                for await event in stream {
                    guard !Task.isCancelled else { return }
                    guard let envelope = try? ProtocolEnvelope(
                        messageID: UUID().uuidString,
                        connectionSequence: event.sequence,
                        kind: .event,
                        channel: .runStream,
                        payload: TypedPayload(RunEventPayload(event: event))
                    ).serializedData() else { continue }
                    peer.sendEvent(envelope)
                }
            })
        }
        xpc_connection_set_event_handler(connection) { [endpoint, peer] message in
            guard xpc_get_type(message) != XPC_TYPE_ERROR else {
                peer.stop()
                return
            }
            guard xpc_get_type(message) == XPC_TYPE_DICTIONARY,
                  let reply = xpc_dictionary_create_reply(message) else {
                return
            }
            let replyMessage = MachMessage(reply)
            var length = 0
            guard let bytes = xpc_dictionary_get_data(message, "request", &length) else {
                peer.send(replyMessage)
                return
            }
            let request = Data(bytes: bytes, count: length)
            Task { [endpoint, peer, replyMessage] in
                let response: ProtocolEnvelope?
                do {
                    let envelope = try ProtocolEnvelope(serializedData: request)
                    response = try await endpoint.receive(envelope)
                } catch {
                    response = try? ProtocolEnvelope(
                        messageID: UUID().uuidString,
                        connectionSequence: 0,
                        kind: .error,
                        channel: .control,
                        payload: TypedPayload(hostErrorPayload(for: error))
                    )
                }
                guard let response, let data = try? response.serializedData() else { peer.send(replyMessage); return }
                data.withUnsafeBytes { bytes in
                    xpc_dictionary_set_data(replyMessage.value, "response", bytes.baseAddress, bytes.count)
                }
                peer.send(replyMessage)
            }
        }
        xpc_connection_activate(connection)
    }
}

func hostErrorPayload(for error: Error) -> HostErrorPayload {
    if let error = error as? HostProtocolError {
        return HostErrorPayload(code: error.errorCode, message: error.localizedDescription)
    }
    return HostErrorPayload(code: .commandFailed, message: error.localizedDescription)
}

private final class MachConnection: @unchecked Sendable {
    let value: xpc_connection_t
    private let eventTaskLock = NSLock()
    private var eventTask: Task<Void, Never>?
    private let terminationLock = NSLock()
    private var isTerminated = false
    private let onTermination: @Sendable () -> Void

    init(_ value: xpc_connection_t, onTermination: @escaping @Sendable () -> Void = {}) {
        self.value = value
        self.onTermination = onTermination
    }

    func send(_ message: MachMessage) {
        xpc_connection_send_message(value, message.value)
    }

    func sendEvent(_ data: Data) {
        let message = xpc_dictionary_create_empty()
        data.withUnsafeBytes { bytes in
            xpc_dictionary_set_data(message, "event", bytes.baseAddress, bytes.count)
        }
        xpc_connection_send_message(value, message)
    }

    func startEventForwarding(_ task: Task<Void, Never>) {
        eventTaskLock.lock()
        defer { eventTaskLock.unlock() }
        eventTask?.cancel()
        eventTask = task
    }

    func stopEventForwarding() {
        eventTaskLock.lock()
        defer { eventTaskLock.unlock() }
        eventTask?.cancel()
        eventTask = nil
    }

    func stop() {
        stopEventForwarding()
        terminationLock.lock()
        let shouldNotify = !isTerminated
        isTerminated = true
        terminationLock.unlock()
        if shouldNotify { onTermination() }
    }

    deinit { stop() }
}

actor MachRunEventHub {
    private var continuations: [UUID: AsyncStream<RunEvent>.Continuation] = [:]

    func stream() -> AsyncStream<RunEvent> {
        let identifier = UUID()
        let stream = AsyncStream<RunEvent>.makeStream(bufferingPolicy: .bufferingNewest(100))
        continuations[identifier] = stream.continuation
        stream.continuation.onTermination = { [weak self] _ in
            Task { await self?.remove(identifier) }
        }
        return stream.stream
    }

    func receive(_ data: Data) {
        guard let envelope = try? ProtocolEnvelope(serializedData: data),
              envelope.kind == .event,
              envelope.channel == .runStream,
              envelope.payload.identifier == RunEventPayload.identifier,
              let event = try? RunEventPayload(protobufBytes: envelope.payload.protobufBytes).event else { return }
        for continuation in continuations.values { continuation.yield(event) }
    }

    /// An XPC interruption invalidates every live subscription. New subscribers may be created
    /// after launchd reconnects the Mach service, but consumers must first replay durable state.
    func finish() {
        for continuation in continuations.values { continuation.finish() }
        continuations.removeAll()
    }

    private func remove(_ identifier: UUID) {
        continuations.removeValue(forKey: identifier)
    }
}

private final class MachMessage: @unchecked Sendable {
    let value: xpc_object_t

    init(_ value: xpc_object_t) {
        self.value = value
    }
}
