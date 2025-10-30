//
//  WorktreeDetailView.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import SwiftUI

struct WorktreeDetailView: View {
    @ObservedObject var worktree: Worktree
    @ObservedObject var repositoryManager: RepositoryManager
    @ObservedObject var appDetector = AppDetector.shared

    @State private var selectedTab = "chat"
    @State private var selectedChatSessionId: UUID?
    @State private var selectedTerminalSessionId: UUID?
    @State private var gitAdditions = 0
    @State private var gitDeletions = 0
    @State private var gitUntrackedFiles = 0
    @State private var isLoadingGitStatus = false
    @State private var gitStatusTimer: Timer?
    @State private var lastOpenedApp: DetectedApp?

    var chatSessions: [ChatSession] {
        let sessions = (worktree.chatSessions as? Set<ChatSession>) ?? []
        return sessions.sorted { ($0.createdAt ?? Date()) < ($1.createdAt ?? Date()) }
    }

    var terminalSessions: [TerminalSession] {
        let sessions = (worktree.terminalSessions as? Set<TerminalSession>) ?? []
        return sessions.sorted { ($0.createdAt ?? Date()) < ($1.createdAt ?? Date()) }
    }

    var hasActiveSessions: Bool {
        (selectedTab == "chat" && !chatSessions.isEmpty) || (selectedTab == "terminal" && !terminalSessions.isEmpty)
    }

    var hasGitChanges: Bool {
        gitAdditions > 0 || gitDeletions > 0 || gitUntrackedFiles > 0
    }
    
    

    @ViewBuilder
    var contentView: some View {
        Group {
            if selectedTab == "chat" {
                ChatTabView(
                    worktree: worktree,
                    selectedSessionId: $selectedChatSessionId
                )
            } else {
                TerminalTabView(
                    worktree: worktree,
                    selectedSessionId: $selectedTerminalSessionId,
                    repositoryManager: repositoryManager
                )
            }
        }
    }

