import Foundation
import GhosttyKit
import OSLog

extension Ghostty.App {
    /// Generate and load config content into a ghostty_config_t
    func loadConfigIntoGhostty(_ config: ghostty_config_t) {
        let tempDir = NSTemporaryDirectory()
        let ghosttyConfigDir = (tempDir as NSString).appendingPathComponent(".config/ghostty")
        let configFilePath = (ghosttyConfigDir as NSString).appendingPathComponent("config")

        do {
            try FileManager.default.createDirectory(atPath: ghosttyConfigDir, withIntermediateDirectories: true)

            let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
            let shellName = (shell as NSString).lastPathComponent

            let configContent = """
            font-family = \(terminalFontName)
            font-size = \(Int(terminalFontSize))
            window-inherit-font-size = false
            window-padding-balance = false
            window-padding-x = 0
            window-padding-y = 0
            window-padding-color = extend-always

            # Enable shell integration (resources dir auto-detected from app bundle)
            shell-integration = \(shellName)
            shell-integration-features = no-cursor,sudo,title

            # Cursor
            cursor-style-blink = true

            theme = \(effectiveThemeName)

            # Disable audible bell
            audible-bell = false

            # Custom keybinds
            keybind = shift+enter=text:\\n

            """

            try configContent.write(toFile: configFilePath, atomically: true, encoding: String.Encoding.utf8)

            setenv("XDG_CONFIG_HOME", (tempDir as NSString).appendingPathComponent(".config"), 1)
            ghostty_config_load_default_files(config)
        } catch {
            Ghostty.logger.warning("Failed to write config: \(error)")
        }
    }
}
