//
//  GhosttyTerminalView.swift
//  aizen
//
//  NSView subclass that integrates Ghostty terminal rendering
//

import AppKit
import Metal
import OSLog
import SwiftUI

/// NSView that embeds a Ghostty terminal surface with Metal rendering
///
/// This view handles:
/// - Metal layer setup for terminal rendering
/// - Input forwarding (keyboard, mouse, scroll)
/// - Focus management
/// - Surface lifecycle management
@MainActor
class GhosttyTerminalView: NSView {
    // MARK: - Properties

    private var ghosttyApp: ghostty_app_t?
    private weak var ghosttyAppWrapper: Ghostty.App?
    internal var surface: Ghostty.Surface?
    private var surfaceReference: Ghostty.SurfaceReference?
    private let worktreePath: String

    /// Callback invoked when the terminal process exits
    var onProcessExit: (() -> Void)?

    /// Callback invoked when the terminal title changes
    var onTitleChange: ((String) -> Void)?

    private static let logger = Logger(subsystem: "com.aizen.app", category: "GhosttyTerminal")

    // MARK: - Terminal Settings from AppStorage

    @AppStorage("terminalFontName") private var terminalFontName = "Menlo"
    @AppStorage("terminalFontSize") private var terminalFontSize = 12.0
    @AppStorage("terminalBackgroundColor") private var terminalBackgroundColor = "#1e1e2e"
    @AppStorage("terminalForegroundColor") private var terminalForegroundColor = "#cdd6f4"
    @AppStorage("terminalCursorColor") private var terminalCursorColor = "#f5e0dc"
    @AppStorage("terminalSelectionBackground") private var terminalSelectionBackground = "#585b70"
    @AppStorage("terminalPalette") private var terminalPalette = "#45475a,#f38ba8,#a6e3a1,#f9e2af,#89b4fa,#f5c2e7,#94e2d5,#a6adc8,#585b70,#f37799,#89d88b,#ebd391,#74a8fc,#f2aede,#6bd7ca,#bac2de"

    /// Observation for appearance changes
    private var appearanceObservation: NSKeyValueObservation?

    // MARK: - Initialization

