//
//  AppSurfaceTheme.swift
//  aizen
//

import AppKit
import SwiftUI

enum AppSurfaceTheme {
    static func effectiveThemeName(
        colorScheme: ColorScheme? = nil,
        defaults: UserDefaults = .standard
    ) -> String {
        let darkTheme = defaults.string(forKey: "terminalThemeName") ?? "Aizen Dark"
        guard defaults.bool(forKey: "usePerAppearanceTheme") else {
            return darkTheme
        }

        let lightTheme = defaults.string(forKey: "terminalThemeNameLight") ?? "Aizen Light"

        if let colorScheme {
            return colorScheme == .dark ? darkTheme : lightTheme
        }

        let bestMatch = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
        return bestMatch == .darkAqua ? darkTheme : lightTheme
    }

    static func backgroundNSColor(
        colorScheme: ColorScheme? = nil,
        defaults: UserDefaults = .standard
    ) -> NSColor {
        GhosttyThemeParser.loadBackgroundColor(named: effectiveThemeName(colorScheme: colorScheme, defaults: defaults))
    }

    static func backgroundColor(
        colorScheme: ColorScheme? = nil,
        defaults: UserDefaults = .standard
    ) -> Color {
        Color(nsColor: backgroundNSColor(colorScheme: colorScheme, defaults: defaults))
    }
}

struct WindowBackgroundSync: NSViewRepresentable {
    let color: NSColor

    func makeNSView(context: Context) -> WindowBackgroundSyncView {
        let view = WindowBackgroundSyncView()
        view.color = color
        return view
    }

    func updateNSView(_ nsView: WindowBackgroundSyncView, context: Context) {
        nsView.color = color
        nsView.applyBackground()
    }
}

final class WindowBackgroundSyncView: NSView {
    var color: NSColor = .clear

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyBackground()
    }

    func applyBackground() {
        window?.backgroundColor = color
    }
}
