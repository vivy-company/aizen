//
//  GhosttyThemeParser.swift
//  aizen
//
//  Parser for Ghostty theme files to convert them to EditorTheme
//

import Foundation
import AppKit
import CodeEditSourceEditor

typealias Attribute = EditorTheme.Attribute

struct GhosttyThemeParser {
    struct ParsedTheme {
        var background: NSColor?
        var foreground: NSColor?
        var cursorColor: NSColor?
        var selectionBackground: NSColor?
        var palette: [Int: NSColor] = [:]

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

    static func parse(contentsOf path: String) -> EditorTheme? {
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

        return theme.toEditorTheme()
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
}
