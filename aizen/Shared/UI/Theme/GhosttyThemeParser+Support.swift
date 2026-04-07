import Foundation
import AppKit
import VVCode

nonisolated extension NSColor {
    convenience init(hex: String, alpha: Double = 1.0) {
        let hex = hex.trimmingCharacters(in: .alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        self.init(hex: Int(int), alpha: alpha)
    }

    convenience init(hex: Int, alpha: Double = 1.0) {
        let red = (hex >> 16) & 0xFF
        let green = (hex >> 8) & 0xFF
        let blue = hex & 0xFF
        self.init(srgbRed: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255, alpha: alpha)
    }

    var hexInt: Int {
        guard let components = cgColor.components, components.count >= 3 else { return 0 }
        let red = lround((Double(components[0]) * 255.0)) << 16
        let green = lround((Double(components[1]) * 255.0)) << 8
        let blue = lround(Double(components[2]) * 255.0)
        return red | green | blue
    }

    var hexString: String {
        String(format: "%06x", hexInt)
    }

    var luminance: Double {
        guard let rgb = usingColorSpace(.sRGB) else { return 0 }
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        rgb.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (0.299 * r) + (0.587 * g) + (0.114 * b)
    }

    func darken(by amount: CGFloat) -> NSColor {
        var h: CGFloat = 0
        var s: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return NSColor(hue: h, saturation: s, brightness: b * (1 - amount), alpha: a)
    }

    func lighten(by amount: CGFloat) -> NSColor {
        var h: CGFloat = 0
        var s: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return NSColor(hue: h, saturation: s, brightness: min(b + ((1 - b) * amount), 1), alpha: a)
    }
}

nonisolated struct GitStatusColors {
    let modified: NSColor
    let added: NSColor
    let untracked: NSColor
    let deleted: NSColor
    let renamed: NSColor

    static let `default` = GitStatusColors(
        modified: NSColor(hex: "F9E2AF"),
        added: NSColor(hex: "A6E3A1"),
        untracked: NSColor(hex: "89B4FA"),
        deleted: NSColor(hex: "F38BA8"),
        renamed: NSColor(hex: "F5C2E7")
    )
}

nonisolated extension GhosttyThemeParser {
    struct ParsedTheme {
        var background: NSColor?
        var foreground: NSColor?
        var cursorColor: NSColor?
        var selectionBackground: NSColor?
        var palette: [Int: NSColor] = [:]

        func toGitStatusColors() -> GitStatusColors {
            GitStatusColors(
                modified: palette[3] ?? NSColor(hex: "F9E2AF"),
                added: palette[2] ?? NSColor(hex: "A6E3A1"),
                untracked: palette[4] ?? NSColor(hex: "89B4FA"),
                deleted: palette[1] ?? NSColor(hex: "F38BA8"),
                renamed: palette[5] ?? NSColor(hex: "F5C2E7")
            )
        }

        func toVVTheme() -> VVTheme {
            let bg = background ?? NSColor(hex: "1E1E2E")
            let fg = foreground ?? NSColor(hex: "CDD6F4")
            let selection = selectionBackground ?? NSColor(hex: "585B70")
            let brightBlack = palette[8] ?? NSColor(hex: "585B70")

            var lineHighlightColor = bg
            if let components = bg.usingColorSpace(.deviceRGB) {
                let brightness = components.brightnessComponent
                if brightness < 0.5 {
                    lineHighlightColor = NSColor(
                        red: min(components.redComponent + 0.05, 1.0),
                        green: min(components.greenComponent + 0.05, 1.0),
                        blue: min(components.blueComponent + 0.05, 1.0),
                        alpha: 1.0
                    )
                } else {
                    lineHighlightColor = NSColor(
                        red: max(components.redComponent - 0.05, 0.0),
                        green: max(components.greenComponent - 0.05, 0.0),
                        blue: max(components.blueComponent - 0.05, 0.0),
                        alpha: 1.0
                    )
                }
            }

            let gitColors = toGitStatusColors()

            return VVTheme(
                id: "ghostty-\(bg.hexString)-\(fg.hexString)",
                backgroundColor: bg,
                textColor: fg,
                selectionColor: selection,
                currentLineColor: lineHighlightColor,
                gutterBackgroundColor: bg,
                gutterTextColor: brightBlack,
                gutterActiveTextColor: fg,
                gutterSeparatorColor: brightBlack.withAlphaComponent(0.5),
                cursorColor: cursorColor ?? fg,
                gitAddedColor: gitColors.added,
                gitModifiedColor: gitColors.modified,
                gitDeletedColor: gitColors.deleted
            )
        }
    }
}
