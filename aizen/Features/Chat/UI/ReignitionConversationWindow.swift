import AizenCore
import AizenClient
import AizenWire
import AppKit
import Combine
import GhosttyKit
import SwiftUI
import WebKit

/// A complete Mac Client path for projectless Reignition conversations.
/// It is intentionally independent from the legacy worktree/Core Data navigation tree.
struct ReignitionConversationWindow: View {
    @StateObject private var store: ReignitionConversationStore
    @State private var selectedSpaceID: SpaceID?
    @State private var draft = ""
    @State private var newConversationTitle = ""
    @State private var newSpaceName = ""
    @State private var contextCreation: ReignitionContextCreation?
    @State private var terminalPresentation: ReignitionTerminalPresentation?
    @State private var fileBrowserContext: ExecutionContext?
    @State private var showingLicenseDeepLinkSheet = false
    @State private var webBrowserResource: Resource?
    @State private var newWebURL = ""

    init(host: ReignitionHostComposition) {
        let cursorURL = ReignitionHostComposition.defaultStorageURL()
            .deletingLastPathComponent()
            .appendingPathComponent("reignition-journal-cursor.json")
        _store = StateObject(
            wrappedValue: ReignitionConversationStore(
                host: host,
                journalCursorStore: FileJournalCursorStore(url: cursorURL)
            )
        )
    }