    /// Create a new Ghostty terminal view
    ///
    /// - Parameters:
    ///   - frame: The initial frame for the view
    ///   - worktreePath: Working directory for the terminal session
    ///   - ghosttyApp: The shared Ghostty app instance (C pointer)
    ///   - appWrapper: The Ghostty.App wrapper for surface tracking (optional)
    init(frame: NSRect, worktreePath: String, ghosttyApp: ghostty_app_t, appWrapper: Ghostty.App? = nil) {
        self.worktreePath = worktreePath
        self.ghosttyApp = ghosttyApp
        self.ghosttyAppWrapper = appWrapper

        // Use a reasonable default size if frame is zero
        let initialFrame = frame.width > 0 && frame.height > 0 ? frame : NSRect(x: 0, y: 0, width: 800, height: 600)
        super.init(frame: initialFrame)

        setupLayer()
        setupSurface()
        setupTrackingArea()
        setupAppearanceObservation()
        setupFrameObservation()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    nonisolated deinit {
        // Surface cleanup happens via Surface's deinit
        // Note: Cannot access @MainActor properties in deinit
        // Tracking areas are automatically cleaned up by NSView
        // Appearance observation is automatically invalidated

        // Surface reference cleanup needs to happen on main actor
        // We capture the values before the Task to avoid capturing self
        let wrapper = self.ghosttyAppWrapper
        let ref = self.surfaceReference
        if let wrapper = wrapper, let ref = ref {
            Task { @MainActor in
                wrapper.unregisterSurface(ref)
            }
        }
    }

    // MARK: - Setup

    /// Configure the Metal-backed layer for terminal rendering
    ///
    /// CRITICAL: Must set layer property BEFORE setting wantsLayer = true
    /// This ensures Metal rendering works correctly
    private func setupLayer() {
        // Create Metal layer
        let metalLayer = CAMetalLayer()
        metalLayer.device = MTLCreateSystemDefaultDevice()
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true

        // IMPORTANT: Set layer before wantsLayer for proper Metal initialization
        self.layer = metalLayer
        self.wantsLayer = true
        self.layerContentsRedrawPolicy = .duringViewResize

        Self.logger.debug("Metal layer configured")
    }

    /// Create and configure the Ghostty surface
    private func setupSurface() {
        guard let app = ghosttyApp else {
            Self.logger.error("Cannot create surface: ghostty_app_t is nil")
            return
        }

        // Configure surface with working directory
        var surfaceConfig = ghostty_surface_config_new()

        // CRITICAL: Set platform information
        surfaceConfig.platform_tag = GHOSTTY_PLATFORM_MACOS
        surfaceConfig.platform.macos.nsview = Unmanaged.passUnretained(self).toOpaque()

        // Set userdata
        surfaceConfig.userdata = Unmanaged.passUnretained(self).toOpaque()

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
        guard let cSurface = ghostty_surface_new(app, &surfaceConfig) else {
            Self.logger.error("ghostty_surface_new failed")
            return
        }

        // Immediately set size after creation to minimize "small grid" warnings
        let scaledSize = convertToBacking(bounds.size.width > 0 ? bounds.size : NSSize(width: 800, height: 600))
        ghostty_surface_set_size(
            cSurface,
            UInt32(scaledSize.width),
            UInt32(scaledSize.height)
        )

        // Set content scale for retina displays
        let scale = window?.backingScaleFactor ?? 1.0
        ghostty_surface_set_content_scale(cSurface, scale, scale)

        // Wrap in Swift Surface class
        self.surface = Ghostty.Surface(cSurface: cSurface)

        // Register surface with app wrapper for config update tracking
        if let wrapper = ghosttyAppWrapper {
            self.surfaceReference = wrapper.registerSurface(cSurface)
        }

        Self.logger.info("Ghostty surface created at: \(self.worktreePath)")
    }

    /// Setup mouse tracking area for the entire view
    private func setupTrackingArea() {
        let options: NSTrackingArea.Options = [
            .mouseEnteredAndExited,
            .mouseMoved,
            .inVisibleRect,
            .activeAlways  // Track even when not focused
        ]

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: options,
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }

    /// Setup observation for system appearance changes (light/dark mode)
    /// Setup appearance observation to track light/dark mode changes
    /// Implementation copied from Ghostty's SurfaceView_AppKit.swift
    private func setupAppearanceObservation() {
        appearanceObservation = observe(\.effectiveAppearance, options: [.new, .initial]) { view, change in
            guard let appearance = change.newValue else { return }
            guard let surface = view.surface?.unsafeCValue else { return }

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

    private func setupFrameObservation() {
        // Observe frame changes to resize terminal when split panes are resized
        NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: self,
            queue: .main
        ) { [weak self] _ in
            guard let self = self,
                  let surface = self.surface?.unsafeCValue else { return }

            let scaledSize = self.convertToBacking(self.bounds.size)
            ghostty_surface_set_size(
                surface,
                UInt32(scaledSize.width),
                UInt32(scaledSize.height)
            )
        }

        // Enable frame change notifications
        self.postsFrameChangedNotifications = true
    }

    // MARK: - NSView Overrides

    override var acceptsFirstResponder: Bool {
        return true
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result, let surface = surface?.unsafeCValue {
            ghostty_surface_set_focus(surface, true)
            Self.logger.debug("Terminal gained focus")
        }
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result, let surface = surface?.unsafeCValue {
            ghostty_surface_set_focus(surface, false)
            Self.logger.debug("Terminal lost focus")
        }
        return result
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        // Remove old tracking areas
        trackingAreas.forEach { removeTrackingArea($0) }

        // Recreate with current bounds
        setupTrackingArea()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()

        guard let surface = surface?.unsafeCValue else { return }

        // Update Metal layer content scale
        if let window = window {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer?.contentsScale = window.backingScaleFactor
            CATransaction.commit()
        }

        // Update surface scale factors
        let fbFrame = convertToBacking(frame)
        let xScale = fbFrame.size.width / frame.size.width
        let yScale = fbFrame.size.height / frame.size.height
        ghostty_surface_set_content_scale(surface, xScale, yScale)

        // Update surface size (framebuffer dimensions changed)
        ghostty_surface_set_size(
            surface,
            UInt32(fbFrame.size.width),
            UInt32(fbFrame.size.height)
        )
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)

        guard let surface = surface?.unsafeCValue else { return }

        // Update Ghostty with new framebuffer size
        let scaledSize = convertToBacking(NSRect(origin: .zero, size: newSize).size)
        ghostty_surface_set_size(
            surface,
            UInt32(scaledSize.width),
            UInt32(scaledSize.height)
        )
    }

    // MARK: - Keyboard Input

    override func keyDown(with event: NSEvent) {
        guard let surface = surface else {
            Self.logger.warning("keyDown: no surface")
            return
        }

        // Convert NSEvent to Ghostty key event
        var keyEvent = event.ghosttyKeyEvent(GHOSTTY_ACTION_PRESS)

        // Set text field if we have characters
        // Control characters are handled by Ghostty internally
        if let chars = event.ghosttyCharacters,
           let codepoint = chars.utf8.first,
           codepoint >= 0x20 {
            chars.withCString { textPtr in
                keyEvent.text = textPtr
                surface.sendKeyEvent(Ghostty.Input.KeyEvent(cValue: keyEvent)!)
            }
        } else {
            keyEvent.text = nil
            if let inputEvent = Ghostty.Input.KeyEvent(cValue: keyEvent) {
                surface.sendKeyEvent(inputEvent)
            }
        }
    }

    override func keyUp(with event: NSEvent) {
        guard let surface = surface else { return }

        var keyEvent = event.ghosttyKeyEvent(GHOSTTY_ACTION_RELEASE)
        keyEvent.text = nil

        if let inputEvent = Ghostty.Input.KeyEvent(cValue: keyEvent) {
            surface.sendKeyEvent(inputEvent)
        }
    }

    override func flagsChanged(with event: NSEvent) {
        guard let surface = surface?.unsafeCValue else { return }

        // Determine which modifier key changed
        let mods = Ghostty.ghosttyMods(event.modifierFlags)
        let mod: UInt32

        switch event.keyCode {
        case 0x39: mod = GHOSTTY_MODS_CAPS.rawValue
        case 0x38, 0x3C: mod = GHOSTTY_MODS_SHIFT.rawValue
        case 0x3B, 0x3E: mod = GHOSTTY_MODS_CTRL.rawValue
        case 0x3A, 0x3D: mod = GHOSTTY_MODS_ALT.rawValue
        case 0x37, 0x36: mod = GHOSTTY_MODS_SUPER.rawValue
        default: return
        }

        // Determine if press or release
        let action: ghostty_input_action_e = (mods.rawValue & mod != 0)
            ? GHOSTTY_ACTION_PRESS
            : GHOSTTY_ACTION_RELEASE

        // Send to Ghostty
        var keyEvent = event.ghosttyKeyEvent(action)
        keyEvent.text = nil
        ghostty_surface_key(surface, keyEvent)
    }

    // MARK: - Mouse Input

    override func mouseDown(with event: NSEvent) {
        guard let surface = surface else { return }

        let mouseEvent = Ghostty.Input.MouseButtonEvent(
            action: .press,
            button: .left,
            mods: Ghostty.Input.Mods(nsFlags: event.modifierFlags)
        )
        surface.sendMouseButton(mouseEvent)
    }

    override func mouseUp(with event: NSEvent) {
        guard let surface = surface else { return }

        let mouseEvent = Ghostty.Input.MouseButtonEvent(
            action: .release,
            button: .left,
            mods: Ghostty.Input.Mods(nsFlags: event.modifierFlags)
        )
        surface.sendMouseButton(mouseEvent)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let surface = surface else { return }

        let mouseEvent = Ghostty.Input.MouseButtonEvent(
            action: .press,
            button: .right,
            mods: Ghostty.Input.Mods(nsFlags: event.modifierFlags)
        )
        surface.sendMouseButton(mouseEvent)
    }

    override func rightMouseUp(with event: NSEvent) {
        guard let surface = surface else { return }

        let mouseEvent = Ghostty.Input.MouseButtonEvent(
            action: .release,
            button: .right,
            mods: Ghostty.Input.Mods(nsFlags: event.modifierFlags)
        )
        surface.sendMouseButton(mouseEvent)
    }

    override func otherMouseDown(with event: NSEvent) {
        guard event.buttonNumber == 2 else { return }
        guard let surface = surface else { return }

        let mouseEvent = Ghostty.Input.MouseButtonEvent(
            action: .press,
            button: .middle,
            mods: Ghostty.Input.Mods(nsFlags: event.modifierFlags)
        )
        surface.sendMouseButton(mouseEvent)
    }

    override func otherMouseUp(with event: NSEvent) {
        guard event.buttonNumber == 2 else { return }
        guard let surface = surface else { return }

        let mouseEvent = Ghostty.Input.MouseButtonEvent(
            action: .release,
            button: .middle,
            mods: Ghostty.Input.Mods(nsFlags: event.modifierFlags)
        )
        surface.sendMouseButton(mouseEvent)
    }

    override func mouseMoved(with event: NSEvent) {
        guard let surface = surface else { return }

        // Convert window coords to view coords
        // Ghostty expects top-left origin (y inverted from AppKit)
        let pos = convert(event.locationInWindow, from: nil)
        let mouseEvent = Ghostty.Input.MousePosEvent(
            x: pos.x,
            y: frame.height - pos.y,
            mods: Ghostty.Input.Mods(nsFlags: event.modifierFlags)
        )
        surface.sendMousePos(mouseEvent)
    }

    override func mouseDragged(with event: NSEvent) {
        // Mouse dragging is just mouse movement with a button held
        mouseMoved(with: event)
    }

    override func rightMouseDragged(with event: NSEvent) {
        mouseMoved(with: event)
    }

    override func otherMouseDragged(with event: NSEvent) {
        mouseMoved(with: event)
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)

        guard let surface = surface else { return }

        // Report mouse entering the viewport
        let pos = convert(event.locationInWindow, from: nil)
        let mouseEvent = Ghostty.Input.MousePosEvent(
            x: pos.x,
            y: frame.height - pos.y,
            mods: Ghostty.Input.Mods(nsFlags: event.modifierFlags)
        )
        surface.sendMousePos(mouseEvent)
    }

