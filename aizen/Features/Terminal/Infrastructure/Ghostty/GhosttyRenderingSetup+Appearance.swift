//
//  GhosttyRenderingSetup+Appearance.swift
//  aizen
//
//  Appearance observation support for Ghostty rendering.
//

import AppKit
import GhosttyKit
import OSLog

@MainActor
extension GhosttyRenderingSetup {
    /// Setup observation for system appearance changes (light/dark mode)
    /// Implementation copied from Ghostty's SurfaceView_AppKit.swift
    func setupAppearanceObservation(for view: NSView, surface: Ghostty.Surface?) -> NSKeyValueObservation? {
        return view.observe(\.effectiveAppearance, options: [.new, .initial]) { view, change in
            guard let appearance = change.newValue else { return }
            guard let surface = surface?.unsafeCValue else { return }

            let scheme: ghostty_color_scheme_e
            switch (appearance.name) {
            case .aqua, .vibrantLight:
                scheme = GHOSTTY_COLOR_SCHEME_LIGHT

            case .darkAqua, .vibrantDark:
                scheme = GHOSTTY_COLOR_SCHEME_DARK

            default:
                scheme = GHOSTTY_COLOR_SCHEME_DARK
            }

            ghostty_surface_set_color_scheme(surface, scheme)
            Self.logger.debug("Color scheme updated to: \(scheme == GHOSTTY_COLOR_SCHEME_DARK ? "dark" : "light")")
        }
    }
}