    var body: some View {
        NavigationSplitView {
            List(selection: conversationSelection) {
                Section("Spaces") {
                    Picker("Space", selection: $selectedSpaceID) {
                        Text("All Spaces").tag(SpaceID?.none)
                        ForEach(store.spaces) { space in
                            Text(space.name).tag(Optional(space.id))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    Button("New Space…", systemImage: "plus") {
                        newSpaceName = "New Space"
                    }
                    Label(connectionStateTitle, systemImage: connectionStateSymbol)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Conversations") {
                    ForEach(store.conversations) { conversation in
                        Text(conversation.title).tag(conversation.id)
                    }
                }
            }
            .navigationTitle("Conversations")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("New Conversation", systemImage: "square.and.pencil") {
                        newConversationTitle = "New Conversation"
                    }
                    .disabled(selectedSpaceID == nil)
                }
            }
        } detail: {
            conversationDetail
        }
        .task {
            await store.refreshSpaces()
            if selectedSpaceID == nil { selectedSpaceID = store.spaces.first?.id }
            openPendingDeepLinkPaths()
            if LicenseStateStore.shared.hasPendingDeepLink {
                showingLicenseDeepLinkSheet = true
            }
        }
        .task(id: selectedSpaceID) { await store.refresh(spaceID: selectedSpaceID) }
        .onReceive(NotificationCenter.default.publisher(for: .openReignitionPath)) { _ in
            openPendingDeepLinkPaths()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openLicenseDeepLink)) { _ in
            showingLicenseDeepLinkSheet = true
        }
        .alert("New Conversation", isPresented: newConversationAlert) {
            TextField("Title", text: $newConversationTitle)
            Button("Create") { createConversation() }
            Button("Cancel", role: .cancel) { newConversationTitle = "" }
        }
        .alert("Conversation Error", isPresented: errorAlert) {
            Button("OK") { store.dismissError() }
        } message: {
            Text(store.lastError ?? "An unknown error occurred.")
        }
        .alert("New Space", isPresented: newSpaceAlert) {
            TextField("Name", text: $newSpaceName)
            Button("Create") { createSpace() }
            Button("Cancel", role: .cancel) { newSpaceName = "" }
        }
        .alert("Open Web Resource", isPresented: newWebResourceAlert) {
            TextField("https://example.com", text: $newWebURL)
            Button("Open") { openWebResource() }
            Button("Cancel", role: .cancel) { newWebURL = "" }
        }
        .sheet(item: $contextCreation) { creation in
            ReignitionContextCreationSheet(creation: creation) { destinationPath, branch in
                contextCreation = nil
                createContext(creation, destinationPath: destinationPath, branch: branch)
            } onCancel: {
                contextCreation = nil
            }
        }
        .sheet(item: $terminalPresentation) { presentation in
            ReignitionTerminalSheet(store: store, presentation: presentation)
        }
        .sheet(item: $fileBrowserContext) { context in
            ReignitionContextFilesSheet(store: store, context: context)
        }
        .sheet(item: $webBrowserResource) { resource in
            ReignitionWebBrowserSheet(resource: resource)
        }
        .sheet(isPresented: $showingLicenseDeepLinkSheet) {
            LicenseDeepLinkSheet(
                licenseManager: LicenseStateStore.shared,
                onOpenSettings: { ReignitionHostSettingsWindowController.shared.show() }
            )
        }
    }

    @ViewBuilder
    private var conversationDetail: some View {
        if let conversationID = store.selectedConversationID,
            let conversation = store.conversations.first(where: { $0.id == conversationID }) {
            VStack(spacing: 0) {
                HStack {
                    if let resource = store.resource(for: conversation) {
                        Label(resource.title, systemImage: resource.kind == .repository ? "folder.badge.gearshape" : "folder")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if resource.kind == .repository {
                            repositoryState(resource)
                            Button("Refresh Repository", systemImage: "arrow.clockwise") {
                                Task { await store.refreshRepository(resourceID: resource.id) }
                            }
                            .labelStyle(.iconOnly)
                            .disabled(store.isSynchronizing)
                        }
                    } else {
                        Label("No folder attached", systemImage: "folder")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Open Terminal", systemImage: "terminal") {
                        openTerminal(for: conversation.id)
                    }
                    .disabled(conversation.executionContextID == nil || store.isSynchronizing)
                    Button("Browse Files", systemImage: "folder") {
                        fileBrowserContext = conversation.executionContextID.flatMap { id in
                            store.executionContexts.first(where: { $0.id == id })
                        }
                    }
                    .disabled(conversation.executionContextID == nil || store.isSynchronizing)
                    webResourceMenu(for: conversation)
                    folderMenu(for: conversation)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                Divider()
                List(store.messages) { message in
                    VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                        Text(message.role.rawValue.capitalized)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(message.content)
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
                }
                if let liveAssistantText = store.liveAssistantText {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Assistant")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(liveAssistantText)
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
                Divider()
                HStack(alignment: .bottom) {
                    TextField("Message", text: $draft, axis: .vertical)
                        .lineLimit(1...6)
                    Button("Send") {
                        let content = draft
                        draft = ""
                        Task { await store.send(content: content) }
                    }
                    .disabled(draft.isEmpty || store.isSynchronizing)
                }
                .padding()
            }
            .navigationTitle(conversation.title)
        } else {
            ContentUnavailableView("Select a Conversation", systemImage: "bubble.left.and.bubble.right")
        }
    }

    private var conversationSelection: Binding<SessionID?> {
        Binding(
            get: { store.selectedConversationID },
            set: { sessionID in Task { await store.select(sessionID) } }
        )
    }

    private var newConversationAlert: Binding<Bool> {
        Binding(
            get: { !newConversationTitle.isEmpty },
            set: { if !$0 { newConversationTitle = "" } }
        )
    }

    private var newSpaceAlert: Binding<Bool> {
        Binding(
            get: { !newSpaceName.isEmpty },
            set: { if !$0 { newSpaceName = "" } }
        )
    }

    private var newWebResourceAlert: Binding<Bool> {
        Binding(
            get: { !newWebURL.isEmpty },
            set: { if !$0 { newWebURL = "" } }
        )
    }

    private var errorAlert: Binding<Bool> {
        Binding(
            get: { store.lastError != nil },
            set: { if !$0 { store.dismissError() } }
        )
    }

    private var connectionStateTitle: String {
        switch store.connectionState {
        case .disconnected: "Disconnected"
        case .connecting: "Connecting"
        case .synchronizing: "Synchronizing"
        case .ready(_): "Ready"
        case .reconnecting: "Reconnecting"
        case .blocked: "Blocked"
        case .failed: "Connection failed"
        }
    }

    private var connectionStateSymbol: String {
        switch store.connectionState {
        case .ready(_): "checkmark.circle"
        case .blocked, .failed: "exclamationmark.triangle"
        default: "arrow.triangle.2.circlepath"
        }
    }

    private func createConversation() {
        guard let selectedSpaceID else { return }
        let title = newConversationTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        newConversationTitle = ""
        guard !title.isEmpty else { return }
        Task { await store.createConversation(spaceID: selectedSpaceID, title: title) }
    }

    private func openPendingDeepLinkPaths() {
        let paths = DeepLinkHandler.shared.takePendingLocalPaths()
        guard !paths.isEmpty else { return }
        Task {
            for url in paths {
                if let spaceID = await store.openLocalPath(url, preferredSpaceID: selectedSpaceID) {
                    selectedSpaceID = spaceID
                }
            }
        }
    }

    private func createSpace() {
        let name = newSpaceName.trimmingCharacters(in: .whitespacesAndNewlines)
        newSpaceName = ""
        guard !name.isEmpty else { return }
        Task {
            if let spaceID = await store.createSpace(name: name) {
                selectedSpaceID = spaceID
            }
        }
    }

    @ViewBuilder
    private func webResourceMenu(for conversation: Session) -> some View {
        Menu("Web", systemImage: "globe") {
            let webResources = store.resources.filter {
                $0.spaceID == conversation.spaceID && $0.kind == .webSource
            }
            if !webResources.isEmpty {
                ForEach(webResources) { resource in
                    Button(resource.title) { webBrowserResource = resource }
                }
                Divider()
            }
            Button("Open URL…", systemImage: "plus") {
                newWebURL = "https://"
            }
        }
        .disabled(store.isSynchronizing)
    }

    private func openWebResource() {
        let input = newWebURL.trimmingCharacters(in: .whitespacesAndNewlines)
        newWebURL = ""
        guard let url = URL(string: input),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else { return }
        guard let conversation = store.conversations.first(where: { $0.id == store.selectedConversationID }) else {
            return
        }
        Task {
            webBrowserResource = await store.importWebResource(spaceID: conversation.spaceID, url: url)
        }
    }

    @ViewBuilder
    private func folderMenu(for conversation: Session) -> some View {
        Menu("Attach Folder", systemImage: "folder.badge.plus") {
            if store.resource(for: conversation) != nil {
                Button("Detach Folder", systemImage: "folder.badge.minus", role: .destructive) {
                    Task { await store.detachExecutionContext(from: conversation.id) }
                }
                Divider()
            }
            let attachableResources = store.resources.filter { $0.kind == .folder || $0.kind == .repository }
            if !attachableResources.isEmpty {
                Section("Existing Resources") {
                    ForEach(attachableResources) { resource in
                        Button(resource.title) {
                            Task { await store.attach(resourceID: resource.id, to: conversation.id) }
                        }
                    }
                }
            }
            let repositories = store.resources.filter { $0.kind == .repository }
            if !repositories.isEmpty {
                Section("Create Repository Context") {
                    ForEach(repositories) { resource in
                        Menu(resource.title) {
                            Button("Linked Worktree…", systemImage: "arrow.triangle.branch") {
                                presentContextCreation(.linkedWorktree, resource: resource, conversation: conversation)
                            }
                            Button("Independent Clone…", systemImage: "arrow.down.forward") {
                                presentContextCreation(.clone, resource: resource, conversation: conversation)
                            }
                            Button("Copied Environment…", systemImage: "doc.on.doc") {
                                presentContextCreation(.copy, resource: resource, conversation: conversation)
                            }
                        }
                    }
                }
            }
            Button("Choose Folder\u{2026}") {
                chooseFolder(for: conversation.id)
            }
            Button("Choose Repository\u{2026}") {
                chooseRepository(for: conversation.id)
            }
        }
        .disabled(store.isSynchronizing)
    }

    private func chooseFolder(for sessionID: SessionID) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Attach Folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await store.importAndAttachFolder(at: url, to: sessionID) }
    }

    private func chooseRepository(for sessionID: SessionID) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Attach Repository"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await store.importAndAttachRepository(at: url, to: sessionID) }
    }

    private func presentContextCreation(
        _ kind: ReignitionContextCreation.Kind,
        resource: Resource,
        conversation: Session
    ) {
        contextCreation = ReignitionContextCreation(
            sessionID: conversation.id,
            resourceID: resource.id,
            kind: kind,
            destinationPath: "",
            branch: "aizen/new-worktree"
        )
    }

    private func createContext(_ creation: ReignitionContextCreation, destinationPath: String, branch: String?) {
        Task {
            switch creation.kind {
            case .linkedWorktree:
                await store.createLinkedWorktree(
                    resourceID: creation.resourceID,
                    to: creation.sessionID,
                    destinationPath: destinationPath,
                    branch: branch ?? "",
                    createBranch: true
                )
            case .clone:
                await store.createIndependentContext(
                    resourceID: creation.resourceID,
                    to: creation.sessionID,
                    destinationPath: destinationPath,
                    mode: .clone
                )
            case .copy:
                await store.createIndependentContext(
                    resourceID: creation.resourceID,
                    to: creation.sessionID,
                    destinationPath: destinationPath,
                    mode: .copy
                )
            }
        }
    }

    private func openTerminal(for sessionID: SessionID) {
        Task {
            guard let terminal = await store.createTerminal(for: sessionID) else { return }
            terminalPresentation = ReignitionTerminalPresentation(
                conversationID: sessionID,
                terminal: terminal
            )
        }
    }

    @ViewBuilder
    private func repositoryState(_ resource: Resource) -> some View {
        if let state = store.repositoryStateByResourceID[resource.id] {
            Label(repositoryStateTitle(state), systemImage: repositoryStateSymbol(state))
                .font(.caption)
                .foregroundStyle(repositoryStateColor(state))
        }
    }

    private func repositoryStateTitle(_ state: RefreshRepositoryResourceResultPayload) -> String {
        switch state.availability {
        case .available:
            var title = state.branch ?? (state.isDetached ? "Detached HEAD" : "Repository ready")
            if state.isRebaseInProgress { title += " · Rebase" }
            if state.hasSubmodules { title += " · Submodules" }
            return title
        case .missing: return "Repository missing"
        case .notRepository: return "Not a repository"
        }
    }

    private func repositoryStateSymbol(_ state: RefreshRepositoryResourceResultPayload) -> String {
        state.availability == .available ? "checkmark.circle" : "exclamationmark.triangle"
    }

    private func repositoryStateColor(_ state: RefreshRepositoryResourceResultPayload) -> Color {
        state.availability == .available ? .secondary : .orange
    }
}

