import Foundation
import GhosttyKit

extension Ghostty {
    /// Represents a single surface within Ghostty.
    ///
    /// Wraps a `ghostty_surface_t`
    final class Surface: Sendable {
        private let surface: ghostty_surface_t

        // SAFETY: Handle wraps a C pointer that is only accessed from @MainActor methods.
        // The deinit captures this handle to ensure proper cleanup on the main actor.
        private struct Handle: @unchecked Sendable {
            let value: ghostty_surface_t
        }

        /// Read the underlying C value for this surface. This is unsafe because the value will be
        /// freed when the Surface class is deinitialized.
        var unsafeCValue: ghostty_surface_t {
            surface
        }

        /// Initialize from the C structure.
        init(cSurface: ghostty_surface_t) {
            self.surface = cSurface
        }

        deinit {
            // deinit is not guaranteed to happen on the main actor and our API
            // calls into libghostty must happen there so we capture the surface
            // value so we don't capture `self` and then we detach it in a task.
            // We can't wait for the task to succeed so this will happen sometime
            // but that's okay.
            let handle = Handle(value: surface)
            Task.detached { @MainActor in
                ghostty_surface_free(handle.value)
            }
        }

        /// Send text to the terminal as if it was typed. This doesn't send the key events so keyboard
        /// shortcuts and other encodings do not take effect.
        @MainActor
        func sendText(_ text: String) {
            let len = text.utf8CString.count
            if (len == 0) { return }

            text.withCString { ptr in
                // len includes the null terminator so we do len - 1
                ghostty_surface_text(surface, ptr, UInt(len - 1))
            }
        }

        /// Send a key event to the terminal.
        ///
        /// This sends the full key event including modifiers, action type, and text to the terminal.
        /// Unlike `sendText`, this method processes keyboard shortcuts, key bindings, and terminal
        /// encoding based on the complete key event information.
        ///
        /// - Parameter event: The key event to send to the terminal
        @MainActor
        func sendKeyEvent(_ event: Input.KeyEvent) {
            event.withCValue { cEvent in
                ghostty_surface_key(surface, cEvent)
            }
        }

        @MainActor
        func keyTranslationMods(_ mods: ghostty_input_mods_e) -> ghostty_input_mods_e {
            ghostty_surface_key_translation_mods(surface, mods)
        }

        @MainActor
        func keyIsBinding(_ event: ghostty_input_key_s) -> Input.BindingFlags? {
            var flags = ghostty_binding_flags_e(rawValue: 0)
            guard ghostty_surface_key_is_binding(surface, event, &flags) else { return nil }
            return Input.BindingFlags(cFlags: flags)
        }

        /// Perform a keybinding action.
        ///
        /// The action can be any valid keybind parameter. e.g. `keybind = goto_tab:4`
        /// you can perform `goto_tab:4` with this.
        ///
        /// Returns true if the action was performed. Invalid actions return false.
        @MainActor
        func perform(action: String) -> Bool {
            let len = action.utf8CString.count
            if (len == 0) { return false }
            return action.withCString { cString in
                ghostty_surface_binding_action(surface, cString, UInt(len - 1))
            }
        }

        /// Terminal grid size information
        struct TerminalSize {
            let columns: UInt16
            let rows: UInt16
            let widthPx: UInt32
            let heightPx: UInt32
            let cellWidthPx: UInt32
            let cellHeightPx: UInt32
        }

        /// Get current terminal size
        @MainActor
        func terminalSize() -> TerminalSize {
            let cSize = ghostty_surface_size(surface)
            return TerminalSize(
                columns: cSize.columns,
                rows: cSize.rows,
                widthPx: cSize.width_px,
                heightPx: cSize.height_px,
                cellWidthPx: cSize.cell_width_px,
                cellHeightPx: cSize.cell_height_px
            )
        }

        /// Whether closing this terminal requires user confirmation.
        ///
        /// Returns true if the terminal is busy (command running, cursor not at prompt).
        /// Uses Ghostty's internal prompt detection to avoid confirming idle shells.
        @MainActor
        var needsConfirmQuit: Bool {
            ghostty_surface_needs_confirm_quit(surface)
        }
    }
}
