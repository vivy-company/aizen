import AizenCore
import AizenSecurity
import AizenWire
import Foundation
@preconcurrency import Network
import Security
import UIKit

@MainActor
final class MobilePairingStore: ObservableObject {
    enum State: Equatable {
        case unpaired
        case pairing
        case awaitingApproval(hostName: String)
        case failed(String)
    }

    @Published private(set) var state: State = .unpaired

    func submit(invitationText: String) async {
        do {
            let invitation = try MobilePairingInvitation.decode(invitationText)
            let endpoint = try MobilePairingInvitation.endpoint(from: invitation)
            state = .pairing
            let identity = try MobileDeviceIdentityStore.loadOrCreate()
            let exchange = try MobileWebSocketExchange(endpoint: endpoint)
            try await exchange.start()
            let device = DevicePublicIdentity(
                deviceID: identity.deviceID,
                displayName: UIDevice.current.name,
                platform: "iOS",
                cryptographicIdentity: identity.identity.publicIdentity(createdAt: identity.createdAt)
            )
            _ = try await PairingClientAuthenticator(
                invitation: invitation,
                device: device,
                deviceIdentity: identity.identity
            ).submit(using: { frame in try await exchange.exchange(frame) })
            try MobilePairedHostStore.save(.init(host: invitation.host, endpoint: endpoint))
            state = .awaitingApproval(hostName: invitation.host.displayName)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func recordScannerFailure(_ message: String) {
        state = .failed(message)
    }
}

private enum MobilePairingInvitation {
    static func decode(_ text: String) throws -> PairingInvitation {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload: String
        if let components = URLComponents(string: raw), components.scheme == "aizen",
           let encoded = components.queryItems?.first(where: { $0.name == "invitation" })?.value {
            payload = encoded
        } else {
            payload = raw
        }
        guard let data = Data(base64Encoded: payload) else { throw MobilePairingError.invalidInvitation }
        let invitation = try JSONDecoder().decode(PairingInvitation.self, from: data)
        try invitation.validate()
        return invitation
    }

    static func endpoint(from invitation: PairingInvitation) throws -> URL {
        guard let endpoint = invitation.endpointHints.lazy.compactMap(URL.init(string:)).first(where: { $0.scheme?.lowercased() == "wss" }) else {
            throw MobilePairingError.missingEndpoint
        }
        return endpoint
    }
}

private enum MobilePairingError: LocalizedError {
    case invalidInvitation
    case missingEndpoint
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidInvitation: "This pairing QR code is invalid or expired."
        case .missingEndpoint: "This pairing invitation does not include a secure Host endpoint."
        case let .keychain(status): "The device identity could not be stored securely (Keychain status \(status))."
        }
    }
}

private struct MobileDeviceIdentity {
    let deviceID: DeviceID
    let identity: LocalCryptographicIdentity
    let createdAt: Date
}

private enum MobileDeviceIdentityStore {
    private static let service = "win.aizen.mobile.identity"

    static func loadOrCreate() throws -> MobileDeviceIdentity {
        if let data = try load(), let record = try? JSONDecoder().decode(Record.self, from: data) {
            return .init(deviceID: .init(rawValue: record.deviceID), identity: try .init(signingPrivateKey: record.signingPrivateKey, keyAgreementPrivateKey: record.keyAgreementPrivateKey), createdAt: record.createdAt)
        }
        let identity = LocalCryptographicIdentity()
        let record = Record(deviceID: UUID(), signingPrivateKey: identity.signingPrivateKey, keyAgreementPrivateKey: identity.keyAgreementPrivateKey, createdAt: Date())
        try save(JSONEncoder().encode(record))
        return .init(deviceID: .init(rawValue: record.deviceID), identity: identity, createdAt: record.createdAt)
    }

    private struct Record: Codable {
        let deviceID: UUID
        let signingPrivateKey: Data
        let keyAgreementPrivateKey: Data
        let createdAt: Date
    }

    private static func load() throws -> Data? {
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecReturnData: true]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw MobilePairingError.keychain(status) }
        return data
    }

    private static func save(_ data: Data) throws {
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service]
        let attributes: [CFString: Any] = [kSecValueData: data, kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            attributes.forEach { insert[$0.key] = $0.value }
            let inserted = SecItemAdd(insert as CFDictionary, nil)
            guard inserted == errSecSuccess else { throw MobilePairingError.keychain(inserted) }
        } else if status != errSecSuccess {
            throw MobilePairingError.keychain(status)
        }
    }
}

private struct MobilePairedHost: Codable {
    let host: HostPublicIdentity
    let endpoint: URL
}

private enum MobilePairedHostStore {
    private static let key = "paired-host-v1"
    static func save(_ host: MobilePairedHost) throws { UserDefaults.standard.set(try JSONEncoder().encode(host), forKey: key) }
}

private final class MobileWebSocketExchange: @unchecked Sendable {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "win.aizen.mobile.pairing")

    init(endpoint: URL) throws {
        guard endpoint.scheme?.lowercased() == "wss", let host = endpoint.host else { throw MobilePairingError.missingEndpoint }
        let port = endpoint.port ?? 443
        guard (1...65_535).contains(port) else { throw MobilePairingError.missingEndpoint }
        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv13)
        sec_protocol_options_set_max_tls_protocol_version(tls.securityProtocolOptions, .TLSv13)
        sec_protocol_options_set_verify_block(tls.securityProtocolOptions, { _, _, complete in complete(true) }, queue)
        let parameters = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
        parameters.defaultProtocolStack.applicationProtocols.insert(NWProtocolWebSocket.Options(), at: 0)
        connection = NWConnection(host: .init(host), port: .init(rawValue: UInt16(port))!, using: parameters)
    }

    deinit { connection.cancel() }

    func start() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: continuation.resume()
                case let .failed(error): continuation.resume(throwing: error)
                case .cancelled: continuation.resume(throwing: MobilePairingError.invalidInvitation)
                default: break
                }
            }
            connection.start(queue: queue)
        }
    }

    func exchange(_ frame: Data) async throws -> Data {
        try await send(frame)
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            connection.receiveMessage { content, context, _, error in
                guard error == nil, let content,
                      (context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata)?.opcode == .binary else {
                    continuation.resume(throwing: error ?? MobilePairingError.invalidInvitation)
                    return
                }
                continuation.resume(returning: content)
            }
        }
    }

    private func send(_ frame: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: frame, contentContext: .init(identifier: "aizen.binary", metadata: [NWProtocolWebSocket.Metadata(opcode: .binary)]), isComplete: true, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            })
        }
    }
}
