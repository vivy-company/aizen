import SwiftUI
import CoreData
import WebKit
import os.log

struct BrowserTabView: View {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen.app", category: "BrowserTab")
    let worktree: Worktree
    @Binding var selectedSessionId: UUID?

    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var manager: BrowserSessionManager

    init(worktree: Worktree, selectedSessionId: Binding<UUID?>) {
        self.worktree = worktree
        self._selectedSessionId = selectedSessionId

        // Initialize manager with worktree and viewContext
        let context = PersistenceController.shared.container.viewContext
        _manager = StateObject(wrappedValue: BrowserSessionManager(viewContext: context, worktree: worktree))
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            // Session tabs - always visible
            sessionTabsView

            Divider()

            // Active browser content
            VStack(spacing: 0) {
                // Control bar
                BrowserControlBar(
                    url: $manager.currentURL,
                    canGoBack: $manager.canGoBack,
                    canGoForward: $manager.canGoForward,
                    isLoading: $manager.isLoading,
                    loadingProgress: $manager.loadingProgress,
                    onBack: { manager.goBack() },
                    onForward: { manager.goForward() },
                    onReload: { manager.reload() },
                    onNavigate: { url in manager.navigateToURL(url) }
                )

                Divider()

                // WebView - only keep the active tab alive to avoid WKWebView-per-tab memory spikes
                ZStack {
                    if let sessionId = manager.activeSessionId,
                       let session = manager.sessions.first(where: { $0.id == sessionId }) {
                        let sessionURL = session.url ?? ""

                        if !sessionURL.isEmpty {
                            WebViewWrapper(
                                url: sessionURL,
                                canGoBack: $manager.canGoBack,
                                canGoForward: $manager.canGoForward,
                                onURLChange: { newURL in
                                    manager.handleURLChange(sessionId: sessionId, url: newURL)
                                },
                                onTitleChange: { newTitle in
                                    manager.handleTitleChange(sessionId: sessionId, title: newTitle)
                                },
                                isLoading: $manager.isLoading,
                                loadingProgress: $manager.loadingProgress,
                                onNewTab: { url in
                                    manager.createSessionWithURL(url)
                                },
                                onWebViewCreated: { webView in
                                    manager.registerActiveWebView(webView, for: sessionId)
                                },
                                onLoadError: { error in
                                    manager.handleLoadError(error)
                                }
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .id(sessionId)
                        } else {
                            emptyTabState
                        }
                    }

                    // Show error overlay if there's an error
                    if let error = manager.loadError {
                        errorView(error)
                    }
                }
            }
        }
        .task {
            // Initialize session if empty
            if manager.sessions.isEmpty {
                manager.createSession()
            }

            // Sync selection bidirectionally
            if selectedSessionId == nil {
                selectedSessionId = manager.activeSessionId
            } else if let sessionId = selectedSessionId,
                      sessionId != manager.activeSessionId {
                manager.selectSession(sessionId)
            }
        }
        .task(id: manager.activeSessionId) {
            // Keep binding synced with manager state
            selectedSessionId = manager.activeSessionId
        }
    }

    // MARK: - Session Tabs View