private struct ReignitionContextFilesSheet: View {
    @ObservedObject var store: ReignitionConversationStore
    let context: ExecutionContext
    @State private var relativePath = ""
    @State private var selectedFile: ContextFileEntry?

    var body: some View {
        NavigationStack {
            List(store.contextFiles) { entry in
                if entry.isDirectory {
                    Button {
                        relativePath = entry.relativePath
                    } label: {
                        Label(entry.name, systemImage: "folder")
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        selectedFile = entry
                    } label: {
                        Label(entry.name, systemImage: "doc.text")
                    }
                    .buttonStyle(.plain)
                }
            }
            .overlay {
                if store.contextFiles.isEmpty && !store.isSynchronizing {
                    ContentUnavailableView("No Files", systemImage: "folder")
                }
            }
            .navigationTitle(relativePath.isEmpty ? "Files" : relativePath)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if !relativePath.isEmpty {
                        Button("Back", systemImage: "chevron.left") {
                            relativePath = String(relativePath.split(separator: "/").dropLast().joined(separator: "/"))
                        }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Refresh", systemImage: "arrow.clockwise") {
                        Task { await store.loadContextFiles(contextID: context.id, relativePath: relativePath) }
                    }
                    .disabled(store.isSynchronizing)
                }
            }
            .task(id: relativePath) {
                await store.loadContextFiles(contextID: context.id, relativePath: relativePath)
            }
        }
        .sheet(item: $selectedFile) { file in
            ReignitionContextTextFileSheet(store: store, context: context, file: file)
        }
        .frame(minWidth: 380, minHeight: 440)
    }
}

