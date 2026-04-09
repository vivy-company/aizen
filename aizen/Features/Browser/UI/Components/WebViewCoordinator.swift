import SwiftUI
import WebKit
import os.log

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

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            if parent.onNewTab != nil {
                parent.onNewTab?(url.absoluteString)
            } else {
                webView.load(URLRequest(url: url))
            }
        }

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
        guard nsError.code != NSURLErrorCancelled else { return }

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

        if let failedURL = webView.url?.absoluteString {
            lastFailedURL = failedURL
        }

        Task { @MainActor in
            parent.isLoading = false
            parent.onLoadError?(errorMessage)
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard navigationAction.targetFrame?.isMainFrame == true else {
            decisionHandler(.allow)
            return
        }

        if let url = navigationAction.request.url {
            Task { @MainActor in
                parent.onURLChange(url.absoluteString)
            }
        }

        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        if let url = webView.url?.absoluteString {
            Task { @MainActor in
                parent.onURLChange(url)
            }
        }
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        guard let webView = object as? WKWebView, webView === self.webView else { return }

        if keyPath == "estimatedProgress" {
            parent.loadingProgress = webView.estimatedProgress
        } else if keyPath == "URL" {
            if let url = webView.url?.absoluteString {
                Task { @MainActor in
                    parent.onURLChange(url)
                }
            }
        } else if keyPath == "title" {
            if let title = webView.title {
                Task { @MainActor in
                    parent.onTitleChange(title)
                }
            }
        }
    }
}
