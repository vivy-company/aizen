//
//  ClaudeUsageFetcher+Auth.swift
//  aizen
//

import Foundation
#if canImport(Security)
import Security
#endif

struct ClaudeOAuthCredentials {
    let accessToken: String
    let expiresAt: Date?
    let rateLimitTier: String?
    let email: String?
    let organization: String?
    let idToken: String?
    let subscriptionType: String?

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return Date() >= expiresAt
    }

    static func parse(data: Data) throws -> ClaudeOAuthCredentials {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaudeOAuthCredentialsError.decodeFailed
        }
        guard let oauth = root["claudeAiOauth"] as? [String: Any] else {
            throw ClaudeOAuthCredentialsError.decodeFailed
        }

        let accessToken = (oauth["accessToken"] as? String ?? oauth["access_token"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if accessToken.isEmpty { throw ClaudeOAuthCredentialsError.missingAccessToken }

        let expiresAtMs = oauth["expiresAt"] as? Double ?? oauth["expires_at"] as? Double
        let expiresAt = expiresAtMs.map { Date(timeIntervalSince1970: $0 / 1000.0) }

        let rateLimitTier = oauth["rateLimitTier"] as? String ?? oauth["rate_limit_tier"] as? String
        let idToken = oauth["idToken"] as? String ?? oauth["id_token"] as? String
        let subscriptionType = oauth["subscriptionType"] as? String ?? oauth["subscription_type"] as? String

        let email = findString(in: root, keys: ["email", "userEmail", "accountEmail", "primaryEmail"])
        let organization = findString(in: root, keys: ["organization", "org", "orgName", "team", "teamName", "company"])

        return ClaudeOAuthCredentials(
            accessToken: accessToken,
            expiresAt: expiresAt,
            rateLimitTier: rateLimitTier,
            email: email,
            organization: organization,
            idToken: idToken,
            subscriptionType: subscriptionType
        )
    }
}

enum ClaudeOAuthCredentialsError: LocalizedError {
    case decodeFailed
    case missingAccessToken
    case notFound
    case keychainError(Int)
    case readFailed(String)

    var errorDescription: String? {
        switch self {
        case .decodeFailed:
            return "Claude OAuth credentials are invalid."
        case .missingAccessToken:
            return "Claude OAuth access token missing. Run 'claude' to authenticate."
        case .notFound:
            return "Claude OAuth credentials not found. Run 'claude' to authenticate."
        case let .keychainError(status):
            return "Claude OAuth keychain error: \(status)"
        case let .readFailed(message):
            return "Claude OAuth credentials read failed: \(message)"
        }
    }
}

enum ClaudeOAuthCredentialsStore {
    private static let credentialsPath = ".claude/.credentials.json"
    private static let keychainService = "Claude Code-credentials"

    static func load() throws -> ClaudeOAuthCredentials {
        var lastError: Error?
        if let keychainData = try? loadFromKeychain() {
            do {
                return try ClaudeOAuthCredentials.parse(data: keychainData)
            } catch {
                lastError = error
            }
        }

        do {
            let fileData = try loadFromFile()
            return try ClaudeOAuthCredentials.parse(data: fileData)
        } catch {
            if let lastError { throw lastError }
            throw error
        }
    }

    private static func loadFromFile() throws -> Data {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let url = home.appendingPathComponent(credentialsPath)
        do {
            return try Data(contentsOf: url)
        } catch {
            if (error as NSError).code == NSFileReadNoSuchFileError {
                throw ClaudeOAuthCredentialsError.notFound
            }
            throw ClaudeOAuthCredentialsError.readFailed(error.localizedDescription)
        }
    }

    private static func loadFromKeychain() throws -> Data {
        #if os(macOS)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw ClaudeOAuthCredentialsError.readFailed("Keychain item is empty.")
            }
            if data.isEmpty { throw ClaudeOAuthCredentialsError.notFound }
            return data
        case errSecItemNotFound:
            throw ClaudeOAuthCredentialsError.notFound
        default:
            throw ClaudeOAuthCredentialsError.keychainError(Int(status))
        }
        #else
        throw ClaudeOAuthCredentialsError.notFound
        #endif
    }
}

private func findString(in object: Any?, keys: Set<String>, depth: Int = 0) -> String? {
    guard depth <= 4 else { return nil }
    if let dict = object as? [String: Any] {
        for (key, value) in dict {
            if keys.contains(key), let str = value as? String, !str.isEmpty {
                return str
            }
            if let nested = findString(in: value, keys: keys, depth: depth + 1) { return nested }
        }
    } else if let array = object as? [Any] {
        for item in array {
            if let nested = findString(in: item, keys: keys, depth: depth + 1) { return nested }
        }
    }
    return nil
}
