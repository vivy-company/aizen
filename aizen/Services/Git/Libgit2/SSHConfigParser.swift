import Foundation
import Clibgit2

/// Parses ~/.ssh/config to find the IdentityFile for a given host
func findSSHKeyForHost(_ host: String) -> String? {
    let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
    let configPath = "\(homeDir)/.ssh/config"

    guard let content = try? String(contentsOfFile: configPath, encoding: .utf8) else {
        return nil
    }

    var currentHost: String?
    var currentIdentityFile: String?
    var wildcardIdentityFile: String?

    for line in content.components(separatedBy: .newlines) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if trimmed.isEmpty || trimmed.hasPrefix("#") {
            continue
        }

        if trimmed.lowercased().hasPrefix("host ") {
            if let h = currentHost, let key = currentIdentityFile {
                if matchesHost(host, pattern: h) {
                    return expandPath(key)
                }
            }

            currentHost = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            currentIdentityFile = nil
        } else if trimmed.lowercased().hasPrefix("identityfile ") {
            currentIdentityFile = String(trimmed.dropFirst(13)).trimmingCharacters(in: .whitespaces)

            if currentHost == "*" {
                wildcardIdentityFile = currentIdentityFile
            }
        }
    }

    if let h = currentHost, let key = currentIdentityFile {
        if matchesHost(host, pattern: h) {
            return expandPath(key)
        }
    }

    if let wildcard = wildcardIdentityFile {
        return expandPath(wildcard)
    }

    return nil
}

/// Check if host matches pattern (supports * wildcard)
private func matchesHost(_ host: String, pattern: String) -> Bool {
    if pattern == "*" {
        return true
    }
    if pattern.contains("*") {
        let regex = pattern.replacingOccurrences(of: ".", with: "\\.").replacingOccurrences(of: "*", with: ".*")
        return host.range(of: "^\(regex)$", options: .regularExpression, range: nil, locale: nil) != nil
    }
    return host.lowercased() == pattern.lowercased()
}

/// Expand ~ in path
private func expandPath(_ path: String) -> String {
    if path.hasPrefix("~/") {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        return homeDir + String(path.dropFirst(1))
    }
    return path
}

/// Extract hostname from SSH URL (e.g., git@github.com:user/repo.git -> github.com)
func extractHostFromURL(_ urlString: String) -> String? {
    if urlString.contains("@") && urlString.contains(":") && !urlString.hasPrefix("https://") {
        if let atIndex = urlString.firstIndex(of: "@"),
           let colonIndex = urlString.firstIndex(of: ":") {
            let start = urlString.index(after: atIndex)
            if start < colonIndex {
                return String(urlString[start..<colonIndex])
            }
        }
    }
    if let url = URL(string: urlString) {
        return url.host
    }
    return nil
}

/// SSH credential callback for libgit2 - reads SSH config for the correct key
let sshCredentialCallback: git_credential_acquire_cb = { (cred, url, username_from_url, allowed_types, payload) -> Int32 in
    if allowed_types & UInt32(GIT_CREDENTIAL_SSH_KEY.rawValue) != 0 {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let sshDir = "\(homeDir)/.ssh"

        var keysToTry: [String] = []

        if let urlStr = url.map({ String(cString: $0) }),
           let host = extractHostFromURL(urlStr),
           let configKey = findSSHKeyForHost(host) {
            keysToTry.append(configKey)
        }

        keysToTry.append(contentsOf: [
            "\(sshDir)/id_ed25519",
            "\(sshDir)/id_rsa",
            "\(sshDir)/id_ecdsa"
        ])

        var seen = Set<String>()
        keysToTry = keysToTry.filter { seen.insert($0).inserted }

        for privateKey in keysToTry {
            let publicKey = "\(privateKey).pub"

            if FileManager.default.fileExists(atPath: privateKey) {
                let username = username_from_url != nil ? String(cString: username_from_url!) : "git"
                let pubKeyPath: String? = FileManager.default.fileExists(atPath: publicKey) ? publicKey : nil

                let result = git_credential_ssh_key_new(
                    cred,
                    username,
                    pubKeyPath,
                    privateKey,
                    nil
                )
                if result == 0 {
                    return 0
                }
            }
        }

        return git_credential_ssh_key_from_agent(cred, username_from_url)
    }

    if allowed_types & UInt32(GIT_CREDENTIAL_DEFAULT.rawValue) != 0 {
        return git_credential_default_new(cred)
    }

    if allowed_types & UInt32(GIT_CREDENTIAL_USERPASS_PLAINTEXT.rawValue) != 0 {
        return Int32(GIT_PASSTHROUGH.rawValue)
    }

    return Int32(GIT_PASSTHROUGH.rawValue)
}
