import Combine
import CoreData
import Foundation
import os.log

extension BrowserSessionStore {
    // MARK: - Session Management

    func loadSessions() {
        let fetchRequest: NSFetchRequest<BrowserSession> = BrowserSession.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "worktree == %@", worktree)
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \BrowserSession.order, ascending: true)]

        do {
            sessions = try viewContext.fetch(fetchRequest)

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

        if activeSessionId == sessionId {
            activeWebView = nil
        }

        let needsNewActiveTab = activeSessionId == sessionId
        viewContext.delete(session)

        do {
            try viewContext.save()
            loadSessions()

            if sessions.isEmpty {
                createSession()
                return
            }

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

        activeWebView = nil
        canGoBack = false
        canGoForward = false
        isLoading = false
    }

    func handleURLChange(sessionId: UUID, url: String) {
        guard let session = sessions.first(where: { $0.id == sessionId }) else { return }
        guard session.url != url else { return }

        session.url = url

        if activeSessionId == sessionId {
            currentURL = url
        }

        objectWillChange.send()
        debouncedSave()
    }

    func handleTitleChange(sessionId: UUID, title: String) {
        guard let session = sessions.first(where: { $0.id == sessionId }) else { return }
        guard session.title != title else { return }

        session.title = title

        if activeSessionId == sessionId {
            pageTitle = title
        }

        objectWillChange.send()
        debouncedSave()
    }
}
