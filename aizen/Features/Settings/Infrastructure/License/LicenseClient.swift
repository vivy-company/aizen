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

    private let config: Config
    private let session: URLSession

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

    // MARK: - Request Helper

    private func request<T: Decodable, Body: Encodable>(
        path: String,
        method: String,
        body: Body?,
        bearerToken: String?,
        deviceAuth: DeviceAuth?
    ) async throws -> T {
        let normalizedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let url = config.baseURL.appendingPathComponent(normalizedPath)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.userAgent, forHTTPHeaderField: "User-Agent")

        var bodyString = ""
        if let body {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(body)
            bodyString = canonicalJSONString(from: data) ?? ""
            request.httpBody = data
        }

        if let bearerToken {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }

        if let deviceAuth {
            let timestamp = String(Int(Date().timeIntervalSince1970))
            let signaturePayload = "\(timestamp).\(method).\(path).\(deviceAuth.deviceId).\(bodyString)"
            let signature = hmacSHA256Hex(payload: signaturePayload, secret: deviceAuth.deviceSecret)

            request.setValue(deviceAuth.deviceId, forHTTPHeaderField: "x-aizen-device-id")
            request.setValue(timestamp, forHTTPHeaderField: "x-aizen-timestamp")
            request.setValue(signature, forHTTPHeaderField: "x-aizen-signature")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw LicenseAPIError.network(error.localizedDescription)
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LicenseAPIError.network("Invalid response")
        }

        if !(200...299).contains(httpResponse.statusCode) {
            if let message = errorMessage(from: data, response: httpResponse) {
                throw LicenseAPIError.server(message)
            }
            throw LicenseAPIError.server("Request failed with status \(httpResponse.statusCode)")
        }

        let decoder = JSONDecoder()
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw LicenseAPIError.decoding("Invalid response format")
        }
    }

    private func hmacSHA256Hex(payload: String, secret: String) -> String {
        let keyData = hexToData(secret) ?? Data(secret.utf8)
        let key = SymmetricKey(data: keyData)
        let signature = HMAC<SHA256>.authenticationCode(for: Data(payload.utf8), using: key)
        return signature.map { String(format: "%02x", $0) }.joined()
    }

    private func hexToData(_ hex: String) -> Data? {
        let clean = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count % 2 == 0 else { return nil }

        var bytes = [UInt8]()
        bytes.reserveCapacity(clean.count / 2)
        var index = clean.startIndex
        while index < clean.endIndex {
            let nextIndex = clean.index(index, offsetBy: 2)
            let byteString = clean[index..<nextIndex]
            guard let byte = UInt8(byteString, radix: 16) else { return nil }
            bytes.append(byte)
            index = nextIndex
        }
        return Data(bytes)
    }

    private func canonicalJSONString(from data: Data) -> String? {
        guard let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []) else {
            return nil
        }

        let options: JSONSerialization.WritingOptions = [.sortedKeys, .withoutEscapingSlashes]
        guard let canonicalData = try? JSONSerialization.data(withJSONObject: jsonObject, options: options) else {
            return nil
        }

        return String(data: canonicalData, encoding: .utf8)
    }

    private func errorMessage(from data: Data, response: HTTPURLResponse) -> String? {
        if response.statusCode == 429 {
            if let retryAfter = response.value(forHTTPHeaderField: "Retry-After"), !retryAfter.isEmpty {
                return "Too many requests. Try again in \(retryAfter) seconds."
            }
            return "Too many requests. Please try again later."
        }

        let contentType = response.value(forHTTPHeaderField: "Content-Type") ?? ""
        if contentType.contains("application/json") {
            if let apiError = try? JSONDecoder().decode(APIErrorResponse.self, from: data),
               let message = apiError.error, !message.isEmpty {
                return message
            }
            if let body = String(data: data, encoding: .utf8), !body.isEmpty {
                return "Request failed (\(response.statusCode))"
            }
            return nil
        }

        // Avoid surfacing HTML or other non-JSON payloads to the user.
        return "Request failed (\(response.statusCode))"
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
