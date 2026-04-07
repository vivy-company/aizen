import Foundation
import Clibgit2

nonisolated extension Libgit2Repository {

    private struct SSHRemoteURLParts: Sendable {
        let isSSH: Bool
        let isSCP: Bool
        let user: String?
        let host: String
        let path: String
        let port: Int?
    }

    private func parseSSHRemoteURL(_ url: String) -> SSHRemoteURLParts? {
        if url.hasPrefix("ssh://"), let u = URL(string: url), let host = u.host {
            let user = u.user
            let port = u.port
            let path = u.path
            return SSHRemoteURLParts(isSSH: true, isSCP: false, user: user, host: host, path: path, port: port)
        }

        if !url.contains("://"), let colonIndex = url.firstIndex(of: ":") {
            let before = String(url[..<colonIndex])
            let after = String(url[url.index(after: colonIndex)...])
            guard !before.contains("/"), !after.isEmpty else { return nil }

            let user: String?
            let host: String
            if let at = before.firstIndex(of: "@") {
                user = String(before[..<at])
                host = String(before[before.index(after: at)...])
            } else {
                user = nil
                host = before
            }

            guard !host.isEmpty else { return nil }
            return SSHRemoteURLParts(isSSH: true, isSCP: true, user: user, host: host, path: after, port: nil)
        }

        return nil
    }

    private func buildResolvedSSHURL(from parts: SSHRemoteURLParts, resolution: SSHConfigResolution?) -> String? {
        guard parts.isSSH else { return nil }

        let connectHost = resolution?.hostName?.isEmpty == false ? resolution!.hostName! : parts.host
        let user = parts.user ?? resolution?.user
        let port = resolution?.port ?? parts.port

        if parts.isSCP, (port == nil || port == 22) {
            let userPrefix = (user?.isEmpty == false) ? "\(user!)@" : ""
            return "\(userPrefix)\(connectHost):\(parts.path)"
        }

        var components = URLComponents()
        components.scheme = "ssh"
        components.host = connectHost
        components.user = user
        components.port = port

        let path = parts.isSCP ? "/\(parts.path)" : (parts.path.hasPrefix("/") ? parts.path : "/\(parts.path)")
        components.path = path

        return components.url?.absoluteString
    }

    private func prepareSSHCallbacksPayload(originalHost: String) -> UnsafeMutablePointer<SSHCredentialPayload> {
        let payload = UnsafeMutablePointer<SSHCredentialPayload>.allocate(capacity: 1)
        let hostDup = strdup(originalHost)
        payload.initialize(to: SSHCredentialPayload(keyHost: hostDup))
        return payload
    }

    func freeSSHCallbacksPayload(_ payload: UnsafeMutablePointer<SSHCredentialPayload>?) {
        guard let payload else { return }
        if let host = payload.pointee.keyHost {
            free(host)
        }
        payload.deinitialize(count: 1)
        payload.deallocate()
    }

    func configureRemoteInstanceURLIfNeeded(
        remote: OpaquePointer,
        forPush: Bool
    ) -> UnsafeMutablePointer<SSHCredentialPayload>? {
        let rawURLPtr = forPush ? git_remote_pushurl(remote) : git_remote_url(remote)
        guard let rawURLPtr else { return nil }
        let rawURL = String(cString: rawURLPtr)

        guard let parts = parseSSHRemoteURL(rawURL) else { return nil }

        let resolution = resolveSSHConfig(forHost: parts.host)
        let resolvedURL = buildResolvedSSHURL(from: parts, resolution: resolution)

        if let resolvedURL, resolvedURL != rawURL {
            resolvedURL.withCString { cStr in
                if forPush {
                    _ = git_remote_set_instance_pushurl(remote, cStr)
                } else {
                    _ = git_remote_set_instance_url(remote, cStr)
                }
            }
        }

        return prepareSSHCallbacksPayload(originalHost: parts.host)
    }
}
