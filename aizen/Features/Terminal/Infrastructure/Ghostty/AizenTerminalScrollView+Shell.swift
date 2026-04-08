import AppKit

extension AizenTerminalScrollView {
    // The entire bounds is a safe area, so we override any default
    // insets. This is necessary for the content view to match the
    // surface view if we have the "hidden" titlebar style.
    override var safeAreaInsets: NSEdgeInsets { return NSEdgeInsetsZero }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        guard window != nil else { return }

        DispatchQueue.main.async { [weak self] in
            self?.synchronizeForHostUpdate()
        }
    }

    override func layout() {
        super.layout()

        scrollView.frame = bounds
        surfaceView.frame.size = scrollView.bounds.size
        documentView.frame.size.width = scrollView.bounds.width

        synchronizeScrollView()
        synchronizeSurfaceView()
        synchronizeCoreSurface()
    }

    override func mouseMoved(with: NSEvent) {
        guard NSScroller.preferredScrollerStyle == .legacy else { return }
        scrollView.flashScrollers()
    }

    override func updateTrackingAreas() {
        trackingAreas.forEach { removeTrackingArea($0) }

        super.updateTrackingAreas()

        guard let scroller = scrollView.verticalScroller else { return }
        addTrackingArea(NSTrackingArea(
            rect: convert(scroller.bounds, from: scroller),
            options: [
                .mouseMoved,
                .activeInKeyWindow,
            ],
            owner: self,
            userInfo: nil))
    }
}
