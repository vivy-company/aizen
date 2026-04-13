//
//  AppSurfaceTheme.swift
//  aizen
//

import AppKit
import SwiftUI

enum AppSurfaceTheme {
    private static let minimumPrimaryContrastRatio = 4.5
    private static let minimumSecondaryContrastRatio = 3.0

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
        let isDarkAppearance = self.isDarkAppearance(colorScheme: colorScheme)
        let themeBackground = GhosttyThemeParser.loadBackgroundColor(
            named: effectiveThemeName(colorScheme: colorScheme, defaults: defaults)
        )
        return resolvedSurfaceBackground(themeBackground: themeBackground, isDarkAppearance: isDarkAppearance)
    }

    static func backgroundColor(
        colorScheme: ColorScheme? = nil,
        defaults: UserDefaults = .standard
    ) -> Color {
        Color(nsColor: backgroundNSColor(colorScheme: colorScheme, defaults: defaults))
    }

    static func resolvedSurfaceBackground(
        themeBackground: NSColor,
        isDarkAppearance: Bool
    ) -> NSColor {
        let appearance = NSAppearance(named: isDarkAppearance ? .darkAqua : .aqua)!
        let primaryText = resolvedSystemColor(NSColor.labelColor, appearance: appearance)
        let secondaryText = resolvedSystemColor(NSColor.secondaryLabelColor, appearance: appearance)

        let primaryContrast = contrastRatio(between: themeBackground, and: primaryText)
        let secondaryContrast = contrastRatio(between: themeBackground, and: secondaryText)

        guard primaryContrast >= minimumPrimaryContrastRatio,
              secondaryContrast >= minimumSecondaryContrastRatio else {
            return resolvedSystemColor(NSColor.windowBackgroundColor, appearance: appearance)
        }

        return themeBackground
    }

    static func resolvedSystemColor(_ color: NSColor, appearance: NSAppearance) -> NSColor {
        var resolved = color
        appearance.performAsCurrentDrawingAppearance {
            resolved = color.usingColorSpace(.sRGB) ?? color
        }
        return resolved
    }

    private static func isDarkAppearance(colorScheme: ColorScheme?) -> Bool {
        if let colorScheme {
            return colorScheme == .dark
        }

        let bestMatch = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
        return bestMatch == .darkAqua
    }

    private static func contrastRatio(between lhs: NSColor, and rhs: NSColor) -> Double {
        let lhsLuminance = relativeLuminance(of: lhs)
        let rhsLuminance = relativeLuminance(of: rhs)
        let lighter = max(lhsLuminance, rhsLuminance)
        let darker = min(lhsLuminance, rhsLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private static func relativeLuminance(of color: NSColor) -> Double {
        guard let rgb = color.usingColorSpace(.sRGB) else { return 0 }

        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        rgb.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        return (0.2126 * linearized(red))
            + (0.7152 * linearized(green))
            + (0.0722 * linearized(blue))
    }

    private static func linearized(_ component: CGFloat) -> Double {
        let value = Double(component)
        if value <= 0.03928 {
            return value / 12.92
        }
        return pow((value + 0.055) / 1.055, 2.4)
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
