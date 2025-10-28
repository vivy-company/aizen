//
//  GhosttyConfigWriter.swift
//  aizen
//
//  Utility to generate Ghostty configuration files from Aizen terminal settings
//

import Foundation

struct GhosttyConfigWriter {
    /// Generate Ghostty config content as a string
    ///
    /// - Parameters:
    ///   - backgroundColor: Hex color for background (e.g., "#1e1e2e")
    ///   - foregroundColor: Hex color for foreground text
    ///   - cursorColor: Hex color for cursor
    ///   - selectionBackground: Hex color for text selection
    ///   - palette: Comma-separated 16 hex colors for ANSI palette
    /// - Returns: Config file content as a string
    static func writeConfigContent(
        backgroundColor: String,
        foregroundColor: String,
        cursorColor: String,
        selectionBackground: String,
        palette: String
    ) -> String {
        var configLines: [String] = []

        // Color settings
        configLines.append("background = \(backgroundColor)")
        configLines.append("foreground = \(foregroundColor)")
        configLines.append("cursor-color = \(cursorColor)")
        configLines.append("selection-background = \(selectionBackground)")

        // Parse and add palette colors
        let paletteColors = palette.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
        if paletteColors.count == 16 {
            for (index, color) in paletteColors.enumerated() {
                configLines.append("palette = \(index)=\(color)")
            }
        }

        return configLines.joined(separator: "\n") + "\n"
    }

    /// Write a Ghostty config file with terminal settings
    ///
    /// - Parameters:
    ///   - fontName: Font family name (e.g., "Menlo")
    ///   - fontSize: Font size in points
    ///   - backgroundColor: Hex color for background (e.g., "#1e1e2e")
    ///   - foregroundColor: Hex color for foreground text
    ///   - cursorColor: Hex color for cursor
    ///   - selectionBackground: Hex color for text selection
    ///   - palette: Comma-separated 16 hex colors for ANSI palette
    /// - Returns: Path to the written config file, or nil if failed
    static func writeConfig(
        fontName: String,
        fontSize: Double,
        backgroundColor: String,
        foregroundColor: String,
        cursorColor: String,
        selectionBackground: String,
        palette: String
    ) -> String? {
        // Create temp directory if needed
        let tempDir = NSTemporaryDirectory()
        let configPath = (tempDir as NSString).appendingPathComponent("aizen-ghostty-config")

        var configLines: [String] = []

        // Font settings
        configLines.append("font-family = \(fontName)")
        configLines.append("font-size = \(Int(fontSize))")

        // Add color config content
        configLines.append(writeConfigContent(
            backgroundColor: backgroundColor,
            foregroundColor: foregroundColor,
            cursorColor: cursorColor,
            selectionBackground: selectionBackground,
            palette: palette
        ))

        // Write to file
        let configContent = configLines.joined(separator: "\n")

        do {
            try configContent.write(toFile: configPath, atomically: true, encoding: .utf8)
            return configPath
        } catch {
            print("Failed to write Ghostty config: \(error)")
            return nil
        }
    }
}
