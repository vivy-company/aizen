//
//  ANSIParser+LineParsing.swift
//  aizen
//
//  Created by OpenAI Codex on 07.04.26.
//

import Foundation
import SwiftUI

// MARK: - Parsed Line for Lazy Rendering

nonisolated struct ANSIParsedLine: Identifiable, Sendable {
    let id: Int
    let attributedString: AttributedString
    let rawText: String
}

// MARK: - Line-Based Parser for Lazy Loading

nonisolated extension ANSIParser {
    /// Parse log text into lines for lazy rendering
    static func parseLines(_ text: String) -> [ANSIParsedLine] {
        let lines = text.components(separatedBy: "\n")
        var result: [ANSIParsedLine] = []
        result.reserveCapacity(lines.count)

        // Track style across lines (ANSI codes can span lines)
        var currentStyle = ANSITextStyle()

        for (index, line) in lines.enumerated() {
            let (attributed, newStyle) = parseLine(line, initialStyle: currentStyle)
            result.append(ANSIParsedLine(
                id: index,
                attributedString: attributed,
                rawText: stripANSI(line)
            ))
            currentStyle = newStyle
        }

        return result
    }

    /// Parse a single line with initial style state, returns attributed string and final style
    static func parseLine(_ input: String, initialStyle: ANSITextStyle) -> (AttributedString, ANSITextStyle) {
        var result = AttributedString()
        var style = initialStyle

        let pattern = "\u{001B}\\[([0-9;]*)m"
        let regex = try? NSRegularExpression(pattern: pattern, options: [])

        var lastEnd = input.startIndex
        let nsString = input as NSString
        let matches = regex?.matches(in: input, options: [], range: NSRange(location: 0, length: nsString.length)) ?? []

        for match in matches {
            if let swiftRange = Range(match.range, in: input) {
                let textBefore = String(input[lastEnd..<swiftRange.lowerBound])
                if !textBefore.isEmpty {
                    result.append(styledString(textBefore, style: style))
                }

                if let codeRange = Range(match.range(at: 1), in: input) {
                    let codes = String(input[codeRange])
                    parseEscapeCodes(codes, style: &style)
                }

                lastEnd = swiftRange.upperBound
            }
        }

        let remaining = String(input[lastEnd...])
        if !remaining.isEmpty {
            result.append(styledString(remaining, style: style))
        }

        // Return empty space if line is empty for proper line height
        if result.characters.isEmpty {
            result = AttributedString(" ")
        }

        return (result, style)
    }
}