    @ToolbarContentBuilder
    var sessionToolbarItems: some ToolbarContent {

        ToolbarItem(placement: .automatic) {
            SessionTabsScrollView(
                selectedTab: selectedTab,
                chatSessions: chatSessions,
                terminalSessions: terminalSessions,
                selectedChatSessionId: $selectedChatSessionId,
                selectedTerminalSessionId: $selectedTerminalSessionId,
                onCloseChatSession: closeChatSession,
                onCloseTerminalSession: closeTerminalSession
            )
        }

        ToolbarItem(placement: .automatic) {
            if selectedTab == "chat" {
                Button {
                    createNewChatSession()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11))
                }
                .help(String(localized: "worktree.session.newChat"))
            } else {
                Button {
                    createNewTerminalSession()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11))
                }
                .help(String(localized: "worktree.session.newTerminal"))
            }
        }

    }

    @ToolbarContentBuilder
    var appAndGitToolbarItems: some ToolbarContent {
        ToolbarItem {
            OpenInAppButton(
                lastOpenedApp: lastOpenedApp,
                appDetector: appDetector,
                onOpenInLastApp: openInLastApp,
                onOpenInDetectedApp: openInDetectedApp
            )
        }

        if #available(macOS 26.0, *) {
            ToolbarSpacer(.fixed)
        } else {
            ToolbarItem(placement: .automatic) {
                Spacer().fixedSize()
            }
        }

        ToolbarItem(placement: .automatic) {
            if hasGitChanges {
                GitStatusView(
                    additions: gitAdditions,
                    deletions: gitDeletions,
                    untrackedFiles: gitUntrackedFiles
                )
            }
        }
    }

    var body: some View {
        NavigationStack {
            contentView
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(worktree.branch ?? String(localized: "worktree.session.worktree"))
            .toolbarBackground(.visible, for: .windowToolbar)
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Picker(String(localized: "worktree.session.tab"), selection: $selectedTab) {
                        Label(String(localized: "worktree.session.chat"), systemImage: "message").tag("chat")
                        Label(String(localized: "worktree.session.terminal"), systemImage: "terminal").tag("terminal")
                    }
                    .pickerStyle(.segmented)
                }
                
                
                if #available(macOS 26.0, *) {
                    ToolbarSpacer()
                } else {
                    ToolbarItem(placement: .automatic) {
                        Spacer().fixedSize()
                    }
                }

                if hasActiveSessions {
                    sessionToolbarItems
                }
                
                if #available(macOS 26.0, *) {
                    ToolbarSpacer()
                } else {
                    ToolbarItem(placement: .automatic) {
                        Spacer().fixedSize()
                    }
                }

                appAndGitToolbarItems
            }
            .task {
                await loadGitStatus()
                startPeriodicRefresh()
            }
            .onDisappear {
                gitStatusTimer?.invalidate()
                gitStatusTimer = nil
            }
        }
    }

    private func startPeriodicRefresh() {
        gitStatusTimer?.invalidate()
        gitStatusTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            Task {
                await loadGitStatus()
            }
        }
    }

    private func loadGitStatus() async {
        isLoadingGitStatus = true
        defer { isLoadingGitStatus = false }

        guard let path = worktree.path else { return }

        do {
            // Get numstat for additions/deletions (both staged and unstaged)
            let diffProcess = Process()
            diffProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            diffProcess.arguments = ["diff", "--numstat", "HEAD"]
            diffProcess.currentDirectoryURL = URL(fileURLWithPath: path)

            let diffPipe = Pipe()
            diffProcess.standardOutput = diffPipe

            try diffProcess.run()
            diffProcess.waitUntilExit()

            let diffData = diffPipe.fileHandleForReading.readDataToEndOfFile()
            let diffOutput = String(data: diffData, encoding: .utf8) ?? ""

            var additions = 0
            var deletions = 0

            for line in diffOutput.components(separatedBy: .newlines) {
                let parts = line.split(separator: "\t")
                if parts.count >= 2 {
                    if let add = Int(parts[0]) {
                        additions += add
                    }
                    if let del = Int(parts[1]) {
                        deletions += del
                    }
                }
            }

            // Get status for new/untracked files and staged additions
            let statusProcess = Process()
            statusProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            statusProcess.arguments = ["status", "--porcelain"]
            statusProcess.currentDirectoryURL = URL(fileURLWithPath: path)

            let statusPipe = Pipe()
            statusProcess.standardOutput = statusPipe

            try statusProcess.run()
            statusProcess.waitUntilExit()

            let statusData = statusPipe.fileHandleForReading.readDataToEndOfFile()
            let statusOutput = String(data: statusData, encoding: .utf8) ?? ""

            let lines = statusOutput.components(separatedBy: .newlines)

            // Count untracked files (??), added files (A ), and new files in index (AM, A )
            let untrackedCount = lines.filter { $0.hasPrefix("??") || $0.hasPrefix("A ") || $0.hasPrefix("AM") }.count

            await MainActor.run {
                gitAdditions = additions
                gitDeletions = deletions
                gitUntrackedFiles = untrackedCount
            }
        } catch {
            print("Failed to load git status: \(error)")
        }
    }

    private func closeChatSession(_ session: ChatSession) {
        guard let context = worktree.managedObjectContext else { return }

        if let id = session.id {
            ChatSessionManager.shared.removeAgentSession(for: id)
        }

        if selectedChatSessionId == session.id {
            if let index = chatSessions.firstIndex(where: { $0.id == session.id }) {
                if index > 0 {
                    selectedChatSessionId = chatSessions[index - 1].id
                } else if chatSessions.count > 1 {
                    selectedChatSessionId = chatSessions[index + 1].id
                } else {
                    selectedChatSessionId = nil
                }
            }
        }

        context.delete(session)

        do {
            try context.save()
        } catch {
            print("Failed to delete chat session: \(error)")
        }
    }

    private func closeTerminalSession(_ session: TerminalSession) {
        guard let context = worktree.managedObjectContext else { return }

        if let id = session.id {
            TerminalSessionManager.shared.removeAllTerminals(for: id)
        }

        if selectedTerminalSessionId == session.id {
            if let index = terminalSessions.firstIndex(where: { $0.id == session.id }) {
                if index > 0 {
                    selectedTerminalSessionId = terminalSessions[index - 1].id
                } else if terminalSessions.count > 1 {
                    selectedTerminalSessionId = terminalSessions[index + 1].id
                } else {
                    selectedTerminalSessionId = nil
                }
            }
        }

        context.delete(session)

        do {
            try context.save()
        } catch {
            print("Failed to delete terminal session: \(error)")
        }
    }

    private func openInLastApp() {
        guard let app = lastOpenedApp else {
            // Open in Finder by default
            if let finder = appDetector.getApps(for: .finder).first {
                openInDetectedApp(finder)
            }
            return
        }
        openInDetectedApp(app)
    }

    private func openInDetectedApp(_ app: DetectedApp) {
        guard let path = worktree.path else { return }
        lastOpenedApp = app
        appDetector.openPath(path, with: app)
    }

    private func createNewChatSession() {
        guard let context = worktree.managedObjectContext else { return }

        let session = ChatSession(context: context)
        session.id = UUID()
        let defaultAgent = AgentRouter().defaultAgent
        session.title = defaultAgent.capitalized
        session.agentName = defaultAgent
        session.createdAt = Date()
        session.worktree = worktree

        do {
            try context.save()
            selectedChatSessionId = session.id
        } catch {
            print("Failed to create chat session: \(error)")
        }
    }

    private func createNewTerminalSession() {
        guard let context = worktree.managedObjectContext else { return }

        let terminalSessions = (worktree.terminalSessions as? Set<TerminalSession>) ?? []

        let session = TerminalSession(context: context)
        session.id = UUID()
        session.title = String(localized: "worktree.session.terminalTitle \(terminalSessions.count + 1)")
        session.createdAt = Date()
        session.worktree = worktree

        do {
            try context.save()
            selectedTerminalSessionId = session.id
        } catch {
            print("Failed to create terminal session: \(error)")
        }
    }
}

