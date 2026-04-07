//
//  TerminalTextCleaner.swift
//  aizen
//

import Foundation

struct TerminalCopySettings {
    var trimTrailingWhitespace: Bool = true
    var collapseBlankLines: Bool = false
    var stripShellPrompts: Bool = false
    var flattenCommands: Bool = false
    var removeBoxDrawing: Bool = false
    var stripAnsiCodes: Bool = true
}

nonisolated struct TerminalTextCleaner {
    static func cleanText(_ text: String, settings: TerminalCopySettings) -> String {
        var result = text

        if settings.stripAnsiCodes {
            result = stripAnsiCodes(result)
        }

        if settings.removeBoxDrawing {
            if let cleaned = stripBoxDrawingCharacters(in: result) {
                result = cleaned
            }
        }

        if settings.stripShellPrompts {
            if let stripped = stripPromptPrefixes(result) {
                result = stripped
            }
        }

        if settings.flattenCommands {
            if let flattened = flattenMultilineCommand(result) {
                result = flattened
            }
        }

        if settings.trimTrailingWhitespace {
            result = trimTrailingWhitespace(result)
        }

        if settings.collapseBlankLines {
            result = collapseBlankLines(result)
        }

        return result
    }

    // MARK: - ANSI Codes

    static func stripAnsiCodes(_ text: String) -> String {
        // Match ANSI escape sequences: ESC[ followed by params and command
        // Covers: colors, cursor movement, clearing, etc.
        let patterns = [
            #"\x1b\[[0-9;]*[A-Za-z]"#,  // CSI sequences (colors, cursor, etc.)
            #"\x1b\][^\x07]*\x07"#,      // OSC sequences (title, etc.)
            #"\x1b\][^\x1b]*\x1b\\"#,    // OSC with ST terminator
            #"\x1b[PX^_][^\x1b]*\x1b\\"#, // DCS, SOS, PM, APC sequences
            #"\x1b[@-Z\\-_]"#,           // Fe escape sequences
        ]

        var result = text
        for pattern in patterns {
            result = result.replacingOccurrences(
                of: pattern,
                with: "",
                options: .regularExpression
            )
        }
        return result
    }

    // MARK: - Trailing Whitespace

    static func trimTrailingWhitespace(_ text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let trimmed = lines.map { line -> String in
            var s = String(line)
            while s.last?.isWhitespace == true && s.last != "\n" {
                s.removeLast()
            }
            return s
        }
        return trimmed.joined(separator: "\n")
    }

    // MARK: - Blank Lines

    static func collapseBlankLines(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"\n{3,}"#,
            with: "\n\n",
            options: .regularExpression
        )
    }

}
