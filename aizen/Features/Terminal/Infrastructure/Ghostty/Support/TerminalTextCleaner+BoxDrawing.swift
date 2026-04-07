import Foundation

nonisolated extension TerminalTextCleaner {
    static let boxDrawingCharacterClass = "[│┃╎╏┆┇┊┋╽╿￨｜]"

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

            let leadingMatches = nonEmptyLines.count {
                $0.range(of: leadingPattern, options: .regularExpression) != nil
            }
            let trailingMatches = nonEmptyLines.count {
                $0.range(of: trailingPattern, options: .regularExpression) != nil
            }

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
