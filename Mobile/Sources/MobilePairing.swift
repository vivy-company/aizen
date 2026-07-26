import AizenCore
import AizenClient
import AizenSecurity
import AizenTransport
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
        case ready(hostName: String, spaceCount: Int)
        case failed(String)
    }

    @Published private(set) var state: State = .unpaired
    @Published private(set) var spaces: [Space] = []
    @Published private(set) var sessions: [Session] = []
    @Published var selectedSpaceID: SpaceID?
    @Published var selectedSessionID: SessionID?
    @Published private(set) var messages: [ConversationMessage] = []
    @Published private(set) var activeRunID: RunID?
    private var client: HostClient?
    private var eventsTask: Task<Void, Never>?

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

    func reconnect() async {
        do {
            guard let pairedHost = try MobilePairedHostStore.load() else { throw MobilePairingError.noPairedHost }
            state = .pairing
            let identity = try MobileDeviceIdentityStore.loadOrCreate()
            let device = DevicePublicIdentity(deviceID: identity.deviceID, displayName: UIDevice.current.name, platform: "iOS", cryptographicIdentity: identity.identity.publicIdentity(createdAt: identity.createdAt))
            let exchange = try MobileWebSocketExchange(endpoint: pairedHost.endpoint)
            try await exchange.start()
            _ = try TransportRouteConfiguration(kind: .lan, endpoint: pairedHost.endpoint, expectedHostIdentity: pairedHost.host.cryptographicIdentity.fingerprint.description)
            let transport = try await RemoteClientAuthenticator(host: pairedHost.host, device: device, deviceIdentity: identity.identity, route: .lan).authenticate(
                using: { frame in try await exchange.exchange(frame) },
                frameSender: { frame in try await exchange.send(frame) },
                frameStream: { exchange.frames() }
            )
            let client = HostClient(transport: transport)
            _ = try await client.negotiate()
            let spaces = try await client.spaces()
            self.client = client
            self.spaces = spaces
            selectedSpaceID = spaces.first?.id
            sessions = try await client.conversations(spaceID: selectedSpaceID)
            subscribe(to: client)
            state = .ready(hostName: pairedHost.host.displayName, spaceCount: spaces.count)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func selectSpace(_ id: SpaceID) async {
        guard let client else { return }
        do {
            selectedSpaceID = id
            selectedSessionID = nil
            messages = []
            sessions = try await client.conversations(spaceID: id)
        } catch { state = .failed(error.localizedDescription) }
    }

    func selectSession(_ id: SessionID) async {
        guard let client else { return }
        do {
            selectedSessionID = id
            messages = try await client.conversationTimeline(sessionID: id)
        } catch { state = .failed(error.localizedDescription) }
    }

    func createConversation(title: String) async {
        guard let client, let spaceID = selectedSpaceID, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do {
            let id = try await client.createConversation(spaceID: spaceID, title: title)
            sessions = try await client.conversations(spaceID: spaceID)
            await selectSession(id)
        } catch { state = .failed(error.localizedDescription) }
    }

    func sendMessage(_ content: String) async {
        guard let client, let spaceID = selectedSpaceID, let sessionID = selectedSessionID,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do {
            activeRunID = try await client.sendConversation(spaceID: spaceID, sessionID: sessionID, content: content)
            messages = try await client.conversationTimeline(sessionID: sessionID)
        } catch { state = .failed(error.localizedDescription) }
    }

    func cancelActiveRun() async {
        guard let client, let activeRunID else { return }
        do {
            try await client.cancelRun(id: activeRunID)
            self.activeRunID = nil
        } catch { state = .failed(error.localizedDescription) }
    }

    private func subscribe(to client: HostClient) {
        eventsTask?.cancel()
        eventsTask = Task { [weak self] in
            guard let self else { return }
            guard let events = try? await client.runEvents() else { return }
            for await event in events {
                guard !Task.isCancelled else { return }
                guard case let .run(run) = event else { continue }
                if run.sessionID == self.selectedSessionID, case .lifecycle(let lifecycle) = run.kind,
                   lifecycle == .completed || lifecycle == .failed || lifecycle == .cancelled {
                    self.activeRunID = nil
                    if let client = self.client, let sessionID = self.selectedSessionID {
                        self.messages = (try? await client.conversationTimeline(sessionID: sessionID)) ?? self.messages
                    }
                }
            }
        }
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
    case noPairedHost
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidInvitation: "This pairing QR code is invalid or expired."
        case .missingEndpoint: "This pairing invitation does not include a secure Host endpoint."
        case .noPairedHost: "No approved Host is available to reconnect."
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
    static func load() throws -> MobilePairedHost? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try JSONDecoder().decode(MobilePairedHost.self, from: data)
    }
}

nonisolated private final class MobileWebSocketExchange: @unchecked Sendable {
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

    func frames() -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            queue.async { [weak self] in self?.receiveNext(continuation) }
            continuation.onTermination = { [weak self] _ in self?.connection.cancel() }
        }
    }

    func send(_ frame: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: frame, contentContext: .init(identifier: "aizen.binary", metadata: [NWProtocolWebSocket.Metadata(opcode: .binary)]), isComplete: true, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            })
        }
    }

    private func receiveNext(_ continuation: AsyncThrowingStream<Data, Error>.Continuation) {
        connection.receiveMessage { [weak self] content, context, _, error in
            guard let self else { return }
            guard error == nil, let content,
                  (context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata)?.opcode == .binary else {
                continuation.finish(throwing: error ?? MobilePairingError.invalidInvitation)
                return
            }
            continuation.yield(content)
            self.receiveNext(continuation)
        }
    }
}
