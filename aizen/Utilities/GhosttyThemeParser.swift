//
//  GhosttyThemeParser.swift
//  aizen
//
//  Parser for Ghostty theme files to convert them to EditorTheme
//

import Foundation
import AppKit
import CodeEditSourceEditor

// MARK: - NSColor Hex Extension

extension NSColor {
    convenience init(hex: String, alpha: Double = 1.0) {
        let hex = hex.trimmingCharacters(in: .alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        self.init(hex: Int(int), alpha: alpha)
    }

    convenience init(hex: Int, alpha: Double = 1.0) {
        let red = (hex >> 16) & 0xFF
        let green = (hex >> 8) & 0xFF
        let blue = hex & 0xFF
        self.init(srgbRed: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255, alpha: alpha)
    }

    var hexInt: Int {
        guard let components = cgColor.components, components.count >= 3 else { return 0 }
        let red = lround((Double(components[0]) * 255.0)) << 16
        let green = lround((Double(components[1]) * 255.0)) << 8
        let blue = lround((Double(components[2]) * 255.0))
        return red | green | blue
    }

    var hexString: String {
        String(format: "%06x", hexInt)
    }
}

typealias Attribute = EditorTheme.Attribute

nonisolated struct GitStatusColors {
    let modified: NSColor   // yellow - modified/mixed files
    let added: NSColor      // green - staged/added files
    let untracked: NSColor  // blue - untracked files
    let deleted: NSColor    // red - deleted/conflicted files
    let renamed: NSColor    // magenta - renamed files

    static let `default` = GitStatusColors(
        modified: NSColor(hex: "F9E2AF"),
        added: NSColor(hex: "A6E3A1"),
        untracked: NSColor(hex: "89B4FA"),
        deleted: NSColor(hex: "F38BA8"),
        renamed: NSColor(hex: "F5C2E7")
    )
}

nonisolated struct GhosttyThemeParser {
    struct ParsedTheme {
        var background: NSColor?
        var foreground: NSColor?
        var cursorColor: NSColor?
        var selectionBackground: NSColor?
        var palette: [Int: NSColor] = [:]

        func toGitStatusColors() -> GitStatusColors {
            GitStatusColors(
                modified: palette[3] ?? NSColor(hex: "F9E2AF"),   // yellow
                added: palette[2] ?? NSColor(hex: "A6E3A1"),      // green
                untracked: palette[4] ?? NSColor(hex: "89B4FA"),  // blue
                deleted: palette[1] ?? NSColor(hex: "F38BA8"),    // red
                renamed: palette[5] ?? NSColor(hex: "F5C2E7")     // magenta
            )
        }

        func toEditorTheme() -> EditorTheme {
            let bg = background ?? NSColor(hex: "1E1E2E")
            let fg = foreground ?? NSColor(hex: "CDD6F4")
            let selection = selectionBackground ?? NSColor(hex: "585B70")

            // Map ANSI colors to syntax highlighting
            // ANSI colors: 0=black, 1=red, 2=green, 3=yellow, 4=blue, 5=magenta, 6=cyan, 7=white
            let red = palette[1] ?? NSColor(hex: "F38BA8")
            let green = palette[2] ?? NSColor(hex: "A6E3A1")
            let yellow = palette[3] ?? NSColor(hex: "F9E2AF")
            let blue = palette[4] ?? NSColor(hex: "89B4FA")
            let magenta = palette[5] ?? NSColor(hex: "F5C2E7")
            let cyan = palette[6] ?? NSColor(hex: "94E2D5")
            let brightBlack = palette[8] ?? NSColor(hex: "585B70")

            // Create line highlight color (slightly lighter/darker than background)
            var lineHighlightColor = bg
            if let components = bg.usingColorSpace(.deviceRGB) {
                let brightness = components.brightnessComponent
                if brightness < 0.5 {
                    // Dark theme - make slightly lighter
                    lineHighlightColor = NSColor(
                        red: min(components.redComponent + 0.05, 1.0),
                        green: min(components.greenComponent + 0.05, 1.0),
                        blue: min(components.blueComponent + 0.05, 1.0),
                        alpha: 1.0
                    )
                } else {
                    // Light theme - make slightly darker
                    lineHighlightColor = NSColor(
                        red: max(components.redComponent - 0.05, 0.0),
                        green: max(components.greenComponent - 0.05, 0.0),
                        blue: max(components.blueComponent - 0.05, 0.0),
                        alpha: 1.0
                    )
                }
            }

            return EditorTheme(
                text: Attribute(color: fg),
                insertionPoint: cursorColor ?? fg,
                invisibles: Attribute(color: brightBlack),
                background: bg,
                lineHighlight: lineHighlightColor,
                selection: selection,
                keywords: Attribute(color: magenta),
                commands: Attribute(color: blue),
                types: Attribute(color: yellow),
                attributes: Attribute(color: green),
                variables: Attribute(color: cyan),
                values: Attribute(color: magenta),
                numbers: Attribute(color: yellow),
                strings: Attribute(color: green),
                characters: Attribute(color: green),
                comments: Attribute(color: brightBlack)
            )
        }
    }

    private static func parseRaw(contentsOf path: String) -> ParsedTheme? {
        guard let content = try? String(contentsOfFile: path) else {
            return nil
        }

        var theme = ParsedTheme()

        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }

            let parts = trimmed.components(separatedBy: "=").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }

