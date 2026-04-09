import ACP
import Combine
import CoreData
import os.log
import SwiftUI
import WebKit

@MainActor
class BrowserSessionStore: ObservableObject {
    let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen.app", category: "BrowserSession")
    @Published var sessions: [BrowserSession] = []
    @Published var activeSessionId: UUID?

    // WebView state bindings
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false
    @Published var currentURL: String = ""
    @Published var pageTitle: String = ""
    @Published var isLoading: Bool = false
    @Published var loadingProgress: Double = 0.0
    @Published var loadError: String? = nil

    let viewContext: NSManagedObjectContext
    let worktree: Worktree
    private var saveTask: Task<Void, Never>?
    var activeWebView: WKWebView?
    private var warmWebViewsBySessionId: [UUID: WKWebView] = [:]
    private var warmWebViewOrder: [UUID] = []
    private let maxWarmWebViews = 3

    init(viewContext: NSManagedObjectContext, worktree: Worktree) {
        self.viewContext = viewContext
        self.worktree = worktree
        loadSessions()
    }

    deinit {
        saveTask?.cancel()
    }

    func debouncedSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            guard !Task.isCancelled else { return }

            do {
                try viewContext.save()
            } catch {
                logger.error("Failed to save browser session: \(error)")
            }
        }
    }

    // MARK: - WebView Actions

    func navigateToURL(_ url: String) {
        guard let sessionId = activeSessionId,
              let session = sessions.first(where: { $0.id == sessionId }) else {
            return
        }

        // Clear any previous errors
        loadError = nil

        // Update the published property (will trigger WebView to load)
        currentURL = url

        // Update Core Data
        session.url = url
        do {
            try viewContext.save()
        } catch {
            logger.error("Failed to save session URL: \(error)")
        }
    }

    func handleLoadError(_ error: String) {
        loadError = error
        isLoading = false
    }

    func goBack() {
        activeWebView?.goBack()
    }

    func goForward() {
        activeWebView?.goForward()
    }

    func reload() {
        activeWebView?.reload()
    }

    func registerActiveWebView(_ webView: WKWebView, for sessionId: UUID) {
        guard activeSessionId == sessionId else { return }
        cacheWebView(webView, for: sessionId)
        activeWebView = webView
        syncNavigationState(from: webView)
    }

    func releaseActiveWebView() {
        activeWebView = nil
        canGoBack = false
        canGoForward = false
        isLoading = false
        loadingProgress = 0
    }

    func cachedWebView(for sessionId: UUID) -> WKWebView? {
        guard let webView = warmWebViewsBySessionId[sessionId] else { return nil }
        touchWarmWebView(sessionId)
        return webView
    }

    func clearWarmWebViews() {
        for webView in warmWebViewsBySessionId.values {
            webView.stopLoading()
            webView.navigationDelegate = nil
            webView.uiDelegate = nil
        }
        warmWebViewsBySessionId.removeAll()
        warmWebViewOrder.removeAll()
        releaseActiveWebView()
    }

    func removeWarmWebView(for sessionId: UUID) {
        if let webView = warmWebViewsBySessionId.removeValue(forKey: sessionId) {
            webView.stopLoading()
            webView.navigationDelegate = nil
            webView.uiDelegate = nil
        }
        warmWebViewOrder.removeAll { $0 == sessionId }
        if activeSessionId == sessionId {
            releaseActiveWebView()
        }
    }

    func syncNavigationState(from webView: WKWebView) {
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        isLoading = webView.isLoading
        loadingProgress = webView.estimatedProgress
        currentURL = webView.url?.absoluteString ?? currentURL
        pageTitle = webView.title ?? pageTitle
    }

    // MARK: - Computed Properties

    var activeSession: BrowserSession? {
        guard let sessionId = activeSessionId else { return nil }
        return sessions.first { $0.id == sessionId }
    }

    private func cacheWebView(_ webView: WKWebView, for sessionId: UUID) {
        warmWebViewsBySessionId[sessionId] = webView
        touchWarmWebView(sessionId)
        evictWarmWebViewsIfNeeded()
    }

    private func touchWarmWebView(_ sessionId: UUID) {
        warmWebViewOrder.removeAll { $0 == sessionId }
        warmWebViewOrder.append(sessionId)
    }

    private func evictWarmWebViewsIfNeeded() {
        while warmWebViewsBySessionId.count > maxWarmWebViews,
              let oldestSessionId = warmWebViewOrder.first {
            warmWebViewOrder.removeFirst()
            guard oldestSessionId != activeSessionId else {
                warmWebViewOrder.append(oldestSessionId)
                break
            }
            removeWarmWebView(for: oldestSessionId)
        }
    }
}
