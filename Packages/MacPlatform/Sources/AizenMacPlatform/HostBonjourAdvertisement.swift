import AizenSecurity
import CryptoKit
import Foundation

/// The only metadata Aizen publishes through Bonjour; it intentionally excludes user and workspace data.
public struct HostBonjourMetadata: Sendable, Hashable {
    public let minimumProtocolGeneration: UInt32
    public let maximumProtocolGeneration: UInt32
    public let hostHint: String
    public let fingerprintPrefix: String
    public let pairingRequired: Bool

    public init(host: HostPublicIdentity, minimumProtocolGeneration: UInt32, maximumProtocolGeneration: UInt32, pairingRequired: Bool = true) {
        precondition(minimumProtocolGeneration > 0 && minimumProtocolGeneration <= maximumProtocolGeneration, "Protocol range must be non-empty")
        self.minimumProtocolGeneration = minimumProtocolGeneration
        self.maximumProtocolGeneration = maximumProtocolGeneration
        hostHint = Data(SHA256.hash(data: Data(host.hostID.description.utf8))).prefix(8).map { String(format: "%02x", $0) }.joined()
        fingerprintPrefix = host.cryptographicIdentity.fingerprint.prefix
        self.pairingRequired = pairingRequired
    }

    public var txtRecord: [String: Data] {
        [
            "pr": Data("\(minimumProtocolGeneration)-\(maximumProtocolGeneration)".utf8),
            "h": Data(hostHint.utf8),
            "fp": Data(fingerprintPrefix.utf8),
            "pair": Data((pairingRequired ? "1" : "0").utf8)
        ]
    }
}

/// Main-actor NetService adapter for publishing a real `_aizen-host._tcp` service.
@MainActor
public final class HostBonjourAdvertisement {
    public static let serviceType = "_aizen-host._tcp."

    private let metadata: HostBonjourMetadata
    private let serviceName: String
    private var service: NetService?

    public init(host: HostPublicIdentity, metadata: HostBonjourMetadata) {
        self.metadata = metadata
        serviceName = "Aizen-\(host.hostID.description.prefix(8))"
    }

    public func start(port: Int32) {
        precondition((1...65_535).contains(port), "Bonjour services need a valid TCP port")
        stop()
        let service = NetService(domain: "local.", type: Self.serviceType, name: serviceName, port: port)
        service.setTXTRecord(NetService.data(fromTXTRecord: metadata.txtRecord))
        service.publish(options: .listenForConnections)
        self.service = service
    }

    public func stop() {
        service?.stop()
        service = nil
    }
}
