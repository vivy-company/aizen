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
        AppearanceSettings.effectiveThemeName(colorScheme: colorScheme, defaults: defaults)
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
