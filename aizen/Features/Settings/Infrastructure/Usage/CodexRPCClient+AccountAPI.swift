import Foundation

extension CodexRPCClient {
    func initialize(clientName: String, clientVersion: String) async throws {
        _ = try await request(
            method: "initialize",
            params: ["clientInfo": ["name": clientName, "version": clientVersion]]
        )
        try sendNotification(method: "initialized")
    }

    func fetchRateLimits() async throws -> RateLimitsSnapshot {
        let message = try await request(method: "account/rateLimits/read")
        let response = try decodeResult(from: message, as: RPCRateLimitsResponse.self)
        return RateLimitsSnapshot(from: response.rateLimits)
    }

    func fetchAccount() async throws -> RPCAccountResponse {
        let message = try await request(method: "account/read")
        return try decodeResult(from: message, as: RPCAccountResponse.self)
    }
}
