import Foundation

extension LicenseClient {
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
        try await request(
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
