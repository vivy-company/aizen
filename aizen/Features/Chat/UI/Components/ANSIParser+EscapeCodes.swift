//
//  ANSIParser+EscapeCodes.swift
//  aizen
//

import Foundation

nonisolated extension ANSIParser {
    static func parseEscapeCodes(_ codes: String, style: inout ANSITextStyle) {
        let parts = codes.split(separator: ";").compactMap { Int($0) }

        if parts.isEmpty {
            style.reset()
            return
        }

        var index = 0
        while index < parts.count {
            let code = parts[index]

            switch code {
            case 0: style.reset()
            case 1: style.bold = true
            case 2: style.dim = true
            case 3: style.italic = true
            case 4: style.underline = true
            case 9: style.strikethrough = true
            case 21: style.bold = false
            case 22:
                style.bold = false
                style.dim = false
            case 23: style.italic = false
            case 24: style.underline = false
            case 29: style.strikethrough = false

            case 30: style.foreground = .black
            case 31: style.foreground = .red
            case 32: style.foreground = .green
            case 33: style.foreground = .yellow
            case 34: style.foreground = .blue
            case 35: style.foreground = .magenta
            case 36: style.foreground = .cyan
            case 37: style.foreground = .white
            case 39: style.foreground = .default

            case 40: style.background = .black
            case 41: style.background = .red
            case 42: style.background = .green
            case 43: style.background = .yellow
            case 44: style.background = .blue
            case 45: style.background = .magenta
            case 46: style.background = .cyan
            case 47: style.background = .white
            case 49: style.background = .default

            case 90: style.foreground = .brightBlack
            case 91: style.foreground = .brightRed
            case 92: style.foreground = .brightGreen
            case 93: style.foreground = .brightYellow
            case 94: style.foreground = .brightBlue
            case 95: style.foreground = .brightMagenta
            case 96: style.foreground = .brightCyan
            case 97: style.foreground = .brightWhite

            case 100: style.background = .brightBlack
            case 101: style.background = .brightRed
            case 102: style.background = .brightGreen
            case 103: style.background = .brightYellow
            case 104: style.background = .brightBlue
            case 105: style.background = .brightMagenta
            case 106: style.background = .brightCyan
            case 107: style.background = .brightWhite

            case 38:
                if applyExtendedColor(parts, at: &index, target: \.foreground, style: &style) == false {
                    break
                }

            case 48:
                if applyExtendedColor(parts, at: &index, target: \.background, style: &style) == false {
                    break
                }

            default:
                break
            }

            index += 1
        }
    }

    private static func applyExtendedColor(
        _ parts: [Int],
        at index: inout Int,
        target: WritableKeyPath<ANSITextStyle, ANSIColor>,
        style: inout ANSITextStyle
    ) -> Bool {
        guard index + 1 < parts.count else { return false }

        if parts[index + 1] == 5, index + 2 < parts.count {
            style[keyPath: target] = .palette(UInt8(parts[index + 2]))
            index += 2
            return true
        }

        if parts[index + 1] == 2, index + 4 < parts.count {
            style[keyPath: target] = .rgb(
                UInt8(parts[index + 2]),
                UInt8(parts[index + 3]),
                UInt8(parts[index + 4])
            )
            index += 4
            return true
        }

        return false
    }
}
