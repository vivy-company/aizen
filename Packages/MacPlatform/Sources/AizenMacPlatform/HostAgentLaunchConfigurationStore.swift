import AizenHost
import AizenWire
import Foundation
import Security

/// Host-owned persistence for ACP launch inputs. The environment is kept exclusively in Keychain.
public actor HostAgentLaunchConfigurationStore: AgentLaunchConfigurationUpdating, ACPAgentLaunchConfigurationResolving {
    public enum Error: Swift.Error, Sendable, Equatable {
        case notConfigured
        case invalidConfiguration
    }

    private struct StoredConfiguration: Codable, Sendable, Equatable {
        let executablePath: String
        let arguments: [String]
    }

    private let configurationURL: URL
    private let secrets: any HostAgentEnvironmentStoring

    public init(configurationURL: URL, secrets: any HostAgentEnvironmentStoring = KeychainHostAgentEnvironmentStore()) {
        self.configurationURL = configurationURL.standardizedFileURL
        self.secrets = secrets
    }

    public func updateAgentLaunchConfiguration(_ configuration: ConfigureAgentLaunchCommandPayload) async throws {
        guard !configuration.executablePath.isEmpty else { throw Error.invalidConfiguration }
        let data = try JSONEncoder().encode(StoredConfiguration(
            executablePath: configuration.executablePath,
            arguments: configuration.arguments
        ))
        try FileManager.default.createDirectory(at: configurationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: configurationURL, options: .atomic)
        try secrets.store(environment: configuration.environment)
    }

    public func launchConfiguration() async throws -> ACPAgentLaunchConfiguration {
        guard let data = try? Data(contentsOf: configurationURL),
              let configuration = try? JSONDecoder().decode(StoredConfiguration.self, from: data) else {
            throw Error.notConfigured
        }
        return ACPAgentLaunchConfiguration(
            executablePath: configuration.executablePath,
            arguments: configuration.arguments,
            environment: try secrets.environment()
        )
    }
}

public protocol HostAgentEnvironmentStoring: Sendable {
    func store(environment: [String: String]) throws
    func environment() throws -> [String: String]
}

public final class KeychainHostAgentEnvironmentStore: @unchecked Sendable, HostAgentEnvironmentStoring {
    private static let service = "win.aizen.host.agent-launch"
    private static let account = "current"

    public init() {}

    public func store(environment: [String: String]) throws {
        let data = try JSONEncoder().encode(environment)
        let query = Self.query
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status) }
    }

    public func environment() throws -> [String: String] {
        var query = Self.query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { throw HostAgentLaunchConfigurationStore.Error.notConfigured }
        return try JSONDecoder().decode([String: String].self, from: data)
    }

    private static var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

public struct KeychainError: Swift.Error, Sendable, Equatable {
    public let status: Int32

    init(_ status: OSStatus) {
        self.status = status
    }
}
