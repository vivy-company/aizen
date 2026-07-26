import AizenCore
import AizenTransport
import AizenWire
import Dispatch
import Foundation
@preconcurrency import XPC

/// Errors surfaced by the authenticated production Mach XPC transport.
public enum MachWireTransportError: Swift.Error, Sendable, Equatable {
    case invalidResponse
    case unavailable
    case invalidCodeSigningRequirement(Int32)
}

public enum HostMachServiceConfigurationError: Swift.Error, Sendable, Equatable {
    case invalidTeamIdentifier
}

/// Stable identity of the user-level Host Mach service and its accepted signed peers.
public struct HostMachServiceConfiguration: Sendable, Equatable {
    public let machServiceName: String
    public let teamIdentifier: String

    public init(machServiceName: String, teamIdentifier: String) throws {
        guard !machServiceName.isEmpty,
              !teamIdentifier.isEmpty,
              teamIdentifier.unicodeScalars.allSatisfy({ $0.isASCII && ($0.properties.isAlphabetic || $0.properties.numericType != nil) }) else {
            throw HostMachServiceConfigurationError.invalidTeamIdentifier
        }
        self.machServiceName = machServiceName
        self.teamIdentifier = teamIdentifier
    }

    public var peerCodeSigningRequirement: String {
        "anchor apple generic and certificate leaf[subject.OU] = \"\(teamIdentifier)\""
    }
}

/// Client transport for the user-level Host Mach service.
public final class MachWireTransport: @unchecked Sendable, RunEventTransport {
    private let connection: xpc_connection_t
    private let events = MachRunEventHub()

    public init(machServiceName: String) {
        connection = xpc_connection_create_mach_service(machServiceName, nil, 0)
        xpc_connection_set_event_handler(connection) { [events] message in
            guard xpc_get_type(message) == XPC_TYPE_DICTIONARY else { return }
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
            xpc_connection_send_message_with_reply(connection, message, nil) { response in
                guard xpc_get_type(response) == XPC_TYPE_DICTIONARY else {
                    continuation.resume(throwing: MachWireTransportError.unavailable)
                    return
                }
                var length = 0
                guard let bytes = xpc_dictionary_get_data(response, "response", &length) else {
                    continuation.resume(throwing: MachWireTransportError.invalidResponse)
                    return
                }
                continuation.resume(returning: Data(bytes: bytes, count: length))
            }
        }
        return try ProtocolEnvelope(serializedData: response)
    }

    public func runEvents() async throws -> AsyncStream<RunEvent> {
        await events.stream()
    }
}

/// Server listener for the user-level Host Mach service. XPC verifies the peer's code signature
/// before it delivers any request to the Host endpoint.
public final class MachWireHostListener: @unchecked Sendable {
    private let listener: xpc_connection_t
    private let service: MachWireService

    public init(
        configuration: HostMachServiceConfiguration,
        endpoint: any WireEndpoint
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
        service = MachWireService(endpoint: endpoint)
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

private final class MachWireService: @unchecked Sendable {
    private let endpoint: any WireEndpoint

    init(endpoint: any WireEndpoint) {
        self.endpoint = endpoint
    }

    func accept(_ connection: xpc_object_t) {
        let peer = MachConnection(connection)
        if let eventEndpoint = endpoint as? any RunEventEndpoint {
            Task { [peer] in
                let stream = await eventEndpoint.runEvents()
                for await event in stream {
                    guard let envelope = try? ProtocolEnvelope(
                        messageID: UUID().uuidString,
                        connectionSequence: event.sequence,
                        kind: .event,
                        channel: .runStream,
                        payload: TypedPayload(RunEventPayload(event: event))
                    ).serializedData() else { continue }
                    peer.sendEvent(envelope)
                }
            }
        }
        xpc_connection_set_event_handler(connection) { [endpoint, peer] message in
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
                guard let envelope = try? ProtocolEnvelope(serializedData: request),
                      let response = try? await endpoint.receive(envelope),
                      let data = try? response.serializedData() else {
                    peer.send(replyMessage)
                    return
                }
                data.withUnsafeBytes { bytes in
                    xpc_dictionary_set_data(replyMessage.value, "response", bytes.baseAddress, bytes.count)
                }
                peer.send(replyMessage)
            }
        }
        xpc_connection_activate(connection)
    }
}

private final class MachConnection: @unchecked Sendable {
    let value: xpc_connection_t

    init(_ value: xpc_connection_t) {
        self.value = value
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
}

private actor MachRunEventHub {
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
