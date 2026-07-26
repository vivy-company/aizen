import AizenCore
import AizenSecurity
import Foundation
import Security

/// The Host's public identity and in-memory signing material for one process lifetime.
public struct HostIdentityCredentials: Sendable {
    public let publicIdentity: HostPublicIdentity
    public let localIdentity: LocalCryptographicIdentity

    public init(publicIdentity: HostPublicIdentity, localIdentity: LocalCryptographicIdentity) {
        self.publicIdentity = publicIdentity
        self.localIdentity = localIdentity
    }
}

/// Durable Host identity persistence. The private signing and agreement keys remain Keychain-only.
public actor HostIdentityStore {
    private struct StoredIdentity: Codable, Sendable {
        let hostID: HostID
        let signingPrivateKey: Data
        let keyAgreementPrivateKey: Data
        let createdAt: Date
    }

    private let persistence: any HostIdentityPersisting

    public init(persistence: any HostIdentityPersisting = KeychainHostIdentityPersistence()) {
        self.persistence = persistence
    }

    public func loadOrCreate(displayName: String) throws -> HostPublicIdentity {
        try loadOrCreateCredentials(displayName: displayName).publicIdentity
    }

    public func loadOrCreateCredentials(displayName: String) throws -> HostIdentityCredentials {
        if let data = try persistence.load() {
            let stored = try JSONDecoder().decode(StoredIdentity.self, from: data)
            let identity = try LocalCryptographicIdentity(
                signingPrivateKey: stored.signingPrivateKey,
                keyAgreementPrivateKey: stored.keyAgreementPrivateKey
            )
            return HostIdentityCredentials(
                publicIdentity: HostPublicIdentity(
                    hostID: stored.hostID,
                    displayName: displayName,
                    cryptographicIdentity: identity.publicIdentity(createdAt: stored.createdAt)
                ),
                localIdentity: identity
            )
        }

        let identity = LocalCryptographicIdentity()
        let createdAt = Date()
        let stored = StoredIdentity(
            hostID: HostID(),
            signingPrivateKey: identity.signingPrivateKey,
            keyAgreementPrivateKey: identity.keyAgreementPrivateKey,
            createdAt: createdAt
        )
        try persistence.save(JSONEncoder().encode(stored))
        return HostIdentityCredentials(
            publicIdentity: HostPublicIdentity(
                hostID: stored.hostID,
                displayName: displayName,
                cryptographicIdentity: identity.publicIdentity(createdAt: createdAt)
            ),
            localIdentity: identity
        )
    }
}

public protocol HostIdentityPersisting: Sendable {
    func load() throws -> Data?
    func save(_ data: Data) throws
}

public final class KeychainHostIdentityPersistence: @unchecked Sendable, HostIdentityPersisting {
    private static let service = "win.aizen.host.identity"
    private static let account = "current"

    public init() {}

    public func load() throws -> Data? {
        var query = Self.query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw KeychainError(status) }
        return data
    }

    public func save(_ data: Data) throws {
        let query = Self.query
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status) }
    }

    private static var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
