//
//  ANSIParser.swift
//  aizen
//
//  Parses ANSI escape codes and converts to AttributedString for SwiftUI
//

import SwiftUI
import AppKit

// MARK: - ANSI Parser

nonisolated struct ANSIParser {
    /// Parse ANSI-encoded string to AttributedString
    static func parse(_ input: String) -> AttributedString {
        var result = AttributedString()
        var style = ANSITextStyle()
        // Regex to match ANSI escape sequences
        let pattern = "\u{001B}\\[([0-9;]*)m"
        let regex = try? NSRegularExpression(pattern: pattern, options: [])

        var lastEnd = input.startIndex

        let nsString = input as NSString
        let matches = regex?.matches(in: input, options: [], range: NSRange(location: 0, length: nsString.length)) ?? []

        for match in matches {
            // Get text before this escape sequence
            if let swiftRange = Range(match.range, in: input) {
                let textBefore = String(input[lastEnd..<swiftRange.lowerBound])
                if !textBefore.isEmpty {
                    result.append(styledString(textBefore, style: style))
                }

                // Parse the escape sequence
                if let codeRange = Range(match.range(at: 1), in: input) {
                    let codes = String(input[codeRange])
                    parseEscapeCodes(codes, style: &style)
                }

                lastEnd = swiftRange.upperBound
            }
        }

        // Append remaining text
        let remaining = String(input[lastEnd...])
        if !remaining.isEmpty {
            result.append(styledString(remaining, style: style))
        }

        return result
    }

    static func styledString(_ text: String, style: ANSITextStyle) -> AttributedString {
        var attributed = AttributedString(text)

        // Foreground color
        if case .default = style.foreground {
            // Use primary color
        } else {
            attributed.foregroundColor = style.foreground.color
        }

        // Apply dim effect
        if style.dim {
            attributed.foregroundColor = (attributed.foregroundColor ?? .primary).opacity(0.6)
        }

        // Bold
        if style.bold {
            attributed.font = .system(size: 11, weight: .bold, design: .monospaced)
        }

        // Italic
        if style.italic {
            attributed.font = .system(size: 11, design: .monospaced).italic()
        }

        // Underline
        if style.underline {
            attributed.underlineStyle = .single
        }

        // Strikethrough
        if style.strikethrough {
            attributed.strikethroughStyle = .single
        }

        return attributed
    }

    /// Strip all ANSI escape codes from string
    static func stripANSI(_ input: String) -> String {
        let pattern = "\u{001B}\\[[0-9;]*m"
        return input.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
    }
}
