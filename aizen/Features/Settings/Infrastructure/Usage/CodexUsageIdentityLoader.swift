//
//  CodexUsageIdentityLoader.swift
//  aizen
//

import Foundation

enum CodexUsageIdentityLoader {
    static func loadAccountIdentity() -> UsageUserIdentity? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let authURL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CODEX_HOME"] ?? "\(home.path)/.codex")
            .appendingPathComponent("auth.json")
        guard let data = try? Data(contentsOf: authURL),
              let auth = try? JSONDecoder().decode(AuthFile.self, from: data),
              let idToken = auth.tokens?.idToken,
              let payload = JWTDecoder.payload(from: idToken)
        else {
            return nil
        }

        let authDict = payload["https://api.openai.com/auth"] as? [String: Any]
        let profileDict = payload["https://api.openai.com/profile"] as? [String: Any]

        let plan = (authDict?["chatgpt_plan_type"] as? String)
            ?? (payload["chatgpt_plan_type"] as? String)
        let email = (payload["email"] as? String)
            ?? (profileDict?["email"] as? String)
        let organization = resolveOrganizationName(authDict: authDict, profileDict: profileDict)

        return UsageUserIdentity(email: email, organization: organization, plan: plan)
    }

    static func userIdentity(from response: RPCAccountResponse) -> UsageUserIdentity? {
        guard let account = response.account else { return nil }
        switch account {
        case .apiKey:
            return nil
        case let .chatgpt(email, planType):
            let cleanEmail = email.isEmpty ? nil : email
            let cleanPlan = planType.isEmpty ? nil : planType
            return UsageUserIdentity(email: cleanEmail, organization: nil, plan: cleanPlan)
        }
    }

    private static func resolveOrganizationName(
        authDict: [String: Any]?,
        profileDict: [String: Any]?
    ) -> String? {
        if let orgName = authDict?["org_name"] as? String { return orgName }
        if let orgId = authDict?["org_id"] as? String { return orgId }
        if let orgName = profileDict?["organization"] as? String { return orgName }
        if let orgName = profileDict?["org_name"] as? String { return orgName }

        if let orgs = authDict?["organizations"] as? [[String: Any]] {
            if let defaultOrg = orgs.first(where: { ($0["is_default"] as? Bool) == true }) {
                if let title = defaultOrg["title"] as? String { return title }
                if let orgId = defaultOrg["id"] as? String { return orgId }
            }
            if let first = orgs.first {
                if let title = first["title"] as? String { return title }
                if let orgId = first["id"] as? String { return orgId }
            }
        }

        return nil
    }
}

private struct AuthFile: Decodable {
    struct Tokens: Decodable {
        let idToken: String?

        enum CodingKeys: String, CodingKey {
            case idTokenSnake = "id_token"
            case idTokenCamel = "idToken"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.idToken = try container.decodeIfPresent(String.self, forKey: .idTokenSnake)
                ?? container.decodeIfPresent(String.self, forKey: .idTokenCamel)
        }
    }

    let tokens: Tokens?
}
