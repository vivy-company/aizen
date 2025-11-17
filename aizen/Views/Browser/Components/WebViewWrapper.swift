import SwiftUI
import WebKit

// MARK: - WebView Coordinator

class WebViewCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
    var parent: WebViewWrapper
    var lastFailedURL: String?

    init(_ parent: WebViewWrapper) {
        self.parent = parent
    }

    // MARK: - WKUIDelegate

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // Handle new tab/window requests (e.g., target="_blank" links)
        if let url = navigationAction.request.url {
            // Notify parent to create new tab
            parent.onNewTab?(url.absoluteString)
        }

        // Return nil to prevent WKWebView from creating its own window
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

    // MARK: - KVO for Progress

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "estimatedProgress", let webView = object as? WKWebView {
            parent.loadingProgress = webView.estimatedProgress
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

        // Media playback settings (macOS only has these on iOS, so skip)
        #if os(iOS)
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        #endif

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

        // Observe loading progress
        webView.addObserver(context.coordinator, forKeyPath: "estimatedProgress", options: .new, context: nil)

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
        // Find WKWebView in container and remove observer
        if let webView = nsView.subviews.first(where: { $0 is WKWebView }) as? WKWebView {
            webView.removeObserver(coordinator, forKeyPath: "estimatedProgress")
        }
    }

    func updateNSView(_ nsView: NSView, context: Context) {
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

        // Only reload if the new URL is actually different from current
        if let newURL = URL(string: url) {
            webView.load(URLRequest(url: newURL))
        }
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
