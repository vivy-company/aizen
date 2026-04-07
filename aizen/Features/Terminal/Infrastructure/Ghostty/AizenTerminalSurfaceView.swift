import AppKit
import Combine
import SwiftUI
import CoreText
import GhosttyKit
import OSLog

typealias OSView = NSView

@MainActor
final class SearchState: ObservableObject {
    @Published var needle: String
    @Published var total: UInt?
    @Published var selected: UInt?

    init(needle: String = "", total: UInt? = nil, selected: UInt? = nil) {
        self.needle = needle
        self.total = total
        self.selected = selected
    }
}

extension Ghostty {
    /// The NSView implementation for a terminal surface.
    class SurfaceView: OSView, ObservableObject, Identifiable {
        typealias ID = UUID
        static let logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "win.aizen.app",
            category: "GhosttySurfaceView"
        )

        /// Unique ID per surface
        let id: UUID

        // The current title of the surface as defined by the pty. This can be
        // changed with escape codes. This is public because the callbacks go
        // to the app level and it is set from there.
        @Published private(set) var title: String = "" {
            didSet {
                if !title.isEmpty {
                    titleFallbackTimer?.invalidate()
                    titleFallbackTimer = nil
                }
            }
        }

        // The current pwd of the surface as defined by the pty. This can be
        // changed with escape codes.
        @Published var pwd: String?

        // The cell size of this surface. This is set by the core when the
        // surface is first created and any time the cell size changes (i.e.
        // when the font size changes). This is used to allow windows to be
        // resized in discrete steps of a single cell.
        @Published var cellSize: NSSize = .zero

        // The health state of the surface. This currently only reflects the
        // renderer health. In the future we may want to make this an enum.
        @Published var healthy: Bool = true

        // Any error while initializing the surface.
        @Published var error: Error?

        // The hovered URL string
        @Published var hoverUrl: String?

