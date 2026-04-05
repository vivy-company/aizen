import Foundation
import CryptoKit

extension LicenseClient {
    // MARK: - Request Helper

    func request<T: Decodable, Body: Encodable>(
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

    func hmacSHA256Hex(payload: String, secret: String) -> String {
        let keyData = hexToData(secret) ?? Data(secret.utf8)
        let key = SymmetricKey(data: keyData)
        let signature = HMAC<SHA256>.authenticationCode(for: Data(payload.utf8), using: key)
        return signature.map { String(format: "%02x", $0) }.joined()
    }

    func hexToData(_ hex: String) -> Data? {
        let clean = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count.isMultiple(of: 2) else { return nil }

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

    func canonicalJSONString(from data: Data) -> String? {
        guard let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []) else {
            return nil
        }

        let options: JSONSerialization.WritingOptions = [.sortedKeys, .withoutEscapingSlashes]
        guard let canonicalData = try? JSONSerialization.data(withJSONObject: jsonObject, options: options) else {
            return nil
        }

        return String(data: canonicalData, encoding: .utf8)
    }

    func errorMessage(from data: Data, response: HTTPURLResponse) -> String? {
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

        return "Request failed (\(response.statusCode))"
    }
}