            let key = parts[0]
            let value = parts[1]

            switch key {
            case "background":
                theme.background = NSColor(hex: value)
            case "foreground":
                theme.foreground = NSColor(hex: value)
            case "cursor-color":
                theme.cursorColor = NSColor(hex: value)
            case "selection-background":
                theme.selectionBackground = NSColor(hex: value)
            case let k where k.hasPrefix("palette"):
                // palette = 0=#45475a
                let parts = value.split(separator: "=")
                if parts.count == 2,
                   let paletteNum = Int(parts[0].trimmingCharacters(in: .whitespaces)) {
                    let color = NSColor(hex: String(parts[1]))
                    theme.palette[paletteNum] = color
                }
            default:
                break
            }
        }

        return theme
    }

    static func parse(contentsOf path: String) -> EditorTheme? {
        parseRaw(contentsOf: path)?.toEditorTheme()
    }

    static func availableThemes() -> [String] {
        guard let resourcePath = Bundle.main.resourcePath else { return [] }
        let themesPath = (resourcePath as NSString).appendingPathComponent("ghostty/themes")

        guard let themeFiles = try? FileManager.default.contentsOfDirectory(atPath: themesPath) else {
            return []
        }

        return themeFiles.filter { file in
            let path = (themesPath as NSString).appendingPathComponent(file)
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
            return !isDir.boolValue && !file.hasPrefix(".")
        }.sorted()
    }

    static func loadTheme(named name: String) -> EditorTheme? {
        guard let resourcePath = Bundle.main.resourcePath else { return nil }
        let themePath = ((resourcePath as NSString)
            .appendingPathComponent("ghostty/themes") as NSString)
            .appendingPathComponent(name)

        return parse(contentsOf: themePath)
    }

    static func loadGitStatusColors(named name: String) -> GitStatusColors {
        guard let resourcePath = Bundle.main.resourcePath else { return .default }
        let themePath = ((resourcePath as NSString)
            .appendingPathComponent("ghostty/themes") as NSString)
            .appendingPathComponent(name)

        return parseRaw(contentsOf: themePath)?.toGitStatusColors() ?? .default
    }

    /// Returns the ANSI palette colors (0-15) for a theme
    static func loadANSIPalette(named name: String) -> [Int: NSColor]? {
        guard let resourcePath = Bundle.main.resourcePath else { return nil }
        let themePath = ((resourcePath as NSString)
            .appendingPathComponent("ghostty/themes") as NSString)
            .appendingPathComponent(name)

        return parseRaw(contentsOf: themePath)?.palette
    }

    /// Returns tmux mode-style string for selection highlighting
    /// Format: "fg=#RRGGBB,bg=#RRGGBB"
    static func loadTmuxModeStyle(named name: String) -> String {
        guard let resourcePath = Bundle.main.resourcePath else {
            return "fg=#cdd6f4,bg=#45475a"
        }
        let themePath = ((resourcePath as NSString)
            .appendingPathComponent("ghostty/themes") as NSString)
            .appendingPathComponent(name)

        guard let theme = parseRaw(contentsOf: themePath) else {
            return "fg=#cdd6f4,bg=#45475a"
        }

        let fg = theme.foreground?.hexString ?? "cdd6f4"
        let bg = theme.selectionBackground?.hexString ?? "45475a"
        return "fg=#\(fg),bg=#\(bg)"
    }
}