    override func mouseExited(with event: NSEvent) {
        guard let surface = surface else { return }

        // Negative values signal cursor left viewport
        let mouseEvent = Ghostty.Input.MousePosEvent(
            x: -1,
            y: -1,
            mods: Ghostty.Input.Mods(nsFlags: event.modifierFlags)
        )
        surface.sendMousePos(mouseEvent)
    }

    override func scrollWheel(with event: NSEvent) {
        guard let surface = surface else { return }

        var x = event.scrollingDeltaX
        var y = event.scrollingDeltaY
        let precision = event.hasPreciseScrollingDeltas

        if precision {
            // 2x speed multiplier for precise scrolling (trackpad)
            x *= 2
            y *= 2
        }

        let scrollEvent = Ghostty.Input.MouseScrollEvent(
            x: x,
            y: y,
            mods: Ghostty.Input.ScrollMods(
                precision: precision,
                momentum: Ghostty.Input.Momentum(event.momentumPhase)
            )
        )
        surface.sendMouseScroll(scrollEvent)
    }

    // MARK: - Process Lifecycle

    /// Check if the terminal process has exited
    var processExited: Bool {
        guard let surface = surface?.unsafeCValue else { return true }
        return ghostty_surface_process_exited(surface)
    }
}

// MARK: - NSTextInputClient Stub Implementation

