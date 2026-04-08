//
//  Ghostty.SurfaceReference.swift
//  aizen
//

import GhosttyKit

extension Ghostty {
    /// Wrapper to hold reference to a surface for tracking.
    /// Note: `ghostty_surface_t` is opaque, so we store it directly.
    class SurfaceReference {
        let surface: ghostty_surface_t
        var isValid = true

        init(_ surface: ghostty_surface_t) {
            self.surface = surface
        }

        func invalidate() {
            isValid = false
        }
    }
}
