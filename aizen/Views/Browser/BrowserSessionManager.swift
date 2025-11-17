import SwiftUI
import CoreData
import WebKit
import Combine

@MainActor
class BrowserSessionManager: ObservableObject {
    @Published var sessions: [BrowserSession] = []
    @Published var activeSessionId: UUID?
    @Published var webViews: [UUID: WKWebView] = [:]

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
                print("Failed to save browser session: \(error)")
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
            print("Failed to load browser sessions: \(error)")
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
            sessions.append(newSession)
            selectSession(newId)
        } catch {
            print("Failed to create browser session: \(error)")
        }
    }

    func createSessionWithURL(_ url: String) {
        createSession(url: url)
    }

    func closeSession(_ sessionId: UUID) {
        guard let session = sessions.first(where: { $0.id == sessionId }) else { return }

        // Remove webview
        webViews.removeValue(forKey: sessionId)

        // Remove from sessions array first
        sessions.removeAll { $0.id == sessionId }

        // Check if we need to switch to another tab BEFORE deleting
        let needsNewActiveTab = activeSessionId == sessionId
        var newActiveSessionId: UUID?

        if needsNewActiveTab && !sessions.isEmpty {
            // Pick the first remaining session
            newActiveSessionId = sessions.first?.id
        }

        // Delete from Core Data
        viewContext.delete(session)

        do {
            try viewContext.save()

            // If this was the last tab, create a new empty tab
            if sessions.isEmpty {
                createSession()
                return
            }

            // Switch to another session if the closed one was active
            if needsNewActiveTab {
                if let newId = newActiveSessionId {
                    selectSession(newId)
                } else {
                    activeSessionId = nil
                    currentURL = ""
                    pageTitle = ""
                }
            }
        } catch {
            print("Failed to delete browser session: \(error)")
            // Re-add to sessions array on failure
            sessions.append(session)
        }
    }

    func selectSession(_ sessionId: UUID) {
        guard let session = sessions.first(where: { $0.id == sessionId }) else { return }

        activeSessionId = sessionId
        currentURL = session.url ?? ""
        pageTitle = session.title ?? ""

        // Update webview state if exists
        if let webView = webViews[sessionId] {
            canGoBack = webView.canGoBack
            canGoForward = webView.canGoForward
            isLoading = webView.isLoading
        } else {
            canGoBack = false
            canGoForward = false
            isLoading = false
        }
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
            print("Failed to save session URL: \(error)")
        }
    }

    func handleLoadError(_ error: String) {
        loadError = error
        isLoading = false
    }

    func goBack() {
        guard let sessionId = activeSessionId,
              let webView = webViews[sessionId] else { return }

        webView.goBack()
    }

    func goForward() {
        guard let sessionId = activeSessionId,
              let webView = webViews[sessionId] else { return }

        webView.goForward()
    }

    func reload() {
        guard let sessionId = activeSessionId,
              let webView = webViews[sessionId] else { return }

        webView.reload()
    }

    func registerWebView(_ webView: WKWebView, for sessionId: UUID) {
        webViews[sessionId] = webView
    }

    // MARK: - Computed Properties

    var activeSession: BrowserSession? {
        guard let sessionId = activeSessionId else { return nil }
        return sessions.first { $0.id == sessionId }
    }
}