/// Basic NSTextInputClient protocol conformance
///
/// This is required for IME (Input Method Editor) support for languages like Japanese, Chinese, etc.
/// Currently provides minimal stubs - full IME support can be added later
extension GhosttyTerminalView: NSTextInputClient {
    func insertText(_ string: Any, replacementRange: NSRange) {
        // TODO: Implement for IME support
        // For now, simple text insertion
        guard let text = string as? String else { return }
        surface?.sendText(text)
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        // TODO: Implement for IME preedit support
    }

    func unmarkText() {
        // TODO: Implement for IME support
    }

    func selectedRange() -> NSRange {
        // TODO: Return actual selection range from Ghostty
        return NSRange(location: NSNotFound, length: 0)
    }

    func markedRange() -> NSRange {
        // TODO: Return marked text range for IME
        return NSRange(location: NSNotFound, length: 0)
    }

    func hasMarkedText() -> Bool {
        // TODO: Track IME preedit state
        return false
    }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        // TODO: Return text from surface for IME
        return nil
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        return []
    }

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        // Return cursor position for IME window placement
        // TODO: Get actual cursor position from Ghostty
        return NSRect(x: frame.origin.x, y: frame.origin.y, width: 0, height: 0)
    }

    func characterIndex(for point: NSPoint) -> Int {
        return NSNotFound
    }
}

// MARK: - Ghostty Helpers
// Note: ghosttyMods function is defined in Ghostty.Input.swift

extension NSEvent {
    /// Create a Ghostty key event from NSEvent
    func ghosttyKeyEvent(_ action: ghostty_input_action_e) -> ghostty_input_key_s {
        var keyEvent = ghostty_input_key_s()
        keyEvent.action = action
        keyEvent.keycode = UInt32(keyCode)
        keyEvent.mods = Ghostty.ghosttyMods(modifierFlags)
        keyEvent.consumed_mods = Ghostty.ghosttyMods(
            modifierFlags.subtracting([.control, .command])
        )

        // Unshifted codepoint for key identification
        if type == .keyDown || type == .keyUp,
           let chars = characters(byApplyingModifiers: []),
           let codepoint = chars.unicodeScalars.first {
            keyEvent.unshifted_codepoint = codepoint.value
        } else {
            keyEvent.unshifted_codepoint = 0
        }

        keyEvent.text = nil
        keyEvent.composing = false

        return keyEvent
    }

    /// Get characters appropriate for Ghostty (excluding control chars and PUA)
    var ghosttyCharacters: String? {
        guard let characters = characters else { return nil }

        if characters.count == 1,
           let scalar = characters.unicodeScalars.first {
            // Skip control characters (Ghostty handles internally)
            if scalar.value < 0x20 {
                return self.characters(byApplyingModifiers: modifierFlags.subtracting(.control))
            }

            // Skip Private Use Area (function keys)
            if scalar.value >= 0xF700 && scalar.value <= 0xF8FF {
                return nil
            }
        }

        return characters
    }
}
