import SwiftUI
import WebKit
import os.log

// MARK: - WebViewWrapper

struct WebViewWrapper: NSViewRepresentable {
    let url: String
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool
    let onURLChange: (String) -> Void
    let onTitleChange: (String) -> Void
    @Binding var isLoading: Bool
    @Binding var loadingProgress: Double

    let onNavigationAction: ((WKWebView, WKNavigationAction) -> Void)?
    let onNewTab: ((String) -> Void)?
    let onWebViewCreated: ((WKWebView) -> Void)?
    let onLoadError: ((String) -> Void)?

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen.app", category: "WebView")

    init(
        url: String,
        canGoBack: Binding<Bool>,
        canGoForward: Binding<Bool>,
        onURLChange: @escaping (String) -> Void,
        onTitleChange: @escaping (String) -> Void,
        isLoading: Binding<Bool>,
        loadingProgress: Binding<Double>,
        onNavigationAction: ((WKWebView, WKNavigationAction) -> Void)? = nil,
        onNewTab: ((String) -> Void)? = nil,
        onWebViewCreated: ((WKWebView) -> Void)? = nil,
        onLoadError: ((String) -> Void)? = nil
    ) {
        self.url = url
        self._canGoBack = canGoBack
        self._canGoForward = canGoForward
        self.onURLChange = onURLChange
        self.onTitleChange = onTitleChange
        self._isLoading = isLoading
        self._loadingProgress = loadingProgress
        self.onNavigationAction = onNavigationAction
        self.onNewTab = onNewTab
        self.onWebViewCreated = onWebViewCreated
        self.onLoadError = onLoadError
    }

    func makeCoordinator() -> WebViewCoordinator {
        WebViewCoordinator(self)
    }

    func makeNSView(context: Context) -> NSView {
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true

        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences = preferences

        // Enable more Safari-like behavior
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true

        // Enable full-screen support for videos and content
        if #available(macOS 12.0, *) {
            configuration.preferences.isElementFullscreenEnabled = true
        }

        // Enable modern web features via private APIs
        configuration.preferences.setValue(true, forKey: "allowsPictureInPictureMediaPlayback")
        configuration.preferences.setValue(true, forKey: "webGLEnabled")
        configuration.preferences.setValue(true, forKey: "acceleratedDrawingEnabled")
        configuration.preferences.setValue(true, forKey: "canvasUsesAcceleratedDrawing")

        // Suppress content rendering delays
        configuration.suppressesIncrementalRendering = false

        // Media playback settings - macOS uses preferences, not configuration
        // allowsInlineMediaPlayback, mediaTypesRequiringUserActionForPlayback are iOS-only
        // On macOS, media plays inline by default and user action is controlled via preferences

        // Set application name to Safari to bypass WKWebView detection
        configuration.applicationNameForUserAgent = "Version/18.0 Safari/605.1.15"

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true

        // Set custom User-Agent to match Safari macOS Sequoia
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

        // Enable developer extras using private API for context menu "Inspect Element"
        // This is required to show "Inspect Element" in right-click menu on macOS
        webView.configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")

        // Enable web inspector for debugging (macOS 13.3+)
        // This allows inspection via Safari's Develop menu
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }

        // Observe loading progress, URL changes, and title changes
        context.coordinator.attach(to: webView)

        // Create wrapper view to fix Web Inspector flickering
        // Wrapping WKWebView prevents autolayout conflicts with inspector
        let containerView = NSView(frame: .zero)
        containerView.addSubview(webView)

        // Set webView frame to match container
        webView.frame = containerView.bounds
        webView.autoresizingMask = [.width, .height]

        // Notify that WebView was created (defer to avoid publishing during view update)
        if let callback = onWebViewCreated {
            DispatchQueue.main.async {
                callback(webView)
            }
        }

        // Defer initial load to avoid blocking view update
        if let url = URL(string: url) {
            DispatchQueue.main.async {
                webView.load(URLRequest(url: url))
            }
        }

        return containerView
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: WebViewCoordinator) {
        coordinator.detach()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Update coordinator's parent reference to get latest closures
        context.coordinator.parent = self

        // Get the WKWebView from container
        guard let webView = nsView.subviews.first(where: { $0 is WKWebView }) as? WKWebView else { return }
        // Don't reload if URL is empty
        guard !url.isEmpty else { return }

        let currentURL = webView.url?.absoluteString ?? ""

        // Don't reload if the URL is the same (prevents infinite loops)
        guard currentURL != url else { return }

        // Don't retry if this URL previously failed to load
        if url == context.coordinator.lastFailedURL {
            return
        }

        // Don't reload if we're currently loading (prevents interrupting navigation)
        guard !webView.isLoading else { return }

        // Clear failed URL on new navigation attempt
        context.coordinator.lastFailedURL = nil

        // Validate and load URL with error handling
        guard let newURL = URL(string: url) else {
            Self.logger.error("Invalid URL string: \(url)")
            return
        }

        // Additional validation for URL components
        guard newURL.scheme != nil || url.hasPrefix("about:") else {
            Self.logger.error("URL missing scheme: \(url)")
            return
        }

        // Load the URL
        webView.load(URLRequest(url: newURL))
    }

    // MARK: - Navigation Methods

    static func goBack(_ webView: WKWebView) {
        webView.goBack()
    }

    static func goForward(_ webView: WKWebView) {
        webView.goForward()
    }

    static func reload(_ webView: WKWebView) {
        webView.reload()
    }
}
