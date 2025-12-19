//
//  DeepLinkHandler.swift
//  aizen
//
//  Handles app deep links without spawning extra windows
//

import AppKit
import Foundation

@MainActor
final class DeepLinkHandler {
    static let shared = DeepLinkHandler()

    private init() {}

    func handle(_ url: URL) {
        guard url.scheme == "aizen" else { return }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let host = url.host ?? ""
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let queryItems = components?.queryItems ?? []

        let token = queryItems.first(where: { $0.name == "token" })?.value
        let activateFlag = queryItems.first(where: { $0.name == "activate" })?.value?.lowercased()
        let autoActivate = host == "activate" || path == "activate" || activateFlag == "1" || activateFlag == "true"

        if token != nil || autoActivate {
            LicenseManager.shared.setPendingDeepLink(token: token, autoActivate: autoActivate)
        }

        NSApp.activate(ignoringOtherApps: true)

        collapseDuplicateMainWindows { [weak self] in
            self?.dispatchDeepLink(host: host, path: path, token: token, autoActivate: autoActivate)
        }
    }

    private func dispatchDeepLink(host: String, path: String, token: String?, autoActivate: Bool) {
        if token != nil || autoActivate {
            NotificationCenter.default.post(name: .openLicenseDeepLink, object: nil)
            return
        }

        let shouldOpenSettings = host == "settings" || path == "settings"
        guard shouldOpenSettings else { return }

        SettingsWindowManager.shared.show()
        NotificationCenter.default.post(name: .openSettingsPro, object: nil)
    }

    private func collapseDuplicateMainWindows(completion: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let windows = NSApp.windows.filter { window in
                window.identifier != NSUserInterfaceItemIdentifier("GitPanelWindow") &&
                window.isVisible &&
                !window.isMiniaturized
            }

            if windows.count > 1 {
                let keepWindow = NSApp.mainWindow ?? windows.first
                for window in windows {
                    if window != keepWindow {
                        window.close()
                    }
                }
                keepWindow?.makeKeyAndOrderFront(nil)
            }

            completion()
        }
    }
}