    private var sessionTabsView: some View {
        HStack(spacing: 0) {
            // Navigation arrows
            Button(action: selectPreviousTab) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11))
                    .frame(width: 32, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(manager.sessions.count <= 1)

            Button(action: selectNextTab) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11))
                    .frame(width: 32, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(manager.sessions.count <= 1)

            Divider()

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(manager.sessions, id: \.id) { session in
                        sessionTab(for: session)
                    }
                }
            }

            Divider()

            // New tab button
            Button(action: {
                manager.createSession()
            }) {
                Image(systemName: "plus")
                    .font(.system(size: 12))
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help(String(localized: "browser.tab.new"))
        }
        .frame(height: 36)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    private func selectPreviousTab() {
        guard let currentId = manager.activeSessionId,
              let currentIndex = manager.sessions.firstIndex(where: { $0.id == currentId }),
              currentIndex > 0,
              let prevId = manager.sessions[currentIndex - 1].id else { return }
        manager.selectSession(prevId)
    }

    private func selectNextTab() {
        guard let currentId = manager.activeSessionId,
              let currentIndex = manager.sessions.firstIndex(where: { $0.id == currentId }),
              currentIndex < manager.sessions.count - 1,
              let nextId = manager.sessions[currentIndex + 1].id else { return }
        manager.selectSession(nextId)
    }

    @ViewBuilder
    private func sessionTab(for session: BrowserSession) -> some View {
        BrowserTab(
            session: session,
            isSelected: manager.activeSessionId == session.id,
            onSelect: {
                if let sessionId = session.id {
                    manager.selectSession(sessionId)
                }
            },
            onClose: {
                if let sessionId = session.id {
                    manager.closeSession(sessionId)
                }
            }
        )
        .contextMenu {
            if let sessionId = session.id {
                Button("Close Tab") {
                    manager.closeSession(sessionId)
                }

                Divider()

                Button("Close All to the Left") {
                    closeAllToLeft(of: sessionId)
                }
                .disabled(!canCloseToLeft(of: sessionId))

                Button("Close All to the Right") {
                    closeAllToRight(of: sessionId)
                }
                .disabled(!canCloseToRight(of: sessionId))

                Divider()

                Button("Close Other Tabs") {
                    closeOtherTabs(except: sessionId)
                }
                .disabled(manager.sessions.count <= 1)
            }
        }
    }

    private func canCloseToLeft(of sessionId: UUID) -> Bool {
        guard let index = manager.sessions.firstIndex(where: { $0.id == sessionId }) else { return false }
        return index > 0
    }

    private func canCloseToRight(of sessionId: UUID) -> Bool {
        guard let index = manager.sessions.firstIndex(where: { $0.id == sessionId }) else { return false }
        return index < manager.sessions.count - 1
    }

    private func closeAllToLeft(of sessionId: UUID) {
        guard let index = manager.sessions.firstIndex(where: { $0.id == sessionId }) else { return }

        for i in (0..<index).reversed() {
            if let id = manager.sessions[i].id {
                manager.closeSession(id)
            }
        }
    }

    private func closeAllToRight(of sessionId: UUID) {
        guard let index = manager.sessions.firstIndex(where: { $0.id == sessionId }) else { return }

        for i in ((index + 1)..<manager.sessions.count).reversed() {
            if let id = manager.sessions[i].id {
                manager.closeSession(id)
            }
        }
    }

    private func closeOtherTabs(except sessionId: UUID) {
        for session in manager.sessions {
            if let id = session.id, id != sessionId {
                manager.closeSession(id)
            }
        }
    }

    // MARK: - Empty States

    private var emptyTabState: some View {
        EmptyTabStateView(manager: manager)
    }

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.red)

            Text("Failed to Load Page")
                .font(.title2)
                .fontWeight(.semibold)

            Text(error)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button {
                manager.loadError = nil
                manager.reload()
            } label: {
                Text("Try Again")
                    .frame(width: 120, height: 32)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Browser Tab Component

struct BrowserTab: View {
    let session: BrowserSession
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isCloseHovering = false

    var displayTitle: String {
        // If title exists and is not empty, use it
        if let title = session.title, !title.isEmpty {
            return title
        }

        // If URL exists and is not empty, use it
        if let url = session.url, !url.isEmpty {
            return url
        }

        // Default to "New Tab"
        return "New Tab"
    }

    var body: some View {
        HStack(spacing: 6) {
            // Favicon placeholder
            Image(systemName: "globe")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            // Title
            Text(displayTitle)
                .font(.system(size: 11))
                .foregroundColor(isSelected ? .primary : .secondary)
                .lineLimit(1)

            // Close button
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(isCloseHovering ? .primary : .secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 16, height: 16)
            .onHover { hovering in
                isCloseHovering = hovering
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .frame(minWidth: 120, maxWidth: 200)
        .background(isSelected ? Color(NSColor.textBackgroundColor) : Color(NSColor.controlBackgroundColor).opacity(0.3))
        .overlay(
            Rectangle()
                .fill(isSelected ? Color.accentColor : Color.clear)
                .frame(height: 2),
            alignment: .top
        )
        .overlay(
            Rectangle()
                .fill(Color(NSColor.separatorColor))
                .frame(width: 1),
            alignment: .trailing
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
    }
}

// MARK: - Empty Tab State Component

struct EmptyTabStateView: View {
    @ObservedObject var manager: BrowserSessionManager
    @State private var urlInput: String = ""

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen.app", category: "BrowserTab")

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "globe")
                .font(.system(size: 64))
                .foregroundStyle(.tertiary)

            urlTextField
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var urlTextField: some View {
        if #available(macOS 15.0, *) {
            TextField("Enter URL or search", text: $urlInput)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .frame(maxWidth: 600)
                .onSubmit(handleURLSubmit)
        } else {
            TextField("Enter URL or search", text: $urlInput)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 16))
                .frame(maxWidth: 600)
                .padding(.vertical, 8)
                .onSubmit(handleURLSubmit)
        }
    }

    private func handleURLSubmit() {
        let trimmedInput = urlInput.trimmingCharacters(in: .whitespaces)
        guard !trimmedInput.isEmpty else { return }

        // Wrap in error handling to prevent crashes
        do {
            let normalizedURL = URLNormalizer.normalize(trimmedInput)

            // Validate URL before navigating
            guard !normalizedURL.isEmpty else { return }

            manager.navigateToURL(normalizedURL)
            urlInput = ""
        } catch {
            Self.logger.error("Error handling URL submission: \(error)")
            // Clear input on error
            urlInput = ""
        }
    }
}
