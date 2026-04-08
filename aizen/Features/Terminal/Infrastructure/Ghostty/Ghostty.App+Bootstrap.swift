//
//  Ghostty.App+Bootstrap.swift
//  aizen
//

import AppKit
import Foundation
import GhosttyKit
import OSLog

extension Ghostty.App {
    func makeRuntimeConfig() -> ghostty_runtime_config_s {
        ghostty_runtime_config_s(
            userdata: Unmanaged.passUnretained(self).toOpaque(),
            supports_selection_clipboard: true,
            wakeup_cb: { userdata in Ghostty.App.wakeup(userdata) },
            action_cb: { app, target, action in Ghostty.App.handleAction(app!, target: target, action: action) },
            read_clipboard_cb: { userdata, loc, state in Ghostty.App.readClipboard(userdata, location: loc, state: state) },
            confirm_read_clipboard_cb: { userdata, str, state, request in
                Ghostty.App.confirmReadClipboard(userdata, string: str, state: state, request: request)
            },
            write_clipboard_cb: { userdata, loc, content, count, confirm in
                Ghostty.App.writeClipboard(userdata, location: loc, contents: content, count: count, confirm: confirm)
            },
            close_surface_cb: { userdata, processAlive in
                Ghostty.App.closeSurface(userdata, processAlive: processAlive)
            }
        )
    }

    func makeInitialConfig() -> ghostty_config_t? {
        guard let config = ghostty_config_new() else {
            Ghostty.logger.critical("ghostty_config_new failed")
            readiness = .error
            return nil
        }

        loadConfigIntoGhostty(config)
        ghostty_config_finalize(config)
        return config
    }

    func installObservers() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(systemAppearanceDidChange),
            name: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil
        )

        appearanceSettingObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkAppearanceSettingChange()
            }
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardSelectionDidChange),
            name: NSTextInputContext.keyboardSelectionDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidResignActive),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
    }
}