private struct ReignitionContextTextFileSheet: View {
    @ObservedObject var store: ReignitionConversationStore
    let context: ExecutionContext
    let file: ContextFileEntry

    var body: some View {
        Group {
            if store.contextFileTextPath == file.relativePath, let text = store.contextFileText {
                ScrollView([.horizontal, .vertical]) {
                    Text(text)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding()
                }
            } else if store.isSynchronizing {
                ProgressView()
            } else {
                ContentUnavailableView("Unable to Read File", systemImage: "exclamationmark.triangle")
            }
        }
        .navigationTitle(file.name)
        .task(id: file.relativePath) {
            await store.loadContextTextFile(contextID: context.id, relativePath: file.relativePath)
        }
        .frame(minWidth: 620, minHeight: 460)
    }
}

private struct ReignitionWebBrowserSheet: View {
    let resource: Resource
    @State private var url: String
    @State private var canGoBack = false
    @State private var canGoForward = false
    @State private var isLoading = false
    @State private var loadingProgress = 0.0
    @State private var webView: WKWebView?

    init(resource: Resource) {
        self.resource = resource
        guard case let .web(details) = resource.details else {
            preconditionFailure("Web browser presentation requires a web resource")
        }
        _url = State(initialValue: details.url.absoluteString)
    }