struct DetailsTabView: View {
    @ObservedObject var worktree: Worktree
    @ObservedObject var repositoryManager: RepositoryManager

    @State private var currentBranch = ""
    @State private var ahead = 0
    @State private var behind = 0
    @State private var isLoading = false
    @State private var showingDeleteConfirmation = false
    @State private var hasUnsavedChanges = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: worktree.isPrimary ? "arrow.triangle.branch" : "arrow.triangle.2.circlepath")
                        .font(.system(size: 48))
                        .foregroundStyle(.blue)

                    Text(worktree.branch ?? "Unknown")
                        .font(.title)
                        .fontWeight(.bold)

                    if worktree.isPrimary {
                        Text("worktree.detail.primary", bundle: .main)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(.blue, in: Capsule())
                    }
                }
                .padding(.top, 32)

                // Branch status
                if isLoading {
                    ProgressView()
                        .controlSize(.large)
                } else {
                    VStack(spacing: 12) {
                        if ahead > 0 || behind > 0 {
                            HStack(spacing: 20) {
                                if ahead > 0 {
                                    Label {
                                        Text(String(localized: "worktree.detail.ahead \(ahead)"))
                                    } icon: {
                                        Image(systemName: "arrow.up.circle.fill")
                                            .foregroundStyle(.green)
                                    }
                                }

                                if behind > 0 {
                                    Label {
                                        Text(String(localized: "worktree.detail.behind \(behind)"))
                                    } icon: {
                                        Image(systemName: "arrow.down.circle.fill")
                                            .foregroundStyle(.orange)
                                    }
                                }
                            }
                            .font(.callout)
                        } else {
                            Label(String(localized: "worktree.detail.upToDate"), systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                }

                // Info section
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        InfoRow(label: String(localized: "worktree.detail.path"), value: worktree.path ?? String(localized: "worktree.list.unknown"))
                        Divider()
                        InfoRow(label: String(localized: "worktree.detail.branch"), value: currentBranch.isEmpty ? (worktree.branch ?? String(localized: "worktree.list.unknown")) : currentBranch)

                        if let lastAccessed = worktree.lastAccessed {
                            Divider()
                            InfoRow(label: String(localized: "worktree.detail.lastAccessed"), value: lastAccessed.formatted(date: .abbreviated, time: .shortened))
                        }
                    }
                    .padding(4)
                }
                .padding(.horizontal)

                // Actions
                VStack(spacing: 12) {
                    Text("worktree.detail.actions", bundle: .main)
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)

                    VStack(spacing: 8) {
                        ActionButton(
                            title: String(localized: "worktree.detail.openTerminal"),
                            icon: "terminal",
                            color: .blue
                        ) {
                            openInTerminal()
                        }

                        ActionButton(
                            title: String(localized: "worktree.detail.openFinder"),
                            icon: "folder",
                            color: .orange
                        ) {
                            openInFinder()
                        }

                        ActionButton(
                            title: String(localized: "worktree.detail.openEditor"),
                            icon: "chevron.left.forwardslash.chevron.right",
                            color: .purple
                        ) {
                            openInEditor()
                        }

                        if !worktree.isPrimary {
                            ActionButton(
                                title: String(localized: "worktree.detail.delete"),
                                icon: "trash",
                                color: .red
                            ) {
                                checkUnsavedChanges()
                            }
                        }
                    }
                    .padding(.horizontal)
                }

                if let error = errorMessage {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                        .padding(.horizontal)
                }

                Spacer()
            }
        }
        .navigationTitle(String(localized: "worktree.list.title"))
        .toolbar {
            Button {
                refreshStatus()
            } label: {
                Label(String(localized: "worktree.detail.refresh"), systemImage: "arrow.clockwise")
            }
        }
        .task {
            refreshStatus()
        }
        .alert(hasUnsavedChanges ? String(localized: "worktree.detail.unsavedChangesTitle") : String(localized: "worktree.detail.deleteConfirmTitle"), isPresented: $showingDeleteConfirmation) {
            Button(String(localized: "worktree.create.cancel"), role: .cancel) {}
            Button(String(localized: "worktree.detail.delete"), role: .destructive) {
                deleteWorktree()
            }
        } message: {
            if hasUnsavedChanges {
                Text(String(localized: "worktree.detail.unsavedChangesMessage \(worktree.branch ?? String(localized: "worktree.list.unknown"))"))
            } else {
                Text("worktree.detail.deleteConfirmMessage", bundle: .main)
            }
        }
    }

    private func refreshStatus() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let status = try await repositoryManager.getWorktreeStatus(worktree)
                await MainActor.run {
                    currentBranch = status.branch
                    ahead = status.ahead
                    behind = status.behind
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }

    private func openInTerminal() {
        guard let path = worktree.path else { return }
        repositoryManager.openInTerminal(path)
        updateLastAccessed()
    }

    private func openInFinder() {
        guard let path = worktree.path else { return }
        repositoryManager.openInFinder(path)
        updateLastAccessed()
    }

    private func openInEditor() {
        guard let path = worktree.path else { return }
        repositoryManager.openInEditor(path)
        updateLastAccessed()
    }

    private func checkUnsavedChanges() {
        Task {
            do {
                let changes = try await repositoryManager.hasUnsavedChanges(worktree)
                await MainActor.run {
                    hasUnsavedChanges = changes
                    showingDeleteConfirmation = true
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func deleteWorktree() {
        Task {
            do {
                try await repositoryManager.deleteWorktree(worktree, force: hasUnsavedChanges)
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func updateLastAccessed() {
        do {
            try repositoryManager.updateWorktreeAccess(worktree)
        } catch {
            print("Failed to update last accessed: \(error)")
        }
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)

            Text(value)
                .font(.subheadline)
                .textSelection(.enabled)

            Spacer()
        }
    }
}

struct ActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .frame(width: 20)

                Text(title)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
                    .font(.caption)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - App Menu Label with Icon

struct AppMenuLabel: View {
    let app: DetectedApp

    private func resizedIcon(_ image: NSImage, size: CGSize) -> NSImage {
        let newImage = NSImage(size: size)
        newImage.lockFocus()
        image.draw(
            in: NSRect(origin: .zero, size: size),
            from: NSRect(origin: .zero, size: image.size),
            operation: .sourceOver,
            fraction: 1.0
        )
        newImage.unlockFocus()
        return newImage
    }

    var body: some View {
        HStack(spacing: 6) {
            if let icon = app.icon {
                Image(nsImage: resizedIcon(icon, size: CGSize(width: 16, height: 16)))
                    .renderingMode(.original)
            }
            Text(app.name)
        }
    }
}

#Preview {
    WorktreeDetailView(
        worktree: Worktree(),
        repositoryManager: RepositoryManager(viewContext: PersistenceController.preview.container.viewContext)
    )
}

// MARK: - Session Tab Button

struct SessionTabButton<Content: View>: View {
    let isSelected: Bool
    let action: () -> Void
    let content: Content

    @State private var isHovering = false

    init(isSelected: Bool, action: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.isSelected = isSelected
        self.action = action
        self.content = content()
    }


    var body: some View {
        Button(action: action) {
            content
                .padding(6)
                .background(
                    isSelected ?
                    Color(nsColor: .separatorColor) :
                    (isHovering ? Color(nsColor: .separatorColor).opacity(0.5) : Color.clear),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// MARK: - Session Tabs ScrollView

struct SessionTabsScrollView: View {
    let selectedTab: String
    let chatSessions: [ChatSession]
    let terminalSessions: [TerminalSession]
    @Binding var selectedChatSessionId: UUID?
    @Binding var selectedTerminalSessionId: UUID?
    let onCloseChatSession: (ChatSession) -> Void
    let onCloseTerminalSession: (TerminalSession) -> Void

    var body: some View {
        ZStack(alignment: .trailing) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    if selectedTab == "chat" && !chatSessions.isEmpty {
                        ForEach(chatSessions) { session in
                            SessionTabButton(
                                isSelected: selectedChatSessionId == session.id,
                                action: { selectedChatSessionId = session.id }
                            ) {
                                HStack(spacing: 6) {
                                    AgentIconView(agent: session.agentName ?? "claude", size: 14)

                                    Text(session.title ?? session.agentName?.capitalized ?? String(localized: "worktree.session.chat"))
                                        .font(.callout)

                                    Button {
                                        onCloseChatSession(session)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 10))
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                        }
                    } else if selectedTab == "terminal" && !terminalSessions.isEmpty {
                        ForEach(terminalSessions) { session in
                            SessionTabButton(
                                isSelected: selectedTerminalSessionId == session.id,
                                action: { selectedTerminalSessionId = session.id }
                            ) {
                                HStack(spacing: 6) {
                                    Image(systemName: "terminal")
                                        .font(.system(size: 12))
                                    Text(session.title ?? String(localized: "worktree.session.terminal"))
                                        .font(.callout)

                                    Button {
                                        onCloseTerminalSession(session)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 10))
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 6)
            }
            .frame(maxWidth: 600)
        }
        .frame(maxWidth: 600)
    }
}

// MARK: - Open In App Button

struct OpenInAppButton: View {
    let lastOpenedApp: DetectedApp?
    @ObservedObject var appDetector: AppDetector
    let onOpenInLastApp: () -> Void
    let onOpenInDetectedApp: (DetectedApp) -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button {
                onOpenInLastApp()
            } label: {
                if let app = lastOpenedApp {
                    AppMenuLabel(app: app)
                } else if let finder = appDetector.getApps(for: .finder).first {
                    AppMenuLabel(app: finder)
                } else {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 11))
                }
            }
            .buttonStyle(.borderless)
            .padding(8)
            .help(lastOpenedApp?.name ?? "Open in Finder")

            Divider()
                .frame(height: 16)

            Menu {
                if let finder = appDetector.getApps(for: .finder).first {
                    Button {
                        onOpenInDetectedApp(finder)
                    } label: {
                        AppMenuLabel(app: finder)
                    }
                    .buttonStyle(.plain)
                }

                let terminals = appDetector.getTerminals()
                if !terminals.isEmpty {
                    Divider()
                    ForEach(terminals) { app in
                        Button {
                            onOpenInDetectedApp(app)
                        } label: {
                            AppMenuLabel(app: app)
                                .imageScale(.small)
                        }.buttonStyle(.borderless)
    
                    }
                }

                let editors = appDetector.getEditors()
                if !editors.isEmpty {
                    Divider()
                    ForEach(editors) { app in
                        Button {
                            onOpenInDetectedApp(app)
                        } label: {
                            AppMenuLabel(app: app)
                                .imageScale(.small)
                        }
           
                    }
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8))
            }
            .buttonStyle(.borderless)
            .padding(8)
            .imageScale(.small)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }
}

// MARK: - Git Status View

struct GitStatusView: View {
    let additions: Int
    let deletions: Int
    let untrackedFiles: Int

    var body: some View {
        Button {
            print("git status")
        } label: {
        
        HStack(spacing: 8) {
            if additions > 0 {
                Text("+\(additions)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.green)
                    .transition(.opacity)
            }

            if deletions > 0 {
                Text("-\(deletions)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.red)
                    .transition(.opacity)
            }

            if untrackedFiles > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 10))
                    Text("\(untrackedFiles)")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(.orange)
                .transition(.opacity)
            }
        }
        .buttonStyle(.automatic)
        .animation(.easeInOut(duration: 0.2), value: additions)
        .animation(.easeInOut(duration: 0.2), value: deletions)
        .animation(.easeInOut(duration: 0.2), value: untrackedFiles)
      }
    }
}

