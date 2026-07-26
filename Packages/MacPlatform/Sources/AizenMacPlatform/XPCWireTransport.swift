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

    public init(listenerEndpoint: NSXPCListenerEndpoint) {
        connection = NSXPCConnection(listenerEndpoint: listenerEndpoint)
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

/// Owns the server listener and makes the Wire service available to each accepted XPC connection.
/// The persistent Host process uses the Mach-service initializer; the endpoint initializer is used
/// for local integration tests without registering a system service.
public final class XPCWireHostListener: NSObject, NSXPCListenerDelegate {
    public let listenerEndpoint: NSXPCListenerEndpoint?

    private let listener: NSXPCListener
    private let service: XPCWireService

    public init(wireEndpoint: any WireEndpoint) {
        let listener = NSXPCListener.anonymous()
        self.listener = listener
        listenerEndpoint = listener.endpoint
        service = XPCWireService(endpoint: wireEndpoint)
        super.init()
        listener.delegate = self
    }

    public init(machServiceName: String, wireEndpoint: any WireEndpoint) {
        listener = NSXPCListener(machServiceName: machServiceName)
        listenerEndpoint = nil
        service = XPCWireService(endpoint: wireEndpoint)
        super.init()
        listener.delegate = self
    }

    public func resume() {
        listener.resume()
    }

    public func invalidate() {
        listener.invalidate()
    }

    public func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: AizenXPCWireService.self)
        connection.exportedObject = service
        connection.resume()
        return true
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
