import SwiftUI
import CoreData
import WebKit
import Combine
import os.log

@MainActor
class BrowserSessionManager: ObservableObject {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen.app", category: "BrowserSession")
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

    private let viewContext: NSManagedObjectContext
    private let worktree: Worktree
    private var saveTask: Task<Void, Never>?
    private var activeWebView: WKWebView?

    init(viewContext: NSManagedObjectContext, worktree: Worktree) {
        self.viewContext = viewContext
        self.worktree = worktree
        loadSessions()
    }

    deinit {
        saveTask?.cancel()
    }

    private func debouncedSave() {
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

    // MARK: - Session Management

    func loadSessions() {
        let fetchRequest: NSFetchRequest<BrowserSession> = BrowserSession.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "worktree == %@", worktree)
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \BrowserSession.order, ascending: true)]

        do {
            sessions = try viewContext.fetch(fetchRequest)

            // Set active session to first if none selected
            if activeSessionId == nil, let firstSession = sessions.first {
                activeSessionId = firstSession.id
                currentURL = firstSession.url ?? ""
                pageTitle = firstSession.title ?? ""
            }
        } catch {
            logger.error("Failed to load browser sessions: \(error)")
        }
    }

    func createSession(url: String = "") {
        let newSession = BrowserSession(context: viewContext)
        let newId = UUID()
        newSession.id = newId
        newSession.url = url
        newSession.title = nil
        newSession.createdAt = Date()
        newSession.order = Int16(sessions.count)
        newSession.worktree = worktree

        do {
            try viewContext.save()
            loadSessions()
            DispatchQueue.main.async {
                self.selectSession(newId)
            }
        } catch {
            logger.error("Failed to create browser session: \(error)")
        }
    }

    func createSessionWithURL(_ url: String) {
        createSession(url: url)
    }

    func closeSession(_ sessionId: UUID) {
        guard let session = sessions.first(where: { $0.id == sessionId }) else { return }

        // If this tab is currently active, drop the active webview reference so it can deallocate.
        if activeSessionId == sessionId {
            activeWebView = nil
        }

        // Check if we need to switch to another tab BEFORE deleting
        let needsNewActiveTab = activeSessionId == sessionId

        // Delete from Core Data
        viewContext.delete(session)

        do {
            try viewContext.save()
            loadSessions()

            // If this was the last tab, create a new empty tab
            if sessions.isEmpty {
                createSession()
                return
            }

            // Switch to another session if the closed one was active
            if needsNewActiveTab {
                DispatchQueue.main.async {
                    if let newId = self.sessions.first?.id {
                        self.selectSession(newId)
                    } else {
                        self.activeSessionId = nil
                        self.currentURL = ""
                        self.pageTitle = ""
                    }
                }
            }
        } catch {
            logger.error("Failed to delete browser session: \(error)")
        }
    }

    func selectSession(_ sessionId: UUID) {
        guard let session = sessions.first(where: { $0.id == sessionId }) else { return }

        activeSessionId = sessionId
        currentURL = session.url ?? ""
        pageTitle = session.title ?? ""

        // New tab selection creates a new WKWebView; reset state until the view is ready.
        activeWebView = nil
        canGoBack = false
        canGoForward = false
        isLoading = false
    }

    func handleURLChange(sessionId: UUID, url: String) {
        guard let session = sessions.first(where: { $0.id == sessionId }) else { return }

        // Only update if different to avoid reload loop
        guard session.url != url else { return }

        session.url = url

        // Update published property if this is active session
        if activeSessionId == sessionId {
            currentURL = url
        }

        // Trigger UI update for tab titles
        objectWillChange.send()

        // Debounce save to reduce Core Data writes
        debouncedSave()
    }

    func handleTitleChange(sessionId: UUID, title: String) {
        guard let session = sessions.first(where: { $0.id == sessionId }) else { return }

        // Only update if different
        guard session.title != title else { return }

        session.title = title

        // Update published property if this is active session
        if activeSessionId == sessionId {
            pageTitle = title
        }

        // Trigger UI update for tab titles
        objectWillChange.send()

        // Debounce save to reduce Core Data writes
        debouncedSave()
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
        activeWebView = webView
    }

    // MARK: - Computed Properties

    var activeSession: BrowserSession? {
        guard let sessionId = activeSessionId else { return nil }
        return sessions.first { $0.id == sessionId }
    }
}
