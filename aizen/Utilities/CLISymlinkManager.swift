import Foundation

enum CLISymlinkManager {
    private static let cliName = "aizen"
    private static let bundledCLIName = "aizen-cli"

    static func cliBinaryURL() -> URL? {
        return Bundle.main.resourceURL?
            .appendingPathComponent("cli", isDirectory: true)
            .appendingPathComponent(bundledCLIName)
    }

    static func preferredInstallDirectories() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            URL(fileURLWithPath: "/opt/homebrew/bin"),
            URL(fileURLWithPath: "/usr/local/bin"),
            home.appendingPathComponent(".local/bin"),
            home.appendingPathComponent("bin")
        ]
    }

    static func installedSymlinkURL() -> URL? {
        for dir in preferredInstallDirectories() {
            let link = dir.appendingPathComponent(cliName)
            if FileManager.default.fileExists(atPath: link.path) {
                return link
            }
        }
        return nil
    }

    static func statusMessage() -> String {
        guard let link = installedSymlinkURL() else {
            return "Not installed"
        }
        if let target = try? FileManager.default.destinationOfSymbolicLink(atPath: link.path) {
            return "Installed at \(link.path) → \(target)"
        }
        return "Installed at \(link.path)"
    }

    static func install() -> (success: Bool, message: String) {
        guard let sourceURL = cliBinaryURL() else {
            return (false, "CLI binary not found in app bundle")
        }

        let fileManager = FileManager.default
        for dir in preferredInstallDirectories() {
            var isDir: ObjCBool = false
            if !fileManager.fileExists(atPath: dir.path, isDirectory: &isDir) {
                // Create user-level directories if needed
                if dir.path.hasPrefix(fileManager.homeDirectoryForCurrentUser.path) {
                    try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
                }
            }

            if !fileManager.isWritableFile(atPath: dir.path) {
                continue
            }

            let linkURL = dir.appendingPathComponent(cliName)
            if fileManager.fileExists(atPath: linkURL.path) {
                if let target = try? fileManager.destinationOfSymbolicLink(atPath: linkURL.path),
                   target == sourceURL.path {
                    return (true, "CLI already installed at \(linkURL.path)")
                }
                try? fileManager.removeItem(at: linkURL)
            }

            do {
                try fileManager.createSymbolicLink(atPath: linkURL.path, withDestinationPath: sourceURL.path)
                return (true, "Installed CLI at \(linkURL.path)")
            } catch {
                continue
            }
        }

        return (false, "No writable install location found. Try installing manually.")
    }
}
