//
//  CodexRPCClient+Types.swift
//  aizen
//

import Foundation

struct RPCAccountResponse: Decodable {
    let account: RPCAccountDetails?
    let requiresOpenaiAuth: Bool?
}

enum RPCAccountDetails: Decodable {
    case apiKey
    case chatgpt(email: String, planType: String)

    enum CodingKeys: String, CodingKey {
        case type
        case email
        case planType
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type.lowercased() {
        case "apikey":
            self = .apiKey
        case "chatgpt":
            let email = try container.decodeIfPresent(String.self, forKey: .email) ?? ""
            let plan = try container.decodeIfPresent(String.self, forKey: .planType) ?? ""
            self = .chatgpt(email: email, planType: plan)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown account type \(type)"
            )
        }
    }
}

struct RPCRateLimitsResponse: Decodable {
    let rateLimits: RPCRateLimitSnapshot
}

struct RPCRateLimitSnapshot: Decodable {
    let primary: RPCRateLimitWindow?
    let secondary: RPCRateLimitWindow?
    let credits: RPCCreditsSnapshot?
}

struct RPCRateLimitWindow: Decodable {
    let usedPercent: Double
    let windowDurationMins: Int?
    let resetsAt: Int?
}

struct RPCCreditsSnapshot: Decodable {
    let hasCredits: Bool
    let unlimited: Bool
    let balance: String?
}

struct RateLimitsSnapshot {
    let primary: RateWindow?
    let secondary: RateWindow?
    let credits: CreditsSnapshot?

    init(from snapshot: RPCRateLimitSnapshot) {
        self.primary = RateWindow(from: snapshot.primary)
        self.secondary = RateWindow(from: snapshot.secondary)
        self.credits = CreditsSnapshot(from: snapshot.credits)
    }
}

struct RateWindow {
    let usedPercent: Double
    let windowMinutes: Int?
    let resetsAt: Date?
    let resetDescription: String?

    init?(from rpc: RPCRateLimitWindow?) {
        guard let rpc else { return nil }
        let resetsAt = rpc.resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        self.usedPercent = rpc.usedPercent
        self.windowMinutes = rpc.windowDurationMins
        self.resetsAt = resetsAt
        self.resetDescription = resetsAt.map { Self.resetDescription(from: $0) }
    }

    private static func resetDescription(from date: Date) -> String {
        UsageFormatter.resetDateString(date)
    }
}

struct CreditsSnapshot {
    let balance: Double?

    init?(from rpc: RPCCreditsSnapshot?) {
        guard let rpc else { return nil }
        if let balance = rpc.balance, let value = Double(balance) {
            self.balance = value
        } else {
            self.balance = nil
        }
    }
}
