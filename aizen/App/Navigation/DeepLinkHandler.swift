//
//  DeepLinkHandler.swift
//  aizen
//
//  Routes the external aizen:// boundary into the active Reignition client.
//

import AppKit
import Foundation

@MainActor
final class DeepLinkHandler {
    static let shared = DeepLinkHandler()
    private var pendingLocalPaths: [URL] = []

    private init() {}

    func handle(_ url: URL) {
        guard url.scheme == "aizen" else { return }

        let host = url.host ?? ""
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []

        let token = queryItems.first(where: { $0.name == "token" })?.value
        let activateFlag = queryItems.first(where: { $0.name == "activate" })?.value?.lowercased()
        let openPath = queryItems.first(where: { $0.name == "path" })?.value
        let autoActivate = host == "activate" || path == "activate" || activateFlag == "1" || activateFlag == "true"

        if token != nil || autoActivate {
            LicenseStateStore.shared.setPendingDeepLink(token: token, autoActivate: autoActivate)
        }

        NSApp.activate(ignoringOtherApps: true)
        dispatchDeepLink(host: host, path: path, token: token, autoActivate: autoActivate, openPath: openPath)
    }

    func takePendingLocalPaths() -> [URL] {
        defer { pendingLocalPaths.removeAll() }
        return pendingLocalPaths
    }

    private func dispatchDeepLink(host: String, path: String, token: String?, autoActivate: Bool, openPath: String?) {
        if token != nil || autoActivate {
            NotificationCenter.default.post(name: .openLicenseDeepLink, object: nil)
            return
        }

        if host == "open" || path == "open" {
            if let openPath, let url = localDirectoryURL(for: openPath) {
                pendingLocalPaths.append(url)
                NotificationCenter.default.post(name: .openReignitionPath, object: url)
            }
            return
        }

        let shouldOpenSettings = host == "settings" || path == "settings"
        guard shouldOpenSettings else { return }

        ReignitionHostSettingsWindowController.shared.show()
    }

    private func localDirectoryURL(for path: String) -> URL? {
        let expanded = (path as NSString).expandingTildeInPath
        let candidate: URL
        if expanded.hasPrefix("/") {
            candidate = URL(fileURLWithPath: expanded)
        } else {
            candidate = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(expanded)
        }
        let normalized = candidate.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: normalized.path, isDirectory: &isDirectory) else { return nil }
        return isDirectory.boolValue ? normalized : normalized.deletingLastPathComponent()
    }
}
