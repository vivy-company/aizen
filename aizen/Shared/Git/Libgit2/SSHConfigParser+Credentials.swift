import Foundation
import Clibgit2

/// Payload for libgit2 SSH credential callback to preserve host alias for key selection
nonisolated struct SSHCredentialPayload {
    let keyHost: UnsafeMutablePointer<CChar>?
}

/// SSH credential callback for libgit2 - reads SSH config for the correct key
nonisolated let sshCredentialCallback: git_credential_acquire_cb = { (cred, url, username_from_url, allowed_types, payload) -> Int32 in
    if allowed_types & UInt32(GIT_CREDENTIAL_SSH_KEY.rawValue) != 0 {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let sshDir = "\(homeDir)/.ssh"

        var keysToTry: [String] = []

        let hostForKeySelection: String? = {
            guard let payload else { return nil }
            let p = payload.assumingMemoryBound(to: SSHCredentialPayload.self).pointee
            guard let keyHost = p.keyHost else { return nil }
            return String(cString: keyHost)
        }()

        if let urlStr = url.map({ String(cString: $0) }),
           let host = hostForKeySelection ?? extractHostFromURL(urlStr) {
            if let resolved = resolveSSHConfig(forHost: host), !resolved.identityFiles.isEmpty {
                keysToTry.append(contentsOf: resolved.identityFiles)
            }
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
