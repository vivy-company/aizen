//
//  LicenseStore.swift
//  aizen
//
//  Persistence for license state
//

import Foundation

struct LicenseCache: Codable, Equatable {
    let type: String?
    let status: String?
    let expiresAt: Date?
    let isValid: Bool
    let lastValidatedAt: Date
}

final class LicenseStore {
    private let keychain = KeychainStore(service: "win.aizen.app.license")
    private let defaults = UserDefaults.standard

    private enum DefaultsKey {
        static let cache = "license.cache"
    }

    private enum KeychainKey {
        static let token = "license.token"
        static let deviceId = "license.deviceId"
        static let deviceSecret = "license.deviceSecret"
        static let deviceFingerprint = "license.deviceFingerprint"
    }

    func loadToken() -> String? {
        keychain.get(KeychainKey.token)
    }

    func saveToken(_ token: String) {
        try? keychain.set(token, for: KeychainKey.token)
    }

    func clearToken() {
        keychain.delete(KeychainKey.token)
    }

    func loadDeviceId() -> String? {
        keychain.get(KeychainKey.deviceId)
    }

    func saveDeviceId(_ deviceId: String) {
        try? keychain.set(deviceId, for: KeychainKey.deviceId)
    }

    func clearDeviceId() {
        keychain.delete(KeychainKey.deviceId)
    }

    func loadDeviceSecret() -> String? {
        keychain.get(KeychainKey.deviceSecret)
    }

    func saveDeviceSecret(_ deviceSecret: String) {
        try? keychain.set(deviceSecret, for: KeychainKey.deviceSecret)
    }

    func clearDeviceSecret() {
        keychain.delete(KeychainKey.deviceSecret)
    }

    func loadDeviceFingerprint() -> String? {
        keychain.get(KeychainKey.deviceFingerprint)
    }

    func saveDeviceFingerprint(_ fingerprint: String) {
        try? keychain.set(fingerprint, for: KeychainKey.deviceFingerprint)
    }

    func clearDeviceFingerprint() {
        keychain.delete(KeychainKey.deviceFingerprint)
    }

    func loadCache() -> LicenseCache? {
        guard let data = defaults.data(forKey: DefaultsKey.cache) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(LicenseCache.self, from: data)
    }

    func saveCache(_ cache: LicenseCache) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(cache) {
            defaults.set(data, forKey: DefaultsKey.cache)
        }
    }

    func clearCache() {
        defaults.removeObject(forKey: DefaultsKey.cache)
    }
}
