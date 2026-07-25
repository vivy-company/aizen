import CoreData
import Foundation
import Testing
@testable import Aizen

@MainActor
struct WorkspacePaneIsolationTests {
    @Test func newFileAndBrowserPanesReceiveDistinctSessionIdentities() throws {
        let (context, worktree) = try makeWorktree()
        let workspace = WorkspaceStore(worktree: worktree, viewContext: context)

        let firstFiles = workspace.makePane(kind: .files, inheritingFrom: nil)
        let secondFiles = workspace.makePane(kind: .files, inheritingFrom: nil)
        let firstBrowser = workspace.makePane(kind: .browser, inheritingFrom: nil)
        let secondBrowser = workspace.makePane(kind: .browser, inheritingFrom: nil)

        #expect(firstFiles.sessionId != nil)
        #expect(firstFiles.sessionId != secondFiles.sessionId)
        #expect(firstBrowser.sessionId != nil)
        #expect(firstBrowser.sessionId != secondBrowser.sessionId)
    }

    @Test func filePaneStoresDoNotShareNavigationState() throws {
        let (context, worktree) = try makeWorktree()
        let firstSession = makeFileSession(context: context, worktree: worktree)
        let secondSession = makeFileSession(context: context, worktree: worktree)
        try context.save()

        let firstStore = FileBrowserStore(worktree: worktree, context: context, session: firstSession)
        let secondStore = FileBrowserStore(worktree: worktree, context: context, session: secondSession)

        firstStore.toggleExpanded(path: "/tmp/project/Sources")

        #expect(firstStore.expandedPaths == Set(["/tmp/project/Sources"]))
        #expect(secondStore.expandedPaths.isEmpty)
    }

    @Test func firstFilePaneClaimsLegacyStateWithoutLeavingAStaleFallback() throws {
        let (context, worktree) = try makeWorktree()
        let legacySession = FileBrowserSession(context: context)
        legacySession.id = UUID()
        legacySession.currentPath = "/tmp/project/Sources"
        legacySession.expandedPaths = ["/tmp/project/Sources"]
        legacySession.openFilesPaths = []
        legacySession.worktree = worktree
        try context.save()

        let workspace = WorkspaceStore(worktree: worktree, viewContext: context)
        let pane = workspace.makePane(kind: .files, inheritingFrom: nil)
        let session = try #require(pane.sessionId.flatMap(workspace.filePaneSession(withId:)))
        let legacySessionCount = try context.count(for: FileBrowserSession.fetchRequest())

        #expect(session.currentPath == "/tmp/project/Sources")
        #expect(session.expandedPaths == ["/tmp/project/Sources"])
        #expect(legacySessionCount == 0)
        #expect(worktree.fileBrowserSession == nil)
    }

    @Test func browserStoresOnlyLoadTabsFromTheirWorkspaceSession() throws {
        let (context, worktree) = try makeWorktree()
        let firstWorkspaceSessionId = UUID()
        let secondWorkspaceSessionId = UUID()
        let firstStore = BrowserSessionStore(
            viewContext: context,
            worktree: worktree,
            workspaceSessionId: firstWorkspaceSessionId
        )
        let secondStore = BrowserSessionStore(
            viewContext: context,
            worktree: worktree,
            workspaceSessionId: secondWorkspaceSessionId
        )

        firstStore.createSession(url: "https://example.com/first")
        secondStore.createSession(url: "https://example.com/second")

        #expect(firstStore.sessions.compactMap(\.url) == ["https://example.com/first"])
        #expect(secondStore.sessions.compactMap(\.url) == ["https://example.com/second"])
        #expect(firstStore.sessions.allSatisfy { $0.workspaceSessionId == firstWorkspaceSessionId })
        #expect(secondStore.sessions.allSatisfy { $0.workspaceSessionId == secondWorkspaceSessionId })
    }

    private func makeWorktree() throws -> (NSManagedObjectContext, Worktree) {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let worktree = Worktree(context: context)
        worktree.id = UUID()
        worktree.path = "/tmp/project"
        worktree.branch = "main"
        worktree.isPrimary = true
        try context.save()
        return (context, worktree)
    }

    private func makeFileSession(
        context: NSManagedObjectContext,
        worktree: Worktree
    ) -> FilePaneSession {
        let session = FilePaneSession(context: context)
        session.id = UUID()
        session.currentPath = worktree.path
        session.expandedPaths = []
        session.openFilesPaths = []
        session.worktree = worktree
        return session
    }
}
