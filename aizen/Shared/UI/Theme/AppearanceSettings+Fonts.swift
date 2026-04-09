//
//  AppearanceSettings+Fonts.swift
//  aizen
//

import AppKit
import SwiftUI

extension AppearanceSettings {
    static func monospaceFonts() -> [String] {
        NSFontManager.shared.availableFontFamilies
            .filter { familyName in
                guard let font = NSFont(name: familyName, size: 12) else { return false }
                return font.isFixedPitch
            }
            .sorted()
    }

    static func readableFonts() -> [String] {
        var fonts = NSFontManager.shared.availableFontFamilies.sorted()
        fonts.insert(systemFontFamily, at: 0)
        return fonts
    }

    static func resolvedNSFont(
        family: String,
        size: Double,
        monospacedFallback: Bool = false,
        requireFixedPitch: Bool = false
    ) -> NSFont {
        if family == systemFontFamily {
            return monospacedFallback
                ? .monospacedSystemFont(ofSize: size, weight: .regular)
                : .systemFont(ofSize: size)
        }

        if let custom = NSFont(name: family, size: size), !requireFixedPitch || custom.isFixedPitch {
            return custom
        }

        if monospacedFallback,
           family != defaultCodeFontFamily,
           let defaultCodeFont = NSFont(name: defaultCodeFontFamily, size: size),
           !requireFixedPitch || defaultCodeFont.isFixedPitch {
            return defaultCodeFont
        }

        return monospacedFallback
            ? .monospacedSystemFont(ofSize: size, weight: .regular)
            : .systemFont(ofSize: size)
    }

    static func resolvedFont(
        family: String,
        size: Double,
        weight: Font.Weight = .regular,
        monospacedFallback: Bool = false
    ) -> Font {
        if family == systemFontFamily {
            return monospacedFallback
                ? .system(size: size, weight: weight, design: .monospaced)
                : .system(size: size, weight: weight)
        }

        return .custom(family, size: size).weight(weight)
    }
}
