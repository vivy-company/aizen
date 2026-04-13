import AppKit
import Testing
@testable import Aizen

struct AppSurfaceThemeTests {
    @Test func lightAppearanceFallsBackWhenThemeBackgroundIsTooDark() {
        let darkThemeBackground = NSColor(hex: "1A1A1A")

        let resolved = AppSurfaceTheme.resolvedSurfaceBackground(
            themeBackground: darkThemeBackground,
            isDarkAppearance: false
        )

        let expected = AppSurfaceTheme.resolvedSystemColor(
            NSColor.windowBackgroundColor,
            appearance: NSAppearance(named: .aqua)!
        )
        #expect(colorsMatch(resolved, expected))
    }

    @Test func darkAppearanceFallsBackWhenThemeBackgroundIsTooLight() {
        let lightThemeBackground = NSColor(hex: "F0F2F6")

        let resolved = AppSurfaceTheme.resolvedSurfaceBackground(
            themeBackground: lightThemeBackground,
            isDarkAppearance: true
        )

        let expected = AppSurfaceTheme.resolvedSystemColor(
            NSColor.windowBackgroundColor,
            appearance: NSAppearance(named: .darkAqua)!
        )
        #expect(colorsMatch(resolved, expected))
    }

    @Test func matchingDarkAppearanceKeepsThemeBackground() {
        let darkThemeBackground = NSColor(hex: "1A1A1A")

        let resolved = AppSurfaceTheme.resolvedSurfaceBackground(
            themeBackground: darkThemeBackground,
            isDarkAppearance: true
        )

        #expect(colorsMatch(resolved, darkThemeBackground))
    }

    @Test func matchingLightAppearanceKeepsThemeBackground() {
        let lightThemeBackground = NSColor(hex: "F0F2F6")

        let resolved = AppSurfaceTheme.resolvedSurfaceBackground(
            themeBackground: lightThemeBackground,
            isDarkAppearance: false
        )

        #expect(colorsMatch(resolved, lightThemeBackground))
    }

    private func colorsMatch(
        _ lhs: NSColor,
        _ rhs: NSColor,
        tolerance: CGFloat = 0.002
    ) -> Bool {
        guard let left = lhs.usingColorSpace(.sRGB),
              let right = rhs.usingColorSpace(.sRGB) else {
            return false
        }

        return abs(left.redComponent - right.redComponent) <= tolerance
            && abs(left.greenComponent - right.greenComponent) <= tolerance
            && abs(left.blueComponent - right.blueComponent) <= tolerance
            && abs(left.alphaComponent - right.alphaComponent) <= tolerance
    }
}
