import AizenTransport
import AizenWire
import Foundation

/// The only XPC surface: Wire envelopes remain protobuf `Data`, not mirrored Objective-C models.
@objc public protocol AizenXPCWireService {
    func send(_ request: Data, reply: @escaping (Data?, NSError?) -> Void)
}

public enum XPCWireTransportError: Swift.Error, Sendable, Equatable {
    case invalidResponse
    case remoteFailure(String)
}

/// Client-side request/reply adapter for a local Host Mach service.
public final class XPCWireTransport: @unchecked Sendable, WireTransport {
    private let connection: NSXPCConnection

    public init(machServiceName: String) {
        connection = NSXPCConnection(machServiceName: machServiceName, options: [])
        connection.remoteObjectInterface = NSXPCInterface(with: AizenXPCWireService.self)
        connection.resume()
    }

    deinit {
        connection.invalidate()
    }

    public func send(_ envelope: ProtocolEnvelope) async throws -> ProtocolEnvelope {
        let request = try envelope.serializedData()
        let response: Data = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            guard let service = connection.remoteObjectProxyWithErrorHandler({ error in
                continuation.resume(throwing: error)
            }) as? AizenXPCWireService else {
                continuation.resume(throwing: XPCWireTransportError.remoteFailure("Host XPC service is unavailable"))
                return
            }
            service.send(request) { data, error in
                if let error {
                    continuation.resume(throwing: XPCWireTransportError.remoteFailure(error.localizedDescription))
                } else if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: XPCWireTransportError.invalidResponse)
                }
            }
        }
        return try ProtocolEnvelope(serializedData: response)
    }
}

/// Host-side adapter intended to be exported from the persistent XPC helper.
public final class XPCWireService: NSObject, AizenXPCWireService {
    private let endpoint: any WireEndpoint

    public init(endpoint: any WireEndpoint) {
        self.endpoint = endpoint
    }

    public func send(_ request: Data, reply: @escaping (Data?, NSError?) -> Void) {
        let endpoint = endpoint
        let reply = XPCReply(reply)
        Task { [endpoint, reply] in
            do {
                let envelope = try ProtocolEnvelope(serializedData: request)
                let response = try await endpoint.receive(envelope)
                reply.call(try response.serializedData(), nil)
            } catch {
                reply.call(nil, error as NSError)
            }
        }
    }
}

private final class XPCReply: @unchecked Sendable {
    private let block: (Data?, NSError?) -> Void

    init(_ block: @escaping (Data?, NSError?) -> Void) {
        self.block = block
    }

    func call(_ data: Data?, _ error: NSError?) {
        block(data, error)
    }
}
