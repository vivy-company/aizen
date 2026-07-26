import AizenCore
import AppKit
import SwiftUI

/// A complete Mac Client path for projectless Reignition conversations.
/// It is intentionally independent from the legacy worktree/Core Data navigation tree.
struct ReignitionConversationWindow: View {
    @StateObject private var store: ReignitionConversationStore
    @State private var selectedSpaceID: SpaceID?
    @State private var draft = ""
    @State private var newConversationTitle = ""

    init(host: ReignitionHostComposition) {
        _store = StateObject(wrappedValue: ReignitionConversationStore(host: host))
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
        }
        .task(id: selectedSpaceID) { await store.refresh(spaceID: selectedSpaceID) }
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
    }

    @ViewBuilder
    private var conversationDetail: some View {
        if let conversationID = store.selectedConversationID,
            let conversation = store.conversations.first(where: { $0.id == conversationID }) {
            VStack(spacing: 0) {
                HStack {
                    if let resource = store.folderResource(for: conversation) {
                        Label(resource.title, systemImage: "folder")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Label("No folder attached", systemImage: "folder")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
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

    private var errorAlert: Binding<Bool> {
        Binding(
            get: { store.lastError != nil },
            set: { if !$0 { store.dismissError() } }
        )
    }

    private func createConversation() {
        guard let selectedSpaceID else { return }
        let title = newConversationTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        newConversationTitle = ""
        guard !title.isEmpty else { return }
        Task { await store.createConversation(spaceID: selectedSpaceID, title: title) }
    }

    @ViewBuilder
    private func folderMenu(for conversation: Session) -> some View {
        Menu("Attach Folder", systemImage: "folder.badge.plus") {
            let folderResources = store.resources.filter { $0.kind == .folder }
            if !folderResources.isEmpty {
                Section("Existing Folders") {
                    ForEach(folderResources) { resource in
                        Button(resource.title) {
                            Task { await store.attach(resourceID: resource.id, to: conversation.id) }
                        }
                    }
                }
            }
            Button("Choose Folder\u{2026}") {
                chooseFolder(for: conversation.id)
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
}
