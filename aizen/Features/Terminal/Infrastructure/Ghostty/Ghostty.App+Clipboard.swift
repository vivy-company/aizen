import Foundation
import GhosttyKit

extension Ghostty.App {
    static func readClipboard(
        _ userdata: UnsafeMutableRawPointer?,
        location: ghostty_clipboard_e,
        state: UnsafeMutableRawPointer?
    ) -> Bool {
        guard let userdata = userdata else { return false }
        let terminalView = Unmanaged<AizenTerminalSurfaceView>.fromOpaque(userdata).takeUnretainedValue()
        guard let surface = terminalView.surface else { return false }

        guard let clipboardString = Clipboard.readString(), !clipboardString.isEmpty else {
            return false
        }

        clipboardString.withCString { ptr in
            ghostty_surface_complete_clipboard_request(surface, ptr, state, false)
        }

        return true
    }

    static func confirmReadClipboard(
        _ userdata: UnsafeMutableRawPointer?,
        string: UnsafePointer<CChar>?,
        state: UnsafeMutableRawPointer?,
        request: ghostty_clipboard_request_e
    ) {
        // Clipboard read confirmation hook; currently intentionally no-op.
    }

    static func writeClipboard(
        _ userdata: UnsafeMutableRawPointer?,
        location: ghostty_clipboard_e,
        contents: UnsafePointer<ghostty_clipboard_content_s>?,
        count: Int,
        confirm: Bool
    ) {
        guard let contents = contents, count > 0 else { return }

        for idx in 0..<count {
            let entry = contents.advanced(by: idx).pointee
            guard let dataPtr = entry.data else { continue }

            var string = String(cString: dataPtr)
            if !string.isEmpty {
                let settings = TerminalCopySettings(
                    trimTrailingWhitespace: UserDefaults.standard.object(forKey: "terminalCopyTrimTrailingWhitespace") as? Bool ?? true,
                    collapseBlankLines: UserDefaults.standard.bool(forKey: "terminalCopyCollapseBlankLines"),
                    stripShellPrompts: UserDefaults.standard.bool(forKey: "terminalCopyStripShellPrompts"),
                    flattenCommands: UserDefaults.standard.bool(forKey: "terminalCopyFlattenCommands"),
                    removeBoxDrawing: UserDefaults.standard.bool(forKey: "terminalCopyRemoveBoxDrawing"),
                    stripAnsiCodes: UserDefaults.standard.object(forKey: "terminalCopyStripAnsiCodes") as? Bool ?? true
                )
                string = TerminalTextCleaner.cleanText(string, settings: settings)

                Clipboard.copy(string)
                return
            }
        }
    }
}