        // The progress report (if any)
        @Published var progressReport: Action.ProgressReport? {
            didSet {
                // Cancel any existing timer
                progressReportTimer?.invalidate()
                progressReportTimer = nil

                // If we have a new progress report, start a timer to remove it after 15 seconds
                if progressReport != nil {
                    progressReportTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: false) { [weak self] _ in
                        self?.progressReport = nil
                        self?.progressReportTimer = nil
                    }
                }
            }
        }

        // The currently active key sequence. The sequence is not active if this is empty.
        @Published var keySequence: [KeyboardShortcut] = []

        // The currently active key tables. Empty if no tables are active.
        @Published var keyTables: [String] = []

        // The current search state. When non-nil, the search overlay should be shown.
        @Published var searchState: SearchState? {
            didSet {
                if let searchState {
                    // I'm not a Combine expert so if there is a better way to do this I'm
                    // all ears. What we're doing here is grabbing the latest needle. If the
                    // needle is less than 3 chars, we debounce it for a few hundred ms to
                    // avoid kicking off expensive searches.
                    searchNeedleCancellable = searchState.$needle
                        .removeDuplicates()
                        .map { needle -> AnyPublisher<String, Never> in
                            if needle.isEmpty || needle.count >= 3 {
                                return Just(needle).eraseToAnyPublisher()
                            } else {
                                return Just(needle)
                                    .delay(for: .milliseconds(300), scheduler: DispatchQueue.main)
                                    .eraseToAnyPublisher()
                            }
                        }
                        .switchToLatest()
                        .sink { [weak self] needle in
                            guard let surface = self?.surface else { return }
                            let action = "search:\(needle)"
                            ghostty_surface_binding_action(surface, action, UInt(action.lengthOfBytes(using: .utf8)))
                        }
                } else if oldValue != nil {
                    searchNeedleCancellable = nil
                    guard let surface = self.surface else { return }
                    let action = "end_search"
                    ghostty_surface_binding_action(surface, action, UInt(action.lengthOfBytes(using: .utf8)))
                }
            }
        }

        // Cancellable for search state needle changes
        private var searchNeedleCancellable: AnyCancellable?

        // The time this surface last became focused. This is a ContinuousClock.Instant
        // on supported platforms.
        @Published var focusInstant: ContinuousClock.Instant?

        // Returns sizing information for the surface. This is the raw C
        // structure because I'm lazy.
        @Published var surfaceSize: ghostty_surface_size_s?

        // Whether the pointer should be visible or not
        @Published private(set) var pointerStyle: CursorStyle = .horizontalText

        // Whether the mouse is currently over this surface
        @Published var mouseOverSurface: Bool = false

        // The last known mouse location in the surface's local coordinate space,
        // used by overlays such as the split drag handle reveal region.
        @Published var mouseLocationInSurface: CGPoint?

        // Whether the cursor is currently visible (not hidden by typing, etc.)
        @Published private(set) var cursorVisible: Bool = true

        /// The configuration derived from the Ghostty config so we don't need to rely on references.
        @Published var derivedConfig: DerivedConfig

        /// The background color within the color palette of the surface. This is only set if it is
        /// dynamically updated. Otherwise, the background color is the default background color.
        @Published var backgroundColor: Color?

        /// True when the bell is active. This is set inactive on focus or event.
        @Published var bell: Bool = false

        /// True when the surface is in readonly mode.
        @Published var readonly: Bool = false

        /// True when the surface should show a highlight effect (e.g., when presented via goto_split).
        @Published var highlighted: Bool = false

        // An initial size to request for a window. This will only affect
        // then the view is moved to a new window.
        var initialSize: NSSize?

        // A content size received through sizeDidChange that may in some cases
        // be different from the frame size.
        private var contentSizeBacking: NSSize?
        var contentSize: NSSize {
            get { return contentSizeBacking ?? frame.size }
            set { contentSizeBacking = newValue }
        }

        // Set whether the surface is currently on a password input or not. This is
        // detected with the set_password_input_cb on the Ghostty state.
        var passwordInput: Bool = false {
            didSet {
                // We need to update our state within the SecureInput manager.
                let input = SecureInput.shared
                let id = ObjectIdentifier(self)
                if passwordInput {
                    input.setScoped(id, focused: focused)
                } else {
                    input.removeScoped(id)
                }
            }
        }

        // Returns true if quit confirmation is required for this surface to
        // exit safely.
        var needsConfirmQuit: Bool {
            guard let surface = self.surface else { return false }
            return ghostty_surface_needs_confirm_quit(surface)
        }

        // Returns true if the process in this surface has exited.
        var processExited: Bool {
            guard let surface = self.surface else { return true }
            return ghostty_surface_process_exited(surface)
        }

        // Returns the inspector instance for this surface, or nil if the
        // surface has been closed or no inspector is active.
        var inspector: Ghostty.Inspector? {
            guard let surface = self.surface else { return nil }
            guard let cInspector = ghostty_surface_inspector(surface) else { return nil }
            return Ghostty.Inspector(cInspector: cInspector)
        }

        // True if the inspector should be visible
        @Published var inspectorVisible: Bool = false {
            didSet {
                if oldValue && !inspectorVisible {
                    guard let surface = self.surface else { return }
                    ghostty_inspector_free(surface)
                }
            }
        }

        /// Returns the data model for this surface.
        ///
        /// Note: eventually, all surface access will be through this, but presently its in a transition
        /// state so we're mixing this with direct surface access.
        private(set) var surfaceModel: Ghostty.Surface?

        /// Returns the underlying C value for the surface. See "note" on surfaceModel.
        var surface: ghostty_surface_t? {
            surfaceModel?.unsafeCValue
        }
        /// Current scrollbar state, cached here for persistence across rebuilds
        /// of the SwiftUI view hierarchy, for example when changing splits
        var scrollbar: Ghostty.Action.Scrollbar?

        // Notification identifiers associated with this surface
        var notificationIdentifiers: Set<String> = []

        var markedText: NSMutableAttributedString
        private(set) var focused: Bool = false

        /// Monotonic counter incremented every time any surface becomes first
        /// responder.  ``Ghostty.moveFocus`` captures this at dispatch time and
        /// skips execution when it has changed, preventing stale async focus
        /// requests from stealing focus after a user click.
        static var focusChangeCounter: Int = 0
        var prevPressureStage: Int = 0
        private var appearanceObserver: NSKeyValueObservation?

        // This is set to non-null during keyDown to accumulate insertText contents
        var keyTextAccumulator: [String]?

        // True when we've consumed a left mouse-down only to move focus and
        // should suppress the matching mouse-up from being reported.
        var suppressNextLeftMouseUp: Bool = false

        // A small delay that is introduced before a title change to avoid flickers
        private var titleChangeTimer: Timer?

        // A timer to fallback to ghost emoji if no title is set within the grace period
        private var titleFallbackTimer: Timer?

        // Timer to remove progress report after 15 seconds
        private var progressReportTimer: Timer?

        // This is the title from the terminal. This is nil if we're currently using
        // the terminal title as the main title property. If the title is set manually
        // by the user, this is set to the prior value (which may be empty, but non-nil).
        private var titleFromTerminal: String?

        // The cached contents of the screen.
        private(set) var cachedScreenContents: CachedValue<String>
        private(set) var cachedVisibleContents: CachedValue<String>

        /// Event monitor (see individual events for why)
        private var eventMonitor: Any?

        // We need to support being a first responder so that we can get input events
        override var acceptsFirstResponder: Bool { return true }

        init(_ app: ghostty_app_t, baseConfig: SurfaceConfiguration? = nil, uuid: UUID? = nil) {
            self.markedText = NSMutableAttributedString()
            self.id = uuid ?? .init()

            // Our initial config always is our application wide config.
            self.derivedConfig = DerivedConfig()

            // We need to initialize this so it does something but we want to set
            // it back up later so we can reference `self`. This is a hack we should
            // fix at some point.
            self.cachedScreenContents = .init(duration: .milliseconds(500)) { "" }
            self.cachedVisibleContents = self.cachedScreenContents

            // Initialize with some default frame size. The important thing is that this
            // is non-zero so that our layer bounds are non-zero so that our renderer
            // can do SOMETHING.
            super.init(frame: NSRect(x: 0, y: 0, width: 800, height: 600))

            // Our cache of screen data
            cachedScreenContents = .init(duration: .milliseconds(500)) { [weak self] in
                guard let self else { return "" }
                guard let surface = self.surface else { return "" }
                var text = ghostty_text_s()
                let sel = ghostty_selection_s(
                    top_left: ghostty_point_s(
                        tag: GHOSTTY_POINT_SCREEN,
                        coord: GHOSTTY_POINT_COORD_TOP_LEFT,
                        x: 0,
                        y: 0),
                    bottom_right: ghostty_point_s(
                        tag: GHOSTTY_POINT_SCREEN,
                        coord: GHOSTTY_POINT_COORD_BOTTOM_RIGHT,
                        x: 0,
                        y: 0),
                    rectangle: false)
                guard ghostty_surface_read_text(surface, sel, &text) else { return "" }
                defer { ghostty_surface_free_text(surface, &text) }
                return String(cString: text.text)
            }
            cachedVisibleContents = .init(duration: .milliseconds(500)) { [weak self] in
                guard let self else { return "" }
                guard let surface = self.surface else { return "" }
                var text = ghostty_text_s()
                let sel = ghostty_selection_s(
                    top_left: ghostty_point_s(
                        tag: GHOSTTY_POINT_VIEWPORT,
                        coord: GHOSTTY_POINT_COORD_TOP_LEFT,
                        x: 0,
                        y: 0),
                    bottom_right: ghostty_point_s(
                        tag: GHOSTTY_POINT_VIEWPORT,
                        coord: GHOSTTY_POINT_COORD_BOTTOM_RIGHT,
                        x: 0,
                        y: 0),
                    rectangle: false)
                guard ghostty_surface_read_text(surface, sel, &text) else { return "" }
                defer { ghostty_surface_free_text(surface, &text) }
                return String(cString: text.text)
            }

            // Set a timer to show the ghost emoji after 500ms if no title is set
            titleFallbackTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                if let self = self, self.title.isEmpty {
                    self.title = "👻"
                }
            }

            // Before we initialize the surface we want to register our notifications
            // so there is no window where we can't receive them.
            let center = NotificationCenter.default
            center.addObserver(
                self,
                selector: #selector(onUpdateRendererHealth),
                name: Ghostty.Notification.didUpdateRendererHealth,
                object: self)
            center.addObserver(
                self,
                selector: #selector(ghosttyDidContinueKeySequence),
                name: Ghostty.Notification.didContinueKeySequence,
                object: self)
            center.addObserver(
                self,
                selector: #selector(ghosttyDidEndKeySequence),
                name: Ghostty.Notification.didEndKeySequence,
                object: self)
            center.addObserver(
                self,
                selector: #selector(ghosttyDidChangeKeyTable),
                name: Ghostty.Notification.didChangeKeyTable,
                object: self)
            center.addObserver(
                self,
                selector: #selector(ghosttyConfigDidChange(_:)),
                name: .ghosttyConfigDidChange,
                object: self)
            center.addObserver(
                self,
                selector: #selector(ghosttyColorDidChange(_:)),
                name: .ghosttyColorDidChange,
                object: self)
            center.addObserver(
                self,
                selector: #selector(ghosttyBellDidRing(_:)),
                name: .ghosttyBellDidRing,
                object: self)
            center.addObserver(
                self,
                selector: #selector(ghosttyDidChangeReadonly(_:)),
                name: .ghosttyDidChangeReadonly,
                object: self)
            center.addObserver(
                self,
                selector: #selector(windowDidChangeScreen),
                name: NSWindow.didChangeScreenNotification,
                object: nil)

            // Listen for local events that we need to know of outside of
            // single surface handlers.
            self.eventMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [
                    // We need keyUp because command+key events don't trigger keyUp.
                    .keyUp,

                    // We need leftMouseDown to determine if we should focus ourselves
                    // when the app/window isn't in focus. We do this instead of
                    // "acceptsFirstMouse" because that forces us to also handle the
                    // event and encode the event to the pty which we want to avoid.
                    // (Issue 2595)
                    .leftMouseDown,
                ]
            ) { [weak self] event in self?.localEventHandler(event) }

            // Setup our surface. This will also initialize all the terminal IO.
            let surface_cfg = baseConfig ?? SurfaceConfiguration()
            let surface = surface_cfg.withCValue(view: self) { surface_cfg_c in
                ghostty_surface_new(app, &surface_cfg_c)
            }
            guard let surface = surface else {
                self.error = NSError(domain: "Ghostty", code: 1)
                return
            }
            self.surfaceModel = Ghostty.Surface(cSurface: surface)

            // Setup our tracking area so we get mouse moved events
            updateTrackingAreas()

            // The UTTypes that can be dragged onto this view.
            registerForDraggedTypes(Array(Self.dropTypes))
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not supported for this view")
        }

        deinit {
            // Remove all of our notificationcenter subscriptions
            let center = NotificationCenter.default
            center.removeObserver(self)

            // Remove our event monitor
            if let eventMonitor {
                NSEvent.removeMonitor(eventMonitor)
            }

            trackingAreas.forEach { removeTrackingArea($0) }

            // Remove ourselves from secure input if we have to
            SecureInput.shared.removeScoped(ObjectIdentifier(self))

            // Cancel progress report timer
            progressReportTimer?.invalidate()
        }

        func focusDidChange(_ focused: Bool) {
            guard let surface = self.surface else { return }
            guard self.focused != focused else { return }
            self.focused = focused

            // If we lost our focus then remove the mouse event suppression so
            // our mouse release event leaving the surface can properly be
            // sent to stop things like mouse selection.
            if !focused {
                suppressNextLeftMouseUp = false
            }

            // Notify libghostty
            ghostty_surface_set_focus(surface, focused)

            // Update our secure input state if we are a password input
            if passwordInput {
                SecureInput.shared.setScoped(ObjectIdentifier(self), focused: focused)
            }

            if focused {
                // On macOS 13+ we can store our continuous clock...
                focusInstant = ContinuousClock.now

                // We unset our bell state if we gained focus
                bell = false

            }
        }

        func sizeDidChange(_ size: CGSize) {
            // Ghostty wants to know the actual framebuffer size... It is very important
            // here that we use "size" and NOT the view frame. If we're in the middle of
            // an animation (i.e. a fullscreen animation), the frame will not yet be updated.
            // The size represents our final size we're going for.
            let scaledSize = self.convertToBacking(size)
            setSurfaceSize(width: UInt32(scaledSize.width), height: UInt32(scaledSize.height))
            // Store this size so we can reuse it when backing properties change
            contentSize = size
        }

        func setSurfaceSize(width: UInt32, height: UInt32) {
            guard let surface = self.surface else { return }

            // Update our core surface
            ghostty_surface_set_size(surface, width, height)

            // Update our cached size metrics
            let size = ghostty_surface_size(surface)
            DispatchQueue.main.async {
                // DispatchQueue required since this may be called by SwiftUI off
                // the main thread and Published changes need to be on the main
                // thread. This caused a crash on macOS <= 14.
                self.surfaceSize = size
            }
        }

        func setCursorShape(_ shape: ghostty_action_mouse_shape_e) {
            switch shape {
            case GHOSTTY_MOUSE_SHAPE_DEFAULT:
                pointerStyle = .default

            case GHOSTTY_MOUSE_SHAPE_TEXT:
                pointerStyle = .horizontalText

            case GHOSTTY_MOUSE_SHAPE_GRAB:
                pointerStyle = .grabIdle

            case GHOSTTY_MOUSE_SHAPE_GRABBING:
                pointerStyle = .grabActive

            case GHOSTTY_MOUSE_SHAPE_POINTER:
                pointerStyle = .link

            case GHOSTTY_MOUSE_SHAPE_W_RESIZE:
                pointerStyle = .resizeLeft

            case GHOSTTY_MOUSE_SHAPE_E_RESIZE:
                pointerStyle = .resizeRight

            case GHOSTTY_MOUSE_SHAPE_N_RESIZE:
                pointerStyle = .resizeUp

            case GHOSTTY_MOUSE_SHAPE_S_RESIZE:
                pointerStyle = .resizeDown

            case GHOSTTY_MOUSE_SHAPE_NS_RESIZE:
                pointerStyle = .resizeUpDown

            case GHOSTTY_MOUSE_SHAPE_EW_RESIZE:
                pointerStyle = .resizeLeftRight

            case GHOSTTY_MOUSE_SHAPE_VERTICAL_TEXT:
                pointerStyle = .verticalText

            case GHOSTTY_MOUSE_SHAPE_CONTEXT_MENU:
                pointerStyle = .contextMenu

            case GHOSTTY_MOUSE_SHAPE_CROSSHAIR:
                pointerStyle = .crosshair

            case GHOSTTY_MOUSE_SHAPE_NOT_ALLOWED:
                pointerStyle = .operationNotAllowed

            default:
                // We ignore unknown shapes.
                return
            }
        }

        func setCursorVisibility(_ visible: Bool) {
            cursorVisible = visible
            // Technically this action could be called anytime we want to
            // change the mouse visibility but at the time of writing this
            // mouse-hide-while-typing is the only use case so this is the
            // preferred method.
            NSCursor.setHiddenUntilMouseMoves(!visible)
        }

        /// Set the title by prompting the user.
        func promptTitle() {
            // Create an alert dialog
            let alert = NSAlert()
            alert.messageText = "Change Terminal Title"
            alert.informativeText = "Leave blank to restore the default."
            alert.alertStyle = .informational

            // Add a text field to the alert
            let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 250, height: 24))
            textField.stringValue = title
            alert.accessoryView = textField

            // Add buttons
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Cancel")

            // Make the text field the first responder so it gets focus
            alert.window.initialFirstResponder = textField

            let completionHandler: (NSApplication.ModalResponse) -> Void = { [weak self] response in
                guard let self else { return }

                // Check if the user clicked "OK"
                guard response == .alertFirstButtonReturn  else { return }

                // Get the input text
                let newTitle = textField.stringValue
                if newTitle.isEmpty {
                    // Empty means that user wants the title to be set automatically
                    // We also need to reload the config for the "title" property to be
                    // used again by this tab.
                    let prevTitle = titleFromTerminal ?? "👻"
                    titleFromTerminal = nil
                    setTitle(prevTitle)
                } else {
                    // Set the title and prevent it from being changed automatically
                    titleFromTerminal = title
                    title = newTitle
                }
            }

            // We prefer to run our alert in a sheet modal if we have a window.
            if let window {
                alert.beginSheetModal(for: window, completionHandler: completionHandler)
            } else {
                // On macOS 26 RC, this codepath results in the "OK" button not being
                // visible. The above codepath should be taken most times but I'm just
                // noting this as something I noticed consistently.
                completionHandler(alert.runModal())
            }
        }

        func setTitle(_ title: String) {
            // This fixes an issue where very quick changes to the title could
            // cause an unpleasant flickering. We set a timer so that we can
            // coalesce rapid changes. The timer is short enough that it still
            // feels "instant".
            titleChangeTimer?.invalidate()
            titleChangeTimer = Timer.scheduledTimer(
                withTimeInterval: 0.075,
                repeats: false
            ) { [weak self] _ in
                // Set the title if it wasn't manually set.
                guard self?.titleFromTerminal == nil else {
                    self?.titleFromTerminal = title
                    return
                }
                self?.title = title
            }
        }

        // MARK: - NSView

        override func becomeFirstResponder() -> Bool {
            let result = super.becomeFirstResponder()
            if result {
                Self.focusChangeCounter &+= 1
                focusDidChange(true)
            }
            return result
        }

        override func resignFirstResponder() -> Bool {
            let result = super.resignFirstResponder()

            // We sometimes call this manually (see SplitView) as a way to force us to
            // yield our focus state.
            if result { focusDidChange(false) }

            return result
        }

        override func updateTrackingAreas() {
            // To update our tracking area we just recreate it all.
            trackingAreas.forEach { removeTrackingArea($0) }

            // This tracking area is across the entire frame to notify us of mouse movements.
            addTrackingArea(NSTrackingArea(
                rect: frame,
                options: [
                    .mouseEnteredAndExited,
                    .mouseMoved,

                    // Only send mouse events that happen in our visible (not obscured) rect
                    .inVisibleRect,

                    // We want active always because we want to still send mouse reports
                    // even if we're not focused or key.
                    .activeAlways,
                ],
                owner: self,
                userInfo: nil))
        }

        override func viewDidChangeBackingProperties() {
            super.viewDidChangeBackingProperties()

            // The Core Animation compositing engine uses the layer's contentsScale property
            // to determine whether to scale its contents during compositing. When the window
            // moves between a high DPI display and a low DPI display, or the user modifies
            // the DPI scaling for a display in the system settings, this can result in the
            // layer being scaled inappropriately. Since we handle the adjustment of scale
            // and resolution ourselves below, we update the layer's contentsScale property
            // to match the window's backingScaleFactor, so as to ensure it is not scaled by
            // the compositor.
            //
            // Ref: High Resolution Guidelines for OS X
            // https://developer.apple.com/library/archive/documentation/GraphicsAnimation/Conceptual/HighResolutionOSX/CapturingScreenContents/CapturingScreenContents.html#//apple_ref/doc/uid/TP40012302-CH10-SW27
            if let window = window {
                CATransaction.begin()
                // Disable the implicit transition animation that Core Animation applies to
                // property changes. Otherwise it will apply a scale animation to the layer
                // contents which looks pretty janky.
                CATransaction.setDisableActions(true)
                layer?.contentsScale = window.backingScaleFactor
                CATransaction.commit()
            }

            guard let surface = self.surface else { return }

            // Detect our X/Y scale factor so we can update our surface
            let fbFrame = self.convertToBacking(self.frame)
            let xScale = fbFrame.size.width / self.frame.size.width
            let yScale = fbFrame.size.height / self.frame.size.height
            ghostty_surface_set_content_scale(surface, xScale, yScale)

            // When our scale factor changes, so does our fb size so we send that too
            let scaledSize = self.convertToBacking(contentSize)
            setSurfaceSize(width: UInt32(scaledSize.width), height: UInt32(scaledSize.height))
        }

        override func keyDown(with event: NSEvent) {
            guard let surface = self.surface else {
                self.interpretKeyEvents([event])
                return
            }

            // On any keyDown event we unset our bell state
            bell = false

            // We need to translate the mods (maybe) to handle configs such as option-as-alt
            let translationModsGhostty = Ghostty.eventModifierFlags(
                mods: ghostty_surface_key_translation_mods(
                    surface,
                    Ghostty.ghosttyMods(event.modifierFlags)
                )
            )

            // There are hidden bits set in our event that matter for certain dead keys
            // so we can't use translationModsGhostty directly. Instead, we just check
            // for exact states and set them.
            var translationMods = event.modifierFlags
            for flag in [NSEvent.ModifierFlags.shift, .control, .option, .command] {
                if translationModsGhostty.contains(flag) {
                    translationMods.insert(flag)
                } else {
                    translationMods.remove(flag)
                }
            }

            // If the translation modifiers are not equal to our original modifiers
            // then we need to construct a new NSEvent. If they are equal we reuse the
            // old one. IMPORTANT: we MUST reuse the old event if they're equal because
            // this keeps things like Korean input working. There must be some object
            // equality happening in AppKit somewhere because this is required.
            let translationEvent: NSEvent
            if translationMods == event.modifierFlags {
                translationEvent = event
            } else {
                translationEvent = NSEvent.keyEvent(
                    with: event.type,
                    location: event.locationInWindow,
                    modifierFlags: translationMods,
                    timestamp: event.timestamp,
                    windowNumber: event.windowNumber,
                    context: nil,
                    characters: event.characters(byApplyingModifiers: translationMods) ?? "",
                    charactersIgnoringModifiers: event.charactersIgnoringModifiers ?? "",
                    isARepeat: event.isARepeat,
                    keyCode: event.keyCode
                ) ?? event
            }

            let action = event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS

            // By setting this to non-nil, we note that we're in a keyDown event. From here,
            // we call interpretKeyEvents so that we can handle complex input such as Korean
            // language.
            keyTextAccumulator = []
            defer { keyTextAccumulator = nil }

            // We need to know what the length of marked text was before this event to
            // know if these events cleared it.
            let markedTextBefore = markedText.length > 0

            // We need to know the keyboard layout before below because some keyboard
            // input events will change our keyboard layout and we don't want those
            // going to the terminal.
            let keyboardIdBefore: String? = if !markedTextBefore {
                KeyboardLayout.id
            } else {
                nil
            }

            // If we are in a keyDown then we don't need to redispatch a command-modded
            // key event (see docs for this field) so reset this to nil because
            // `interpretKeyEvents` may dispatch it.
            self.lastPerformKeyEvent = nil

            self.interpretKeyEvents([translationEvent])

            // If our keyboard changed from this we just assume an input method
            // grabbed it and do nothing.
            if !markedTextBefore && keyboardIdBefore != KeyboardLayout.id {
                return
            }

            // If we have marked text, we're in a preedit state. The order we
            // do this and the key event callbacks below doesn't matter since
            // we control the preedit state only through the preedit API.
            syncPreedit(clearIfNeeded: markedTextBefore)

            if let list = keyTextAccumulator, list.count > 0 {
                // If we have text, then we've composed a character, send that down.
                // These never have "composing" set to true because these are the
                // result of a composition.
                for text in list {
                    _ = keyAction(
                        action,
                        event: event,
                        translationEvent: translationEvent,
                        text: text
                    )
                }
            } else {
                // We have no accumulated text so this is a normal key event.
                _ = keyAction(
                    action,
                    event: event,
                    translationEvent: translationEvent,
                    text: translationEvent.ghosttyCharacters,

                    // We're composing if we have preedit (the obvious case). But we're also
                    // composing if we don't have preedit and we had marked text before,
                    // because this input probably just reset the preedit state. It shouldn't
                    // be encoded. Example: Japanese begin composing, the press backspace.
                    // This should only cancel the composing state but not actually delete
                    // the prior input characters (prior to the composing).
                    composing: markedText.length > 0 || markedTextBefore
                )
            }
        }

        /// Records the timestamp of the last event to performKeyEquivalent that we need to save.
        /// We currently save all commands with command or control set.
        ///
        /// For command+key inputs, the AppKit input stack calls performKeyEquivalent to give us a chance
        /// to handle them first. If we return "false" then it goes through the standard AppKit responder chain.
        /// For an NSTextInputClient, that may redirect some commands _before_ our keyDown gets called.
        /// Concretely: Command+Period will do: performKeyEquivalent, doCommand ("cancel:"). In doCommand,
        /// we need to know that we actually want to handle that in keyDown, so we send it back through the
        /// event dispatch system and use this timestamp as an identity to know to actually send it to keyDown.
        ///
        /// Why not send it to keyDown always? Because if the user rebinds a command to something we
        /// actually handle then we do want the standard response chain to handle the key input. Unfortunately,
        /// we can't know what a command is bound to at a system level until we let it flow through the system.
        /// That's the crux of the problem.
        ///
        /// So, we have to send it back through if we didn't handle it.
        ///
        /// The next part of the problem is comparing NSEvent identity seems pretty nasty. I couldn't
        /// find a good way to do it. I originally stored a weak ref and did identity comparison but that
        /// doesn't work and for reasons I couldn't figure out the value gets mangled (fields don't match
        /// before/after the assignment). I suspect it has something to do with the fact an NSEvent is wrapping
        /// a lower level event pointer and its just not surviving the Swift runtime somehow. I don't know.
        ///
        /// The best thing I could find was to store the event timestamp which has decent granularity
        /// and compare that. To further complicate things, some events are synthetic and have a zero
        /// timestamp so we have to protect against that. Fun!
        var lastPerformKeyEvent: TimeInterval?

        struct DerivedConfig {
            enum Scrollbar {
                case system
                case never
            }

            let backgroundColor: Color
            let backgroundOpacity: Double
            let macosWindowShadow: Bool
            let windowTitleFontFamily: String?
            let windowAppearance: NSAppearance?
            let scrollbar: Scrollbar

            init() {
                self.backgroundColor = Color(NSColor.windowBackgroundColor)
                self.backgroundOpacity = 1
                self.macosWindowShadow = true
                self.windowTitleFontFamily = nil
                self.windowAppearance = nil
                self.scrollbar = .system
            }
        }
    }
}

