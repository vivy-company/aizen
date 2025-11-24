//
//  GhosttyRenderingSetup.swift
//  aizen
//
//  Handles Metal layer setup and rendering configuration for Ghostty terminal
//

import AppKit
import Metal
import OSLog
import SwiftUI

/// Manages Metal rendering setup and configuration for Ghostty terminal
@MainActor
class GhosttyRenderingSetup {
    private static let logger = Logger(subsystem: "com.aizen.app", category: "GhosttyRendering")

    // MARK: - Terminal Settings from AppStorage

    @AppStorage("terminalFontName") private var terminalFontName = "Menlo"
    @AppStorage("terminalFontSize") private var terminalFontSize = 12.0
    @AppStorage("terminalBackgroundColor") private var terminalBackgroundColor = "#1e1e2e"
    @AppStorage("terminalForegroundColor") private var terminalForegroundColor = "#cdd6f4"
    @AppStorage("terminalCursorColor") private var terminalCursorColor = "#f5e0dc"
    @AppStorage("terminalSelectionBackground") private var terminalSelectionBackground = "#585b70"
    @AppStorage("terminalPalette") private var terminalPalette = "#45475a,#f38ba8,#a6e3a1,#f9e2af,#89b4fa,#f5c2e7,#94e2d5,#a6adc8,#585b70,#f37799,#89d88b,#ebd391,#74a8fc,#f2aede,#6bd7ca,#bac2de"

    // MARK: - Layer Setup

    /// Configure the Metal-backed layer for terminal rendering
    ///
    /// CRITICAL: Must set layer property BEFORE setting wantsLayer = true
    /// This ensures Metal rendering works correctly
    func setupLayer(for view: NSView) {
        // Create Metal layer
        let metalLayer = CAMetalLayer()
        metalLayer.device = MTLCreateSystemDefaultDevice()
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true
        metalLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0

        // IMPORTANT: Set layer before wantsLayer for proper Metal initialization
        view.layer = metalLayer
        view.wantsLayer = true
        view.layerContentsRedrawPolicy = .duringViewResize

        Self.logger.debug("Metal layer configured")
    }

    // MARK: - Surface Setup

    /// Create and configure the Ghostty surface
    func setupSurface(
        view: NSView,
        ghosttyApp: ghostty_app_t,
        worktreePath: String,
        initialBounds: NSRect,
        window: NSWindow?
    ) -> ghostty_surface_t? {
        // Configure surface with working directory
        var surfaceConfig = ghostty_surface_config_new()

        // CRITICAL: Set platform information
        surfaceConfig.platform_tag = GHOSTTY_PLATFORM_MACOS
        surfaceConfig.platform.macos.nsview = Unmanaged.passUnretained(view).toOpaque()

        // Set userdata
        surfaceConfig.userdata = Unmanaged.passUnretained(view).toOpaque()

        // Set scale factor for retina displays
        surfaceConfig.scale_factor = Double(window?.backingScaleFactor ?? 2.0)

        // Set font size from Aizen settings
        surfaceConfig.font_size = Float(terminalFontSize)

        // Set working directory
        if let workingDir = strdup(worktreePath) {
            surfaceConfig.working_directory = UnsafePointer(workingDir)
        }

        // DO NOT set command - let Ghostty handle shell integration
        // Ghostty will detect shell, wrap it with proper env vars, and launch via /usr/bin/login
        surfaceConfig.command = nil

        defer {
            if let wd = surfaceConfig.working_directory {
                free(UnsafeMutableRawPointer(mutating: wd))
            }
        }

        // Create the surface
        // NOTE: subprocess spawns during ghostty_surface_new, so size warnings may appear
        // if view frame isn't set yet - this is unavoidable with current API
        guard let cSurface = ghostty_surface_new(ghosttyApp, &surfaceConfig) else {
            Self.logger.error("ghostty_surface_new failed")
            return nil
        }

        // Immediately set size after creation to minimize "small grid" warnings
        let scaledSize = view.convertToBacking(initialBounds.size.width > 0 ? initialBounds.size : NSSize(width: 800, height: 600))
        ghostty_surface_set_size(
            cSurface,
            UInt32(scaledSize.width),
            UInt32(scaledSize.height)
        )

        // Set content scale for retina displays
        let scale = window?.backingScaleFactor ?? 1.0
        ghostty_surface_set_content_scale(cSurface, scale, scale)

        Self.logger.info("Ghostty surface created at: \(worktreePath)")

        return cSurface
    }

    // MARK: - Appearance Observation

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

    // MARK: - Scale and Size Updates

    /// Update Metal layer content scale and surface scale factors
    func updateBackingProperties(view: NSView, surface: ghostty_surface_t?, window: NSWindow?) {
        guard let surface = surface else { return }

        // Update Metal layer content scale
        if let window = window {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            view.layer?.contentsScale = window.backingScaleFactor
            CATransaction.commit()
        }

        // Update surface scale factors
        let fbFrame = view.convertToBacking(view.frame)
        let xScale = fbFrame.size.width / view.frame.size.width
        let yScale = fbFrame.size.height / view.frame.size.height
        ghostty_surface_set_content_scale(surface, xScale, yScale)

        // Update surface size (framebuffer dimensions changed)
        ghostty_surface_set_size(
            surface,
            UInt32(fbFrame.size.width),
            UInt32(fbFrame.size.height)
        )
    }

    /// Update Metal layer frame and Ghostty surface size
    func updateLayout(view: NSView, metalLayer: CAMetalLayer?, surface: ghostty_surface_t?, lastSize: inout CGSize) -> Bool {
        // Update Metal layer frame to match view bounds
        if let metalLayer = metalLayer {
            metalLayer.frame = view.bounds
        }

        // Update Ghostty surface size during layout pass
        // Only update if backing pixel size actually changed to prevent flicker
        guard let surface = surface else { return false }
        guard view.bounds.width > 0 && view.bounds.height > 0 else { return false }

        var scaledSize = view.convertToBacking(view.bounds.size)
        scaledSize = snapSizeToCell(surface: surface, scaledSize: scaledSize)

        // Only update if size changed by at least 1 pixel
        let widthChanged = abs(scaledSize.width - lastSize.width) >= 1.0
        let heightChanged = abs(scaledSize.height - lastSize.height) >= 1.0

        guard widthChanged || heightChanged else { return false }

        lastSize = scaledSize
        if let metalLayer = metalLayer {
            metalLayer.drawableSize = scaledSize
        }
        ghostty_surface_set_size(
            surface,
            UInt32(scaledSize.width),
            UInt32(scaledSize.height)
        )
        ghostty_surface_refresh(surface)

        return true
    }

    /// Snap the desired pixel size down to the nearest full terminal cell to avoid partial-cell artifacts.
    /// Snap size to whole pixels (scaledSize is already in pixel units).
    func snapSizeToCell(surface: ghostty_surface_t, scaledSize: CGSize) -> CGSize {
        CGSize(width: floor(scaledSize.width), height: floor(scaledSize.height))
    }
}