    var body: some View {
        VStack(spacing: 0) {
            BrowserControlBar(
                url: $url,
                canGoBack: $canGoBack,
                canGoForward: $canGoForward,
                isLoading: $isLoading,
                loadingProgress: $loadingProgress,
                onBack: { webView?.goBack() },
                onForward: { webView?.goForward() },
                onReload: { webView?.reload() },
                onNavigate: { url = $0 }
            )
            Divider()
            WebViewWrapper(
                url: url,
                canGoBack: $canGoBack,
                canGoForward: $canGoForward,
                onURLChange: { url = $0 },
                onTitleChange: { _ in },
                isLoading: $isLoading,
                loadingProgress: $loadingProgress,
                onWebViewCreated: { webView = $0 }
            )
        }
        .navigationTitle(resource.title)
        .frame(minWidth: 760, minHeight: 520)
    }
}

private struct ReignitionTerminalPresentation: Identifiable {
    let id: UUID
    let conversationID: SessionID
    let terminal: AizenCore.TerminalSession

    init(conversationID: SessionID, terminal: AizenCore.TerminalSession) {
        id = UUID()
        self.conversationID = conversationID
        self.terminal = terminal
    }
}

private struct ReignitionTerminalSheet: View {
    @ObservedObject var store: ReignitionConversationStore
    let presentation: ReignitionTerminalPresentation
    @StateObject private var controller: ReignitionTerminalPresentationController

    init(store: ReignitionConversationStore, presentation: ReignitionTerminalPresentation) {
        self.store = store
        self.presentation = presentation
        _controller = StateObject(
            wrappedValue: ReignitionTerminalPresentationController(initialTerminal: presentation.terminal)
        )
    }

