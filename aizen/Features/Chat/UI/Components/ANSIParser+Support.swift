//
//  ANSIParser+Support.swift
//  aizen
//
//  Created by OpenAI Codex on 07.04.26.
//

import AppKit
import SwiftUI

// MARK: - ANSI Color Provider

/// Provides ANSI colors from the user's selected theme
nonisolated struct ANSIColorProvider {
    static let shared = ANSIColorProvider()

    private var cachedThemeName: String?
    private var cachedPalette: [Int: NSColor]?

    /// Get the current theme's palette, with caching
    mutating func getPalette() -> [Int: NSColor] {
        let themeName = UserDefaults.standard.string(forKey: "terminalThemeName") ?? "Aizen Dark"

        if themeName == cachedThemeName, let palette = cachedPalette {
            return palette
        }

        if let palette = GhosttyThemeParser.loadANSIPalette(named: themeName), !palette.isEmpty {
            cachedThemeName = themeName
            cachedPalette = palette
            return palette
        }

        return Self.aizenDarkPalette
    }

    static let aizenDarkPalette: [Int: NSColor] = [
        0: NSColor(srgbRed: 0.102, green: 0.102, blue: 0.102, alpha: 1),
        1: NSColor(srgbRed: 0.941, green: 0.533, blue: 0.596, alpha: 1),
        2: NSColor(srgbRed: 0.643, green: 0.878, blue: 0.612, alpha: 1),
        3: NSColor(srgbRed: 0.961, green: 0.871, blue: 0.643, alpha: 1),
        4: NSColor(srgbRed: 0.518, green: 0.706, blue: 0.973, alpha: 1),
        5: NSColor(srgbRed: 0.784, green: 0.635, blue: 0.957, alpha: 1),
        6: NSColor(srgbRed: 0.565, green: 0.863, blue: 0.816, alpha: 1),
        7: NSColor(srgbRed: 0.816, green: 0.839, blue: 0.941, alpha: 1),
        8: NSColor(srgbRed: 0.267, green: 0.267, blue: 0.267, alpha: 1),
        9: NSColor(srgbRed: 0.941, green: 0.533, blue: 0.596, alpha: 1),
        10: NSColor(srgbRed: 0.643, green: 0.878, blue: 0.612, alpha: 1),
        11: NSColor(srgbRed: 0.961, green: 0.871, blue: 0.643, alpha: 1),
        12: NSColor(srgbRed: 0.518, green: 0.706, blue: 0.973, alpha: 1),
        13: NSColor(srgbRed: 0.784, green: 0.635, blue: 0.957, alpha: 1),
        14: NSColor(srgbRed: 0.565, green: 0.863, blue: 0.816, alpha: 1),
        15: NSColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 1),
    ]

    func color(for index: Int) -> Color {
        var provider = self
        let palette = provider.getPalette()
        if let nsColor = palette[index] {
            return Color(nsColor)
        }
        if let nsColor = Self.aizenDarkPalette[index] {
            return Color(nsColor)
        }
        return .primary
    }
}

// MARK: - ANSI Color Definitions

nonisolated enum ANSIColor {
    case `default`
    case black, red, green, yellow, blue, magenta, cyan, white
    case brightBlack, brightRed, brightGreen, brightYellow
    case brightBlue, brightMagenta, brightCyan, brightWhite
    case rgb(UInt8, UInt8, UInt8)
    case palette(UInt8)

    var color: Color {
        let provider = ANSIColorProvider.shared
        switch self {
        case .default: return .primary
        case .black: return provider.color(for: 0)
        case .red: return provider.color(for: 1)
        case .green: return provider.color(for: 2)
        case .yellow: return provider.color(for: 3)
        case .blue: return provider.color(for: 4)
        case .magenta: return provider.color(for: 5)
        case .cyan: return provider.color(for: 6)
        case .white: return provider.color(for: 7)
        case .brightBlack: return provider.color(for: 8)
        case .brightRed: return provider.color(for: 9)
        case .brightGreen: return provider.color(for: 10)
        case .brightYellow: return provider.color(for: 11)
        case .brightBlue: return provider.color(for: 12)
        case .brightMagenta: return provider.color(for: 13)
        case .brightCyan: return provider.color(for: 14)
        case .brightWhite: return provider.color(for: 15)
        case .rgb(let r, let g, let b):
            return Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
        case .palette(let index):
            return paletteColor(index)
        }
    }

    private func paletteColor(_ index: UInt8) -> Color {
        if index < 16 {
            return ANSIColorProvider.shared.color(for: Int(index))
        }
        if index < 232 {
            let adjusted = Int(index) - 16
            let r = adjusted / 36
            let g = (adjusted % 36) / 6
            let b = adjusted % 6
            return Color(
                red: r == 0 ? 0 : Double(r * 40 + 55) / 255,
                green: g == 0 ? 0 : Double(g * 40 + 55) / 255,
                blue: b == 0 ? 0 : Double(b * 40 + 55) / 255
            )
        }
        let gray = Double((Int(index) - 232) * 10 + 8) / 255
        return Color(white: gray)
    }
}

// MARK: - Text Style

nonisolated struct ANSITextStyle: Sendable {
    var foreground: ANSIColor = .default
    var background: ANSIColor = .default
    var bold: Bool = false
    var italic: Bool = false
    var underline: Bool = false
    var dim: Bool = false
    var strikethrough: Bool = false

    mutating func reset() {
        foreground = .default
        background = .default
        bold = false
        italic = false
        underline = false
        dim = false
        strikethrough = false
    }
}
