import AppKit
import Foundation
import GhosttyKit

extension Ghostty.App {
    @objc func systemAppearanceDidChange(_ notification: Foundation.Notification) {
        handleAppearanceChange()
    }

    @objc func keyboardSelectionDidChange(_ notification: Foundation.Notification) {
        guard let app = self.app else { return }
        ghostty_app_keyboard_changed(app)
    }

    @objc func applicationDidBecomeActive(_ notification: Foundation.Notification) {
        guard let app = self.app else { return }
        ghostty_app_set_focus(app, true)
    }

    @objc func applicationDidResignActive(_ notification: Foundation.Notification) {
        guard let app = self.app else { return }
        ghostty_app_set_focus(app, false)
    }

    func handleAppearanceChange() {
        guard usePerAppearanceTheme else { return }

        let currentAppearance = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
        guard currentAppearance != lastKnownAppearance else { return }

        lastKnownAppearance = currentAppearance
        reloadIfThemeChanged()
    }

    func checkAppearanceSettingChange() {
        guard usePerAppearanceTheme else { return }
        reloadIfThemeChanged()
    }

    func reloadIfThemeChanged() {
        let newTheme = effectiveThemeName
        guard newTheme != lastKnownTheme else { return }

        lastKnownTheme = newTheme
        reloadConfig()
    }
}