    var body: some View {
        Group {
            if controller.axis == .horizontal {
                HStack(spacing: 1) {
                    terminalPanes
                }
            } else {
                VStack(spacing: 1) {
                    terminalPanes
                }
            }
        }
        .background(Color.black)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Split Right", systemImage: "rectangle.split.2x1") {
                    controller.split(.horizontal, store: store, conversationID: presentation.conversationID)
                }
                Button("Split Down", systemImage: "rectangle.split.1x2") {
                    controller.split(.vertical, store: store, conversationID: presentation.conversationID)
                }
                Button("Close Pane", systemImage: "xmark") {
                    controller.closePane()
                }
                .disabled(controller.terminals.count == 1)
            }
        }
        .onAppear {
            controller.activate(store: store, conversationID: presentation.conversationID)
        }
        .onDisappear {
            controller.deactivate()
        }
        .frame(minWidth: 760, minHeight: 480)
    }

    @ViewBuilder
    private var terminalPanes: some View {
        ForEach(controller.terminals) { terminal in
            ReignitionTerminalSurface(terminal: terminal)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

@MainActor
private final class ReignitionTerminalPresentationController: ObservableObject {
    enum Axis: Equatable {
        case horizontal
        case vertical
    }

    @Published private(set) var terminals: [AizenCore.TerminalSession]
    @Published private(set) var axis: Axis = .horizontal

    private let splitActions = TerminalSplitActions()

    init(initialTerminal: AizenCore.TerminalSession) {
        terminals = [initialTerminal]
    }

    func activate(store: ReignitionConversationStore, conversationID: SessionID) {
        splitActions.configure(
            splitRight: { [weak self] in
                self?.split(.horizontal, store: store, conversationID: conversationID)
            },
            splitLeft: { [weak self] in
                self?.split(.horizontal, store: store, conversationID: conversationID)
            },
            splitDown: { [weak self] in
                self?.split(.vertical, store: store, conversationID: conversationID)
            },
            splitUp: { [weak self] in
                self?.split(.vertical, store: store, conversationID: conversationID)
            },
            closePane: { [weak self] in
                self?.closePane()
            }
        )
        TerminalSplitActionRouter.shared.activate(splitActions)
    }

    func deactivate() {
        TerminalSplitActionRouter.shared.clear(splitActions)
        splitActions.clear()
    }

    func split(
        _ axis: Axis,
        store: ReignitionConversationStore,
        conversationID: SessionID
    ) {
        self.axis = axis
        Task { @MainActor [weak self, store] in
            guard let terminal = await store.createTerminal(for: conversationID) else { return }
            self?.terminals.append(terminal)
        }
    }

    func closePane() {
        guard terminals.count > 1 else { return }
        terminals.removeLast()
    }
}

private struct ReignitionTerminalSurface: NSViewRepresentable {
    let terminal: AizenCore.TerminalSession
    @EnvironmentObject private var ghosttyApp: Ghostty.App

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        guard context.coordinator.surface == nil else { return }
        ghosttyApp.ensureRunning()
        guard let app = ghosttyApp.app,
              let command = attachCommand else { return }
        let surface = AizenTerminalSurfaceView(
            frame: container.bounds,
            worktreePath: FileManager.default.homeDirectoryForCurrentUser.path,
            ghosttyApp: app,
            appWrapper: ghosttyApp,
            paneId: terminal.paneID,
            command: command
        )
        surface.autoresizingMask = [.width, .height]
        container.addSubview(surface)
        context.coordinator.surface = surface
    }

    static func dismantleNSView(_ container: NSView, coordinator: Coordinator) {
        coordinator.surface?.removeFromSuperview()
        coordinator.surface = nil
    }

    private var attachCommand: String? {
        guard terminal.tmuxSessionName.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }),
              let tmux = TmuxSessionSupport.tmuxPath() else { return nil }
        return "\(tmux) attach-session -t \(terminal.tmuxSessionName)"
    }

    final class Coordinator {
        var surface: AizenTerminalSurfaceView?
    }
}

private struct ReignitionContextCreation: Identifiable {
    enum Kind: String {
        case linkedWorktree
        case clone
        case copy

        var title: String {
            switch self {
            case .linkedWorktree: "New Linked Worktree"
            case .clone: "New Independent Clone"
            case .copy: "New Copied Environment"
            }
        }
    }

    let id = UUID()
    let sessionID: SessionID
    let resourceID: ResourceID
    let kind: Kind
    let destinationPath: String
    let branch: String
}

private struct ReignitionContextCreationSheet: View {
    let creation: ReignitionContextCreation
    let onCreate: (String, String?) -> Void
    let onCancel: () -> Void
    @State private var destinationPath: String
    @State private var branch: String

    init(
        creation: ReignitionContextCreation,
        onCreate: @escaping (String, String?) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.creation = creation
        self.onCreate = onCreate
        self.onCancel = onCancel
        _destinationPath = State(initialValue: creation.destinationPath)
        _branch = State(initialValue: creation.branch)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(creation.kind.title)
                .font(.headline)
            TextField("New directory path", text: $destinationPath)
                .textFieldStyle(.roundedBorder)
            if creation.kind == .linkedWorktree {
                TextField("New branch", text: $branch)
                    .textFieldStyle(.roundedBorder)
            }
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Create") {
                    onCreate(
                        destinationPath.trimmingCharacters(in: .whitespacesAndNewlines),
                        creation.kind == .linkedWorktree ? branch.trimmingCharacters(in: .whitespacesAndNewlines) : nil
                    )
                }
                .keyboardShortcut(.defaultAction)
                .disabled(destinationPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (creation.kind == .linkedWorktree && branch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            }
        }
        .padding()
        .frame(width: 460)
    }
}
