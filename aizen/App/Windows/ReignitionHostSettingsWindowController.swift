import SwiftUI

/// Presents the Reignition settings owned by the Host-client app composition.
@MainActor
final class ReignitionHostSettingsWindowController {
    static let shared = ReignitionHostSettingsWindowController()

    private var window: NSWindow?

    private init() {}

    func show() {
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let content = HostServiceSettingsView()
            .modifier(AppearanceModifier())
        let window = NSWindow(contentViewController: NSHostingController(rootView: content))
        window.title = "Aizen Host Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .unified
        window.backgroundColor = AppSurfaceTheme.backgroundNSColor()
        window.setContentSize(NSSize(width: 640, height: 420))
        window.minSize = NSSize(width: 540, height: 360)
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }
}
