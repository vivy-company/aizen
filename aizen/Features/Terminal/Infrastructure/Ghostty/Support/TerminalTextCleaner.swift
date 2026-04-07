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
    private static let boxDrawingCharacterClass = "[│┃╎╏┆┇┊┋╽╿￨｜]"

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

    // MARK: - Box Drawing

    static func stripBoxDrawingCharacters(in text: String) -> String? {
        let boxRegex = try? NSRegularExpression(pattern: boxDrawingCharacterClass, options: [])
        if boxRegex?.firstMatch(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)) == nil {
            return nil
        }

        var result = text

        if result.contains("│ │") {
            result = result.replacingOccurrences(of: "│ │", with: " ")
        }

        let lines = result.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        let nonEmptyLines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        if !nonEmptyLines.isEmpty {
            let leadingPattern = #"^\s*\#(boxDrawingCharacterClass)+ ?"#
            let trailingPattern = #" ?\#(boxDrawingCharacterClass)+\s*$"#
            let majorityThreshold = nonEmptyLines.count / 2 + 1

            let leadingMatches = nonEmptyLines.count(where: {
                $0.range(of: leadingPattern, options: .regularExpression) != nil
            })
            let trailingMatches = nonEmptyLines.count(where: {
                $0.range(of: trailingPattern, options: .regularExpression) != nil
            })

            let stripLeading = leadingMatches >= majorityThreshold
            let stripTrailing = trailingMatches >= majorityThreshold

            if stripLeading || stripTrailing {
                var rebuilt: [String] = []
                rebuilt.reserveCapacity(lines.count)

                for line in lines {
                    var lineStr = String(line)
                    if stripLeading {
                        lineStr = lineStr.replacingOccurrences(
                            of: leadingPattern,
                            with: "",
                            options: .regularExpression)
                    }
                    if stripTrailing {
                        lineStr = lineStr.replacingOccurrences(
                            of: trailingPattern,
                            with: "",
                            options: .regularExpression)
                    }
                    rebuilt.append(lineStr)
                }

                result = rebuilt.joined(separator: "\n")
            }
        }

        // Clean up box chars in mid-token positions
        let boxAfterPipePattern = #"\|\s*\#(boxDrawingCharacterClass)+\s*"#
        result = result.replacingOccurrences(
            of: boxAfterPipePattern,
            with: "| ",
            options: .regularExpression)

        let boxMidTokenPattern = #"(\S)\s*\#(boxDrawingCharacterClass)+\s*(\S)"#
        result = result.replacingOccurrences(
            of: boxMidTokenPattern,
            with: "$1 $2",
            options: .regularExpression)

        result = result.replacingOccurrences(
            of: #"\s*\#(boxDrawingCharacterClass)+\s*"#,
            with: " ",
            options: .regularExpression)

        let collapsed = result.replacingOccurrences(
            of: #" {2,}"#,
            with: " ",
            options: .regularExpression)

        let trimmed = collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed == text ? nil : trimmed
    }
}
