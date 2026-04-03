import ACP
import Foundation

extension ChatMessageList {
    func messageMarkdown(_ message: MessageItem) -> String {
        let normalizedContent = normalizedMessageMarkdown(
            message.content,
            role: message.role
        )
        if !normalizedContent.isEmpty {
            return normalizedContent
        }

        var lines: [String] = []
        for block in message.contentBlocks {
            if let markdown = attachmentMarkdown(for: block, role: message.role) {
                lines.append(markdown)
            }
        }

        return normalizedMessageMarkdown(lines.joined(separator: "\n\n"), role: message.role)
    }

    func attachmentMarkdown(for block: ContentBlock, role: MessageRole) -> String? {
        switch block {
        case .text(let text):
            let trimmed = text.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : normalizedMessageMarkdown(text.text, role: role)
        case .image:
            return escapeMarkdownForPlainText("[Image attachment]")
        case .audio:
            return escapeMarkdownForPlainText("[Audio attachment]")
        case .resource(let resource):
            if role == .user {
                let label = resourceLabel(from: resource.resource.uri, fallback: "Resource attachment")
                return escapeMarkdownForPlainText(label)
            }
            if let uri = resource.resource.uri {
                return "[Resource](\(uri))"
            }
            return "[Resource attachment]"
        case .resourceLink(let link):
            if role == .user {
                return escapeMarkdownForPlainText(link.name)
            }
            return "[\(link.name)](\(link.uri))"
        }
    }

    func resourceLabel(from rawURI: String?, fallback: String) -> String {
        guard let rawURI, !rawURI.isEmpty else { return fallback }
        if let url = URL(string: rawURI) {
            let component = url.lastPathComponent
            if !component.isEmpty {
                return component
            }
        }
        let trimmed = rawURI.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    func normalizedMessageMarkdown(_ content: String, role: MessageRole) -> String {
        let normalized = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
        let trimmed = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        if role == .user {
            return escapeMarkdownForPlainText(trimmed)
        }

        guard role == .agent else {
            return trimmed
        }

        var lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        var inFence = false
        var commonIndent: Int?
        for line in lines {
            let marker = line.trimmingCharacters(in: .whitespaces)
            if marker.hasPrefix("```") || marker.hasPrefix("~~~") {
                inFence.toggle()
                continue
            }
            if inFence || marker.isEmpty {
                continue
            }
            let indent = leadingHorizontalWhitespaceCount(line)
            commonIndent = min(commonIndent ?? indent, indent)
            if commonIndent == 0 {
                break
            }
        }

        if let commonIndent, commonIndent > 0 {
            inFence = false
            lines = lines.map { line in
                let marker = line.trimmingCharacters(in: .whitespaces)
                if marker.hasPrefix("```") || marker.hasPrefix("~~~") {
                    inFence.toggle()
                    return line
                }
                if inFence || line.isEmpty {
                    return line
                }
                return dropLeadingIndent(line, maxCount: commonIndent)
            }
        }

        inFence = false
        lines = lines.map { line in
            let marker = line.trimmingCharacters(in: .whitespaces)
            if marker.hasPrefix("```") || marker.hasPrefix("~~~") {
                inFence.toggle()
                return line
            }
            if inFence || marker.isEmpty {
                return line
            }
            let indent = leadingHorizontalWhitespaceCount(line)
            guard indent > 0 else {
                return line
            }
            guard let first = marker.first else {
                return line
            }
            let shouldUnindent = first == "#"
                || first == "`"
                || first == "\""
                || first == "'"
                || first.isLetter
                || first.isNumber
            guard shouldUnindent else {
                return line
            }
            return dropLeadingIndent(line, maxCount: indent)
        }

        return lines.joined(separator: "\n")
    }

    func escapeMarkdownForPlainText(_ content: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(content.count)

        let specialCharacters: Set<Character> = ["\\", "`", "*", "_", "{", "}", "[", "]", "(", ")", "#", "!", "|", ">"]

        for character in content {
            if specialCharacters.contains(character) {
                escaped.append("\\")
            }
            escaped.append(character)
        }

        return escaped
    }

    func dropLeadingIndent(_ line: String, maxCount: Int) -> String {
        guard maxCount > 0, !line.isEmpty else { return line }
        var remaining = maxCount
        var index = line.startIndex
        while remaining > 0, index < line.endIndex {
            let char = line[index]
            guard isHorizontalWhitespace(char) else { break }
            index = line.index(after: index)
            remaining -= 1
        }
        return String(line[index...])
    }

    func leadingHorizontalWhitespaceCount(_ line: String) -> Int {
        var count = 0
        for char in line {
            guard isHorizontalWhitespace(char) else { break }
            count += 1
        }
        return count
    }

    func isHorizontalWhitespace(_ char: Character) -> Bool {
        char.unicodeScalars.allSatisfy { scalar in
            scalar.properties.isWhitespace && !CharacterSet.newlines.contains(scalar)
        }
    }
}
