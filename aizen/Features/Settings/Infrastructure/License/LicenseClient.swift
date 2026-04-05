//
//  LicenseClient.swift
//  aizen
//
//  HTTP client for Aizen Pro licensing
//

import Foundation
import CryptoKit

struct LicenseClient {
    struct Config {
        var baseURL: URL
        var userAgent: String

        static let `default` = Config(
            baseURL: URL(string: "https://edge.aizen.win")!,
            userAgent: "Aizen-macOS"
        )
    }

    struct DeviceAuth {
        let deviceId: String
        let deviceSecret: String
    }

    let config: Config
    let session: URLSession

    init(config: Config = .default, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    // MARK: - API Models

    struct ActivateRequest: Encodable {
        let token: String
        let deviceFingerprint: String
        let deviceName: String
    }

    struct ActivateResponse: Decodable {
        let success: Bool
        let deviceId: String?
        let deviceSecret: String?
        let error: String?
    }

    struct ValidateRequest: Encodable {
        let token: String
    }

    struct ValidateResponse: Decodable {
        let valid: Bool
        let license: LicenseInfo?
        let error: String?
    }

    struct LicenseInfo: Decodable {
        let type: String?
        let status: String?
        let expiresAt: String?
    }

    struct StatusResponse: Decodable {
        let type: String?
        let status: String?
        let expiresAt: String?
    }

    struct PortalRequest: Encodable {
        let returnUrl: String
    }

    struct PortalResponse: Decodable {
        let url: String?
        let error: String?
    }

    struct ResendRequest: Encodable {
        let email: String
    }

    struct BasicResponse: Decodable {
        let success: Bool?
        let error: String?
    }

    struct APIErrorResponse: Decodable {
        let error: String?
    }

    // MARK: - Public API

    func activate(token: String, deviceFingerprint: String, deviceName: String) async throws -> ActivateResponse {
        let body = ActivateRequest(token: token, deviceFingerprint: deviceFingerprint, deviceName: deviceName)
        return try await request(
            path: "/api/licenses/activate",
            method: "POST",
            body: body,
            bearerToken: nil,
            deviceAuth: nil
        )
    }

    func validate(token: String, deviceAuth: DeviceAuth) async throws -> ValidateResponse {
        let body = ValidateRequest(token: token)
        return try await request(
            path: "/api/licenses/validate",
            method: "POST",
            body: body,
            bearerToken: nil,
            deviceAuth: deviceAuth
        )
    }

    func status(token: String, deviceAuth: DeviceAuth) async throws -> StatusResponse {
        return try await request(
            path: "/api/licenses/status",
            method: "GET",
            body: Optional<String>.none,
            bearerToken: token,
            deviceAuth: deviceAuth
        )
    }

    func portal(token: String, deviceAuth: DeviceAuth, returnUrl: String) async throws -> PortalResponse {
        let body = PortalRequest(returnUrl: returnUrl)
        return try await request(
            path: "/api/licenses/portal",
            method: "POST",
            body: body,
            bearerToken: token,
            deviceAuth: deviceAuth
        )
    }

    func resend(email: String) async throws -> BasicResponse {
        let body = ResendRequest(email: email)
        return try await request(
            path: "/api/licenses/resend",
            method: "POST",
            body: body,
            bearerToken: nil,
            deviceAuth: nil
        )
    }

    func deactivate(token: String, deviceAuth: DeviceAuth?) async throws -> BasicResponse {
        struct DeactivateRequest: Encodable {
            let token: String
        }
        let body = DeactivateRequest(token: token)
        return try await request(
            path: "/api/licenses/deactivate",
            method: "POST",
            body: body,
            bearerToken: nil,
            deviceAuth: deviceAuth
        )
    }

}

enum LicenseAPIError: LocalizedError {
    case server(String)
    case network(String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .server(let message):
            return message
        case .network(let message):
            return message
        case .decoding(let message):
            return message
        }
    }
}
