import AppKit
import Combine
import SwiftUI
import CoreText
import GhosttyKit
import OSLog

typealias OSView = NSView

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
        @Published var title: String = "" {
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
        @Published var pointerStyle: CursorStyle = .horizontalText

        // Whether the mouse is currently over this surface
        @Published var mouseOverSurface: Bool = false

        // The last known mouse location in the surface's local coordinate space,
        // used by overlays such as the split drag handle reveal region.
        @Published var mouseLocationInSurface: CGPoint?

        // Whether the cursor is currently visible (not hidden by typing, etc.)
        @Published var cursorVisible: Bool = true

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
        var focused: Bool = false

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
        var titleChangeTimer: Timer?

        // A timer to fallback to ghost emoji if no title is set within the grace period
        private var titleFallbackTimer: Timer?

        // Timer to remove progress report after 15 seconds
        private var progressReportTimer: Timer?

        // This is the title from the terminal. This is nil if we're currently using
        // the terminal title as the main title property. If the title is set manually
        // by the user, this is set to the prior value (which may be empty, but non-nil).
        var titleFromTerminal: String?

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

            if !focused {
                suppressNextLeftMouseUp = false
            }

            ghostty_surface_set_focus(surface, focused)

            if passwordInput {
                SecureInput.shared.setScoped(ObjectIdentifier(self), focused: focused)
            }

            if focused {
                focusInstant = ContinuousClock.now
                bell = false
            }
        }

        // MARK: - NSView

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

    func showResizeOverlay() {
    }
}
