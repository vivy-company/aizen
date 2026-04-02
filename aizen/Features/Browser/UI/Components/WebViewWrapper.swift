import SwiftUI
import WebKit
import os.log

// MARK: - WebView Coordinator

class WebViewCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
    var parent: WebViewWrapper
    var lastFailedURL: String?
    weak var webView: WKWebView?
    private var observersAttached = false
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen.app", category: "WebView")

    init(_ parent: WebViewWrapper) {
        self.parent = parent
    }

    func attach(to webView: WKWebView) {
        if self.webView === webView && observersAttached {
            return
        }

        detach()
        self.webView = webView

        webView.addObserver(self, forKeyPath: "estimatedProgress", options: .new, context: nil)
        webView.addObserver(self, forKeyPath: "URL", options: .new, context: nil)
        webView.addObserver(self, forKeyPath: "title", options: .new, context: nil)
        observersAttached = true
    }

    func detach() {
        guard let webView = webView else { return }

        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil

        if observersAttached {
            webView.removeObserver(self, forKeyPath: "estimatedProgress")
            webView.removeObserver(self, forKeyPath: "URL")
            webView.removeObserver(self, forKeyPath: "title")
            observersAttached = false
        }

        self.webView = nil
    }

    // MARK: - WKUIDelegate

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // Handle new tab/window requests (e.g., target="_blank" links, dev tools console URLs)
        if let url = navigationAction.request.url {
            if parent.onNewTab != nil {
                // Notify parent to create new tab
                parent.onNewTab?(url.absoluteString)
            } else {
                // No new tab handler - load in current webview to prevent crash
                webView.load(URLRequest(url: url))
            }
        }

        // Return nil - we handle navigation ourselves
        // This is safe because we either opened a new tab or loaded in current webview
        return nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            parent.canGoBack = webView.canGoBack
            parent.canGoForward = webView.canGoForward

            if let url = webView.url?.absoluteString {
                parent.onURLChange(url)
            }

            if let title = webView.title {
                parent.onTitleChange(title)
            }
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        Task { @MainActor in
            parent.isLoading = true
        }
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        Task { @MainActor in
            parent.isLoading = false
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            parent.isLoading = false
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let nsError = error as NSError

        // Filter out cancelled navigation (error -999)
        guard nsError.code != NSURLErrorCancelled else { return }

        // Build user-friendly error message
        let errorMessage: String
        switch nsError.code {
        case NSURLErrorNotConnectedToInternet:
            errorMessage = "No internet connection"
        case NSURLErrorTimedOut:
            errorMessage = "Request timed out"
        case NSURLErrorCannotFindHost:
            errorMessage = "Cannot find server"
        case NSURLErrorCannotConnectToHost:
            errorMessage = "Cannot connect to server"
        case NSURLErrorServerCertificateUntrusted, NSURLErrorServerCertificateHasBadDate, NSURLErrorServerCertificateHasUnknownRoot:
            errorMessage = "The certificate for this server is invalid"
        default:
            errorMessage = error.localizedDescription
        }

        // Track failed URL to prevent retry loop
        if let failedURL = webView.url?.absoluteString {
            lastFailedURL = failedURL
        }

        Task { @MainActor in
            parent.isLoading = false
            parent.onLoadError?(errorMessage)
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // Only track main frame navigation, not iframes or resources
        guard navigationAction.targetFrame?.isMainFrame == true else {
            decisionHandler(.allow)
            return
        }

        // Track navigation URL (including redirects) for main frame only
        if let url = navigationAction.request.url {
            // Update URL bar for main frame navigations
            Task { @MainActor in
                parent.onURLChange(url.absoluteString)
            }
        }

        // Allow navigation
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        // Update URL bar when server redirect occurs (main frame only)
        if let url = webView.url?.absoluteString {
            Task { @MainActor in
                parent.onURLChange(url)
            }
        }
    }

    // MARK: - KVO for Progress and URL

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        guard let webView = object as? WKWebView, webView === self.webView else { return }

        if keyPath == "estimatedProgress" {
            parent.loadingProgress = webView.estimatedProgress
        } else if keyPath == "URL" {
            // Update URL bar when URL changes (catches all navigation types)
            if let url = webView.url?.absoluteString {
                Task { @MainActor in
                    parent.onURLChange(url)
                }
            }
        } else if keyPath == "title" {
            // Update title when it changes
            if let title = webView.title {
                Task { @MainActor in
                    parent.onTitleChange(title)
                }
            }
        }
    }
}

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
