import AppKit

nonisolated enum WorkflowLogANSIFormatter {
    static func parseLineToAttributedString(
        _ text: String,
        style: ANSITextStyle,
        fontSize: CGFloat
    ) -> (NSAttributedString, ANSITextStyle) {
        let result = NSMutableAttributedString()
        var currentStyle = style

        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let defaultAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor
        ]

        let pattern = "\u{001B}\\[([0-9;]*)m"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return (NSAttributedString(string: text, attributes: defaultAttrs), currentStyle)
        }

        var lastEnd = text.startIndex
        let nsString = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))

        for match in matches {
            if let swiftRange = Range(match.range, in: text) {
                let textBefore = String(text[lastEnd..<swiftRange.lowerBound])
                if !textBefore.isEmpty {
                    result.append(NSAttributedString(string: textBefore, attributes: attributesForStyle(currentStyle, fontSize: fontSize)))
                }

                if let codeRange = Range(match.range(at: 1), in: text) {
                    let codes = String(text[codeRange])
                    parseANSICodes(codes, style: &currentStyle)
                }

                lastEnd = swiftRange.upperBound
            }
        }

        let remaining = String(text[lastEnd...])
        if !remaining.isEmpty {
            result.append(NSAttributedString(string: remaining, attributes: attributesForStyle(currentStyle, fontSize: fontSize)))
        }

        if result.length == 0 {
            result.append(NSAttributedString(string: " ", attributes: defaultAttrs))
        }

        return (result, currentStyle)
    }

    static func attributesForStyle(_ style: ANSITextStyle, fontSize: CGFloat) -> [NSAttributedString.Key: Any] {
        var attrs: [NSAttributedString.Key: Any] = [:]

        let weight: NSFont.Weight = style.bold ? .bold : .regular
        attrs[.font] = NSFont.monospacedSystemFont(ofSize: fontSize, weight: weight)

        var color = NSColor.labelColor
        switch style.foreground {
        case .red: color = NSColor(red: 0.8, green: 0.2, blue: 0.2, alpha: 1)
        case .green: color = NSColor(red: 0.2, green: 0.8, blue: 0.2, alpha: 1)
        case .yellow: color = NSColor(red: 0.8, green: 0.8, blue: 0.2, alpha: 1)
        case .blue: color = NSColor(red: 0.2, green: 0.4, blue: 0.9, alpha: 1)
        case .magenta: color = NSColor(red: 0.8, green: 0.2, blue: 0.8, alpha: 1)
        case .cyan: color = NSColor(red: 0.2, green: 0.8, blue: 0.8, alpha: 1)
        case .brightRed: color = NSColor(red: 1.0, green: 0.4, blue: 0.4, alpha: 1)
        case .brightGreen: color = NSColor(red: 0.4, green: 1.0, blue: 0.4, alpha: 1)
        case .brightYellow: color = NSColor(red: 1.0, green: 1.0, blue: 0.4, alpha: 1)
        case .brightBlue: color = NSColor(red: 0.4, green: 0.6, blue: 1.0, alpha: 1)
        case .brightMagenta: color = NSColor(red: 1.0, green: 0.4, blue: 1.0, alpha: 1)
        case .brightCyan: color = NSColor(red: 0.4, green: 1.0, blue: 1.0, alpha: 1)
        case .white, .brightWhite: color = NSColor.white
        case .black, .brightBlack: color = NSColor(white: 0.4, alpha: 1)
        default: break
        }

        if style.dim {
            color = color.withAlphaComponent(0.6)
        }
        attrs[.foregroundColor] = color

        if style.underline {
            attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }

        return attrs
    }

    static func parseANSICodes(_ codes: String, style: inout ANSITextStyle) {
        let parts = codes.split(separator: ";").compactMap { Int($0) }
        if parts.isEmpty {
            style.reset()
            return
        }

        for code in parts {
            switch code {
            case 0: style.reset()
            case 1: style.bold = true
            case 2: style.dim = true
            case 4: style.underline = true
            case 22: style.bold = false; style.dim = false
            case 24: style.underline = false
            case 30: style.foreground = .black
            case 31: style.foreground = .red
            case 32: style.foreground = .green
            case 33: style.foreground = .yellow
            case 34: style.foreground = .blue
            case 35: style.foreground = .magenta
            case 36: style.foreground = .cyan
            case 37: style.foreground = .white
            case 39: style.foreground = .default
            case 90: style.foreground = .brightBlack
            case 91: style.foreground = .brightRed
            case 92: style.foreground = .brightGreen
            case 93: style.foreground = .brightYellow
            case 94: style.foreground = .brightBlue
            case 95: style.foreground = .brightMagenta
            case 96: style.foreground = .brightCyan
            case 97: style.foreground = .brightWhite
            default: break
            }
        }
    }
}
