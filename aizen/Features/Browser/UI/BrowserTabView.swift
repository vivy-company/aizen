import ACP
import CoreData
import SwiftUI
import WebKit

struct BrowserTabView: View {
    let worktree: Worktree
    let isSelected: Bool
    @Binding var selectedSessionId: UUID?

    @StateObject private var manager: BrowserSessionStore

    init(worktree: Worktree, selectedSessionId: Binding<UUID?>, isSelected: Bool = true) {
        self.worktree = worktree
        self.isSelected = isSelected
        self._selectedSessionId = selectedSessionId

        // Initialize manager with worktree and viewContext
        let context = PersistenceController.shared.container.viewContext
        _manager = StateObject(wrappedValue: BrowserSessionStore(viewContext: context, worktree: worktree))
    }

    init(manager: BrowserSessionStore, selectedSessionId: Binding<UUID?>, isSelected: Bool = true) {
        self.worktree = manager.worktree
        self.isSelected = isSelected
        self._selectedSessionId = selectedSessionId
        _manager = StateObject(wrappedValue: manager)
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            // Session tabs - always visible
            BrowserSessionTabsView(manager: manager)

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
                                existingWebView: manager.cachedWebView(for: sessionId),
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
            syncSelectionState()
        }
        .task(id: isSelected) {
            guard isSelected else { return }
            syncSelectionState()
        }
        .task(id: manager.activeSessionId) {
            // Keep binding synced with manager state
            selectedSessionId = manager.activeSessionId
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
        .background(AppSurfaceTheme.backgroundColor())
    }

    private func syncSelectionState() {
        if manager.sessions.isEmpty, isSelected {
            manager.createSession()
        }

        if selectedSessionId == nil {
            selectedSessionId = manager.activeSessionId
        } else if let sessionId = selectedSessionId,
                  sessionId != manager.activeSessionId {
            manager.selectSession(sessionId)
        }
    }
}

// MARK: - Browser Tab Component

struct BrowserTab: View {
    let session: BrowserSession
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

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
        TabContainer(isSelected: isSelected, onSelect: onSelect) {
            TabLabel(
                title: displayTitle,
                isSelected: isSelected,
                onClose: onClose
            ) {
                Image(systemName: "globe")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            } trailing: {
                EmptyView()
            }
        }
    }
}

// MARK: - Empty Tab State Component

struct EmptyTabStateView: View {
    @ObservedObject var manager: BrowserSessionStore
    @State private var urlInput: String = ""

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "globe")
                .font(.system(size: 64))
                .foregroundStyle(.tertiary)

            urlTextField
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppSurfaceTheme.backgroundColor())
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

        let normalizedURL = URLNormalizer.normalize(trimmedInput)

        // Validate URL before navigating
        guard !normalizedURL.isEmpty else { return }

        manager.navigateToURL(normalizedURL)
        urlInput = ""
    }
}
