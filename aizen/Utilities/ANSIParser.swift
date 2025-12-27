//
//  ANSIParser.swift
//  aizen
//
//  Parses ANSI escape codes and converts to AttributedString for SwiftUI
//

import SwiftUI

// MARK: - ANSI Color Definitions

enum ANSIColor {
    case `default`
    case black, red, green, yellow, blue, magenta, cyan, white
    case brightBlack, brightRed, brightGreen, brightYellow
    case brightBlue, brightMagenta, brightCyan, brightWhite
    case rgb(UInt8, UInt8, UInt8)
    case palette(UInt8)

    // Aizen Dark palette colors
    var color: Color {
        switch self {
        case .default: return .primary
        case .black: return Color(red: 0.102, green: 0.102, blue: 0.102)           // #1a1a1a
        case .red: return Color(red: 0.941, green: 0.533, blue: 0.596)             // #f08898
        case .green: return Color(red: 0.643, green: 0.878, blue: 0.612)           // #a4e09c
        case .yellow: return Color(red: 0.961, green: 0.871, blue: 0.643)          // #f5dea4
        case .blue: return Color(red: 0.518, green: 0.706, blue: 0.973)            // #84b4f8
        case .magenta: return Color(red: 0.784, green: 0.635, blue: 0.957)         // #c8a2f4
        case .cyan: return Color(red: 0.565, green: 0.863, blue: 0.816)            // #90dcd0
        case .white: return Color(red: 0.816, green: 0.839, blue: 0.941)           // #d0d6f0
        case .brightBlack: return Color(red: 0.267, green: 0.267, blue: 0.267)     // #444444
        case .brightRed: return Color(red: 0.941, green: 0.533, blue: 0.596)       // #f08898
        case .brightGreen: return Color(red: 0.643, green: 0.878, blue: 0.612)     // #a4e09c
        case .brightYellow: return Color(red: 0.961, green: 0.871, blue: 0.643)    // #f5dea4
        case .brightBlue: return Color(red: 0.518, green: 0.706, blue: 0.973)      // #84b4f8
        case .brightMagenta: return Color(red: 0.784, green: 0.635, blue: 0.957)   // #c8a2f4
        case .brightCyan: return Color(red: 0.565, green: 0.863, blue: 0.816)      // #90dcd0
        case .brightWhite: return Color(white: 1.0)                                 // #ffffff
        case .rgb(let r, let g, let b):
            return Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
        case .palette(let index):
            return paletteColor(index)
        }
    }

    private func paletteColor(_ index: UInt8) -> Color {
        // Standard 16 colors (0-15)
        if index < 16 {
            let colors: [ANSIColor] = [
                .black, .red, .green, .yellow, .blue, .magenta, .cyan, .white,
                .brightBlack, .brightRed, .brightGreen, .brightYellow,
                .brightBlue, .brightMagenta, .brightCyan, .brightWhite
            ]
            return colors[Int(index)].color
        }
        // 216 color cube (16-231)
        if index < 232 {
            let adjusted = Int(index) - 16
            let r = adjusted / 36
            let g = (adjusted % 36) / 6
            let b = adjusted % 6
            return Color(
                red: r == 0 ? 0 : Double(r * 40 + 55) / 255,
                green: g == 0 ? 0 : Double(g * 40 + 55) / 255,
                blue: b == 0 ? 0 : Double(b * 40 + 55) / 255
            )
        }
        // Grayscale (232-255)
        let gray = Double((Int(index) - 232) * 10 + 8) / 255
        return Color(white: gray)
    }
}

// MARK: - Text Style

struct ANSITextStyle {
    var foreground: ANSIColor = .default
    var background: ANSIColor = .default
    var bold: Bool = false
    var italic: Bool = false
    var underline: Bool = false
    var dim: Bool = false
    var strikethrough: Bool = false

    mutating func reset() {
        foreground = .default
        background = .default
        bold = false
        italic = false
        underline = false
        dim = false
        strikethrough = false
    }
}

// MARK: - ANSI Parser

