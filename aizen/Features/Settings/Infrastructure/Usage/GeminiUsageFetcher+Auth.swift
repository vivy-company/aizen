//
//  GeminiUsageFetcher+Auth.swift
//  aizen
//

import Foundation

enum GeminiAuthType: String {
    case oauthPersonal = "oauth-personal"
    case apiKey = "api-key"
    case vertexAI = "vertex-ai"
    case unknown
}

func currentAuthType(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> GeminiAuthType {
    let url = homeDirectory.appendingPathComponent(".gemini/settings.json")
    guard let data = try? Data(contentsOf: url),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let security = json["security"] as? [String: Any],
          let auth = security["auth"] as? [String: Any],
          let selected = auth["selectedType"] as? String
    else {
        return .unknown
    }

    return GeminiAuthType(rawValue: selected) ?? .unknown
}

struct GeminiOAuthCredentials {
    var accessToken: String?
    let idToken: String?
    let refreshToken: String?
    let expiryDate: Date?
}

func loadCredentials(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) throws -> GeminiOAuthCredentials {
    let url = homeDirectory.appendingPathComponent(".gemini/oauth_creds.json")
    guard FileManager.default.fileExists(atPath: url.path) else {
        throw GeminiStatusError.notLoggedIn
    }

    let data = try Data(contentsOf: url)
    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw GeminiStatusError.parseFailed("Invalid credentials file")
    }

    let accessToken = json["access_token"] as? String
    let idToken = json["id_token"] as? String
    let refreshToken = json["refresh_token"] as? String

    var expiryDate: Date?
    if let expiryMs = json["expiry_date"] as? Double {
        expiryDate = Date(timeIntervalSince1970: expiryMs / 1000)
    }

    return GeminiOAuthCredentials(
        accessToken: accessToken,
        idToken: idToken,
        refreshToken: refreshToken,
        expiryDate: expiryDate
    )
}

enum GeminiStatusError: LocalizedError {
    case geminiNotInstalled
    case notLoggedIn
    case parseFailed(String)
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .geminiNotInstalled:
            return "Gemini CLI is not installed or not on PATH."
        case .notLoggedIn:
            return "Not logged in to Gemini. Run 'gemini' to authenticate."
        case let .parseFailed(message):
            return "Could not parse Gemini usage: \(message)"
        case let .apiError(message):
            return "Gemini API error: \(message)"
        }
    }
}

private struct GeminiOAuthClientCredentials {
    let clientId: String
    let clientSecret: String
}

func refreshAccessToken(
    refreshToken: String,
    homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
) async throws -> String {
    guard let url = URL(string: "https://oauth2.googleapis.com/token") else {
        throw GeminiStatusError.apiError("Invalid token refresh URL")
    }

    guard let oauthCreds = extractOAuthCredentials() else {
        throw GeminiStatusError.apiError("Could not find Gemini CLI OAuth configuration")
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

    let body = [
        "client_id=\(oauthCreds.clientId)",
        "client_secret=\(oauthCreds.clientSecret)",
        "refresh_token=\(refreshToken)",
        "grant_type=refresh_token",
    ].joined(separator: "&")
    request.httpBody = body.data(using: .utf8)

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
        throw GeminiStatusError.apiError("Invalid refresh response")
    }
    guard httpResponse.statusCode == 200 else {
        throw GeminiStatusError.notLoggedIn
    }

    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let newAccessToken = json["access_token"] as? String
    else {
        throw GeminiStatusError.parseFailed("Could not parse refresh response")
    }

    try updateStoredCredentials(json, homeDirectory: homeDirectory)
    return newAccessToken
}

private func updateStoredCredentials(_ refreshResponse: [String: Any], homeDirectory: URL) throws {
    let credsURL = homeDirectory.appendingPathComponent(".gemini/oauth_creds.json")
    guard let existing = try? Data(contentsOf: credsURL),
          var json = try? JSONSerialization.jsonObject(with: existing) as? [String: Any]
    else {
        return
    }

    if let accessToken = refreshResponse["access_token"] {
        json["access_token"] = accessToken
    }
    if let expiresIn = refreshResponse["expires_in"] as? Double {
        json["expiry_date"] = (Date().timeIntervalSince1970 + expiresIn) * 1000
    }
    if let idToken = refreshResponse["id_token"] {
        json["id_token"] = idToken
    }

    let updated = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted])
    try updated.write(to: credsURL, options: .atomic)
}

private func extractOAuthCredentials() -> GeminiOAuthClientCredentials? {
    guard let geminiPath = resolveGeminiBinary() else { return nil }

    let fm = FileManager.default
    var realPath = geminiPath
    if let resolved = try? fm.destinationOfSymbolicLink(atPath: geminiPath) {
        if resolved.hasPrefix("/") {
            realPath = resolved
        } else {
            realPath = (geminiPath as NSString).deletingLastPathComponent + "/" + resolved
        }
    }

    let binDir = (realPath as NSString).deletingLastPathComponent
    let baseDir = (binDir as NSString).deletingLastPathComponent

    let oauthSubpath = "node_modules/@google/gemini-cli/node_modules/@google/gemini-cli-core/dist/src/code_assist/oauth2.js"
    let oauthFile = "dist/src/code_assist/oauth2.js"
    let possiblePaths = [
        "\(baseDir)/libexec/lib/\(oauthSubpath)",
        "\(baseDir)/lib/\(oauthSubpath)",
        "\(baseDir)/../gemini-cli-core/\(oauthFile)",
        "\(baseDir)/node_modules/@google/gemini-cli-core/\(oauthFile)",
    ]

    for path in possiblePaths {
        if let content = try? String(contentsOfFile: path, encoding: .utf8),
           let creds = parseOAuthCredentials(from: content) {
            return creds
        }
    }

    return nil
}

private func parseOAuthCredentials(from content: String) -> GeminiOAuthClientCredentials? {
    let clientIdPattern = #"OAUTH_CLIENT_ID\s*=\s*['\"]([\w\-\.]+)['\"]\s*;"#
    let secretPattern = #"OAUTH_CLIENT_SECRET\s*=\s*['\"]([\w\-]+)['\"]\s*;"#

    guard let clientIdRegex = try? NSRegularExpression(pattern: clientIdPattern),
          let secretRegex = try? NSRegularExpression(pattern: secretPattern)
    else {
        return nil
    }

    let range = NSRange(content.startIndex..., in: content)
    guard let clientIdMatch = clientIdRegex.firstMatch(in: content, range: range),
          let secretMatch = secretRegex.firstMatch(in: content, range: range),
          let clientIdRange = Range(clientIdMatch.range(at: 1), in: content),
          let secretRange = Range(secretMatch.range(at: 1), in: content)
    else {
        return nil
    }

    return GeminiOAuthClientCredentials(
        clientId: String(content[clientIdRange]),
        clientSecret: String(content[secretRange])
    )
}

private func resolveGeminiBinary() -> String? {
    let managed = ACPRegistryService.managedBinaryPath(agentID: "gemini", commandPath: "./gemini")
    if FileManager.default.isExecutableFile(atPath: managed) {
        return managed
    }
    let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
    for dir in path.split(separator: ":") {
        let candidate = "\(dir)/gemini"
        if FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
    }
    return nil
}
