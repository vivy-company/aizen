import AppKit
import SwiftUI

struct AizenTerminalRootContainer<Content: View>: NSViewRepresentable {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeNSView(context: Context) -> AizenTerminalRootContainerView<Content> {
        AizenTerminalRootContainerView(rootView: content)
    }

    func updateNSView(_ nsView: AizenTerminalRootContainerView<Content>, context: Context) {
        nsView.update(rootView: content)
    }
}

final class AizenTerminalRootContainerView<Content: View>: NSView {
    private let clipView = NSView()
    private let hostingView: NSHostingView<Content>
    private var topConstraint: NSLayoutConstraint?
    private var leadingConstraint: NSLayoutConstraint?
    private var bottomConstraint: NSLayoutConstraint?
    private var trailingConstraint: NSLayoutConstraint?
    private var lastBottomInset: CGFloat = 0

    init(rootView: Content) {
        self.hostingView = NSHostingView(rootView: rootView)
        super.init(frame: .zero)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateInsets()
    }

    override func layout() {
        super.layout()
        updateInsets()
    }

    func update(rootView: Content) {
        hostingView.rootView = rootView
        needsLayout = true
    }

    private func setup() {
        wantsLayer = true

        clipView.translatesAutoresizingMaskIntoConstraints = false
        clipView.wantsLayer = true
        clipView.layer?.masksToBounds = true
        addSubview(clipView)

        hostingView.translatesAutoresizingMaskIntoConstraints = false
        clipView.addSubview(hostingView)

        let top = clipView.topAnchor.constraint(equalTo: topAnchor)
        let leading = clipView.leadingAnchor.constraint(equalTo: leadingAnchor)
        let bottom = clipView.bottomAnchor.constraint(equalTo: bottomAnchor)
        let trailing = clipView.trailingAnchor.constraint(equalTo: trailingAnchor)

        NSLayoutConstraint.activate([top, leading, bottom, trailing])
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: clipView.topAnchor),
            hostingView.leadingAnchor.constraint(equalTo: clipView.leadingAnchor),
            hostingView.bottomAnchor.constraint(equalTo: clipView.bottomAnchor),
            hostingView.trailingAnchor.constraint(equalTo: clipView.trailingAnchor),
        ])

        topConstraint = top
        leadingConstraint = leading
        bottomConstraint = bottom
        trailingConstraint = trailing
    }

    private func updateInsets() {
        guard let topConstraint, let leadingConstraint, let bottomConstraint, let trailingConstraint else {
            return
        }

        let bottomInset = terminalBottomInset()
        guard bottomInset != lastBottomInset else { return }
        lastBottomInset = bottomInset

        topConstraint.constant = 0
        leadingConstraint.constant = 0
        bottomConstraint.constant = -bottomInset
        trailingConstraint.constant = 0
    }

    private func terminalBottomInset() -> CGFloat {
        guard let window, let contentView = window.contentView else {
            return 0
        }

        let tolerance: CGFloat = 1
        let regionFrame = convert(bounds, to: nil)
        let contentFrame = contentView.convert(contentView.bounds, to: nil)
        let touchesBottom = abs(regionFrame.minY - contentFrame.minY) <= tolerance

        guard touchesBottom else { return 0 }

        let radius = windowCornerRadius(in: window)
        guard radius > 0 else { return 0 }

        // Keep a small embedded lift: larger than 1pt, but still well below the full corner clearance.
        return max(2, ceil(radius * 0.09))
    }

    private func windowCornerRadius(in window: NSWindow) -> CGFloat {
        guard window.responds(to: Selector(("_cornerRadius"))),
              let radius = window.value(forKey: "_cornerRadius") as? CGFloat else {
            return 0
        }

        return radius
    }
}