struct ANSIParser {
    /// Parse ANSI-encoded string to AttributedString
    static func parse(_ input: String) -> AttributedString {
        var result = AttributedString()
        var style = ANSITextStyle()
        var currentText = ""

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

    static func parseEscapeCodes(_ codes: String, style: inout ANSITextStyle) {
        let parts = codes.split(separator: ";").compactMap { Int($0) }

        if parts.isEmpty {
            style.reset()
            return
        }

        var i = 0
        while i < parts.count {
            let code = parts[i]

            switch code {
            case 0: style.reset()
            case 1: style.bold = true
            case 2: style.dim = true
            case 3: style.italic = true
            case 4: style.underline = true
            case 9: style.strikethrough = true
            case 21: style.bold = false
            case 22: style.bold = false; style.dim = false
            case 23: style.italic = false
            case 24: style.underline = false
            case 29: style.strikethrough = false

            // Foreground colors
            case 30: style.foreground = .black
            case 31: style.foreground = .red
            case 32: style.foreground = .green
            case 33: style.foreground = .yellow
            case 34: style.foreground = .blue
            case 35: style.foreground = .magenta
            case 36: style.foreground = .cyan
            case 37: style.foreground = .white
            case 39: style.foreground = .default

            // Background colors
            case 40: style.background = .black
            case 41: style.background = .red
            case 42: style.background = .green
            case 43: style.background = .yellow
            case 44: style.background = .blue
            case 45: style.background = .magenta
            case 46: style.background = .cyan
            case 47: style.background = .white
            case 49: style.background = .default

            // Bright foreground
            case 90: style.foreground = .brightBlack
            case 91: style.foreground = .brightRed
            case 92: style.foreground = .brightGreen
            case 93: style.foreground = .brightYellow
            case 94: style.foreground = .brightBlue
            case 95: style.foreground = .brightMagenta
            case 96: style.foreground = .brightCyan
            case 97: style.foreground = .brightWhite

            // Bright background
            case 100: style.background = .brightBlack
            case 101: style.background = .brightRed
            case 102: style.background = .brightGreen
            case 103: style.background = .brightYellow
            case 104: style.background = .brightBlue
            case 105: style.background = .brightMagenta
            case 106: style.background = .brightCyan
            case 107: style.background = .brightWhite

            // 256 color / RGB
            case 38:
                if i + 1 < parts.count {
                    if parts[i + 1] == 5, i + 2 < parts.count {
                        // 256 color palette
                        style.foreground = .palette(UInt8(parts[i + 2]))
                        i += 2
                    } else if parts[i + 1] == 2, i + 4 < parts.count {
                        // RGB
                        style.foreground = .rgb(
                            UInt8(parts[i + 2]),
                            UInt8(parts[i + 3]),
                            UInt8(parts[i + 4])
                        )
                        i += 4
                    }
                }

            case 48:
                if i + 1 < parts.count {
                    if parts[i + 1] == 5, i + 2 < parts.count {
                        // 256 color palette
                        style.background = .palette(UInt8(parts[i + 2]))
                        i += 2
                    } else if parts[i + 1] == 2, i + 4 < parts.count {
                        // RGB
                        style.background = .rgb(
                            UInt8(parts[i + 2]),
                            UInt8(parts[i + 3]),
                            UInt8(parts[i + 4])
                        )
                        i += 4
                    }
                }

            default:
                break
            }

            i += 1
        }
    }

    /// Strip all ANSI escape codes from string
    static func stripANSI(_ input: String) -> String {
        let pattern = "\u{001B}\\[[0-9;]*m"
        return input.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
    }
}

// MARK: - SwiftUI View for ANSI Text

struct ANSITextView: View {
    let text: String
    let fontSize: CGFloat

    init(_ text: String, fontSize: CGFloat = 11) {
        self.text = text
        self.fontSize = fontSize
    }

    var body: some View {
        Text(ANSIParser.parse(text))
            .font(.system(size: fontSize, design: .monospaced))
            .textSelection(.enabled)
    }
}

// MARK: - Parsed Line for Lazy Rendering

struct ANSIParsedLine: Identifiable {
    let id: Int
    let attributedString: AttributedString
    let rawText: String
}

// MARK: - Line-Based Parser for Lazy Loading

extension ANSIParser {
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
    private static func parseLine(_ input: String, initialStyle: ANSITextStyle) -> (AttributedString, ANSITextStyle) {
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

// MARK: - Lazy ANSI Log View

struct ANSILazyLogView: View {
    let logs: String
    let fontSize: CGFloat

    @State private var parsedLines: [ANSIParsedLine] = []
    @State private var isProcessing = true

    init(_ logs: String, fontSize: CGFloat = 11) {
        self.logs = logs
        self.fontSize = fontSize
    }

    var body: some View {
        Group {
            if isProcessing {
                VStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Processing logs...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
            } else if parsedLines.isEmpty {
                Text("No logs available")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView([.horizontal, .vertical]) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(parsedLines) { line in
                                Text(line.attributedString)
                                    .font(.system(size: fontSize, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(line.id)
                            }
                        }
                        .padding(12)
                    }
                    .background(Color(nsColor: .textBackgroundColor))
                }
            }
        }
        .onChange(of: logs) { newLogs in
            parseLogsAsync(newLogs)
        }
        .onAppear {
            parseLogsAsync(logs)
        }
    }

    private func parseLogsAsync(_ text: String) {
        isProcessing = true
        Task.detached(priority: .userInitiated) {
            let lines = ANSIParser.parseLines(text)
            await MainActor.run {
                parsedLines = lines
                isProcessing = false
            }
        }
    }
}
