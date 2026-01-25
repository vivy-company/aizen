//
//  CodeBlockColors.swift
//  aizen
//
//  Shared color tokens for code/diagram blocks using Ghostty theme
//

import SwiftUI

enum CodeBlockColors {
    @AppStorage("terminalThemeName") private static var themeName = "Aizen Dark"
    
    static func headerBackground() -> Color {
        let bg = GhosttyThemeParser.loadBackgroundColor(named: themeName)
        let isLight = bg.luminance > 0.5
        return Color(nsColor: bg.darken(by: isLight ? 0.05 : -0.08))
    }

    static func contentBackground() -> Color {
        Color(nsColor: GhosttyThemeParser.loadBackgroundColor(named: themeName))
    }
}