@MainActor
final class AizenTerminalSurfaceView: Ghostty.SurfaceView {
    let paneId: String
    weak var ghosttyAppWrapper: Ghostty.App?
    var surfaceReference: Ghostty.SurfaceReference?
    var onProcessExit: (() -> Void)?
    var onFocus: (() -> Void)?
    var onTitleChange: ((String) -> Void)?
    var onReady: (() -> Void)?
    var onProgressReport: ((GhosttyProgressState, Int?) -> Void)?
    var didSignalReady = false

    init(
        frame: NSRect,
        worktreePath: String,
        ghosttyApp: ghostty_app_t,
        appWrapper: Ghostty.App? = nil,
        paneId: String? = nil,
        command: String? = nil
    ) {
        var config = Ghostty.SurfaceConfiguration()
        config.workingDirectory = worktreePath
        config.initialInput = if let command, !command.isEmpty { command + "\n" } else { nil }
        self.paneId = paneId ?? UUID().uuidString
        self.ghosttyAppWrapper = appWrapper
        super.init(ghosttyApp, baseConfig: config)

        let initialFrame = if frame.width > 0 && frame.height > 0 {
            frame
        } else {
            NSRect(x: 0, y: 0, width: 800, height: 600)
        }
        self.frame = initialFrame

        if let surface, let appWrapper {
            self.surfaceReference = appWrapper.registerSurface(surface)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        let appWrapper = ghosttyAppWrapper
        let surfaceReference = surfaceReference
        if let appWrapper, let surfaceReference {
            Task { @MainActor in
                appWrapper.unregisterSurface(surfaceReference)
            }
        }
    }

    override func focusDidChange(_ focused: Bool) {
        super.focusDidChange(focused)
        if focused {
            onFocus?()
        }
    }

    /// Keep Ghostty's per-surface focus state in sync with Aizen's pane selection
    /// even when AppKit responder transitions are delayed or skipped.
    func setGhosttyFocused(_ focused: Bool) {
        super.focusDidChange(focused)
    }

    func startSearch(_ startSearch: Ghostty.Action.StartSearch) {
        if let searchState {
            searchState.needle = startSearch.needle ?? ""
        } else {
            searchState = SearchState(needle: startSearch.needle ?? "")
            NotificationCenter.default.post(name: .ghosttySearchFocus, object: self)
        }
    }

    func updateSearchTotal(_ total: Int) {
        searchState?.total = total >= 0 ? UInt(total) : nil
    }

    func updateSearchSelected(_ selected: Int) {
        searchState?.selected = selected >= 0 ? UInt(selected) : nil
    }

    func endSearchFromGhostty() {
        searchState = nil
    }

    func showResizeOverlay() {
    }
}
