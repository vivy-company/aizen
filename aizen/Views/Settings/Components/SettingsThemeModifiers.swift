//
//  SettingsThemeModifiers.swift
//  aizen
//

import SwiftUI

private struct SettingsSurfaceModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    private var surfaceColor: Color {
        AppSurfaceTheme.backgroundColor(colorScheme: colorScheme)
    }

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(surfaceColor)
    }
}

private struct SettingsSheetChromeModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    private var surfaceColor: Color {
        AppSurfaceTheme.backgroundColor(colorScheme: colorScheme)
    }

    private var surfaceNSColor: NSColor {
        AppSurfaceTheme.backgroundNSColor(colorScheme: colorScheme)
    }

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(surfaceColor)
            .background(WindowBackgroundSync(color: surfaceNSColor))
    }
}

extension View {
    func settingsSurface() -> some View {
        modifier(SettingsSurfaceModifier())
    }

    func settingsSheetChrome() -> some View {
        modifier(SettingsSheetChromeModifier())
    }

    @ViewBuilder
    func settingsNativeToolbarGlass() -> some View {
        if #available(macOS 15.0, *) {
            self.toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        } else {
            self
        }
    }
}
