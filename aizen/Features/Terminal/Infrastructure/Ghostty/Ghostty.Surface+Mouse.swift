import GhosttyKit

extension Ghostty.Surface {
    /// Whether the terminal has captured mouse input.
    ///
    /// When the mouse is captured, the terminal application is receiving mouse events
    /// directly rather than the host system handling them. This typically occurs when
    /// a terminal application enables mouse reporting mode.
    @MainActor
    var mouseCaptured: Bool {
        ghostty_surface_mouse_captured(unsafeCValue)
    }

    /// Send a mouse button event to the terminal.
    ///
    /// This sends a complete mouse button event including the button state (press/release),
    /// which button was pressed, and any modifier keys that were held during the event.
    /// The terminal processes this event according to its mouse handling configuration.
    @MainActor
    func sendMouseButton(_ event: Ghostty.Input.MouseButtonEvent) -> Bool {
        ghostty_surface_mouse_button(
            unsafeCValue,
            event.action.cMouseState,
            event.button.cMouseButton,
            event.mods.cMods
        )
    }

    /// Send a mouse position event to the terminal.
    @MainActor
    func sendMousePos(_ event: Ghostty.Input.MousePosEvent) {
        ghostty_surface_mouse_pos(
            unsafeCValue,
            event.x,
            event.y,
            event.mods.cMods
        )
    }

    /// Send a mouse scroll event to the terminal.
    @MainActor
    func sendMouseScroll(_ event: Ghostty.Input.MouseScrollEvent) {
        ghostty_surface_mouse_scroll(
            unsafeCValue,
            event.x,
            event.y,
            event.mods.cScrollMods
        )
    }
}
