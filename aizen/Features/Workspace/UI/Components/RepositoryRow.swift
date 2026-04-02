import AppKit
import SwiftUI
import os.log

struct RepositoryRow: View {
    private let logger = Logger.workspace
    @ObservedObject var repository: Repository
    let isSelected: Bool
    @ObservedObject var repositoryManager: WorkspaceRepositoryStore
    let onSelect: () -> Void
    let onRemove: () -> Void
    @Environment(\.controlActiveState) private var controlActiveState

    @State private var showingRemoveConfirmation = false
    @State private var alsoDeleteFromFilesystem = false
    @State private var showingNoteEditor = false
    @State private var showingPostCreateActions = false

    @AppStorage("defaultTerminalBundleId") private var defaultTerminalBundleId: String?
    @AppStorage("defaultEditorBundleId") private var defaultEditorBundleId: String?

    private var defaultTerminal: DetectedApp? {
        guard let bundleId = defaultTerminalBundleId else { return nil }
        return AppDetector.shared.getTerminals().first { $0.bundleIdentifier == bundleId }
    }

    private var defaultEditor: DetectedApp? {
        guard let bundleId = defaultEditorBundleId else { return nil }
        return AppDetector.shared.getEditors().first { $0.bundleIdentifier == bundleId }
    }

    private var finderApp: DetectedApp? {
        AppDetector.shared.getApps(for: .finder).first
    }

    private func sortedApps(_ apps: [DetectedApp], defaultBundleId: String?) -> [DetectedApp] {
        guard let defaultId = defaultBundleId else { return apps }
        var sorted = apps.filter { $0.bundleIdentifier != defaultId }
        if let defaultApp = apps.first(where: { $0.bundleIdentifier == defaultId }) {
            sorted.insert(defaultApp, at: 0)
        }
        return sorted
    }

    var body: some View {
        repositoryLabel
            .background(selectionBackground)
            .contextMenu {
                Button {
                    if let path = repository.path {
                        if let terminal = defaultTerminal {
                            AppDetector.shared.openPath(path, with: terminal)
                        } else {
                            repositoryManager.openInTerminal(path)
                        }
                    }
                } label: {
                    if let terminal = defaultTerminal {
                        AppMenuLabel(app: terminal)
                    } else {
                        Label("workspace.repository.openTerminal", systemImage: "terminal")
                    }
                }

                Button {
                    if let path = repository.path {
                        repositoryManager.openInFinder(path)
                    }
                } label: {
                    if let finder = finderApp {
                        AppMenuLabel(app: finder)
                    } else {
                        Label("workspace.repository.openFinder", systemImage: "folder")
                    }
                }

                Button {
                    if let path = repository.path {
                        if let editor = defaultEditor {
                            AppDetector.shared.openPath(path, with: editor)
                        } else {
                            repositoryManager.openInEditor(path)
                        }
                    }
                } label: {
                    if let editor = defaultEditor {
                        AppMenuLabel(app: editor)
                    } else {
                        Label("workspace.repository.openEditor", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                }

                Menu {
                    Text("Terminals")
                        .font(.caption)

                    ForEach(sortedApps(AppDetector.shared.getTerminals(), defaultBundleId: defaultTerminalBundleId)) { terminal in
                        Button {
                            if let path = repository.path {
                                AppDetector.shared.openPath(path, with: terminal)
                            }
                        } label: {
                            HStack {
                                AppMenuLabel(app: terminal)
                                if terminal.bundleIdentifier == defaultTerminalBundleId {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }

                    Divider()

                    Text("Editors")
                        .font(.caption)

                    ForEach(sortedApps(AppDetector.shared.getEditors(), defaultBundleId: defaultEditorBundleId)) { editor in
                        Button {
                            if let path = repository.path {
                                AppDetector.shared.openPath(path, with: editor)
                            }
                        } label: {
                            HStack {
                                AppMenuLabel(app: editor)
                                if editor.bundleIdentifier == defaultEditorBundleId {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Label("Open in...", systemImage: "arrow.up.forward.app")
                }

                Button {
                    if let path = repository.path {
                        Clipboard.copy(path)
                    }
                } label: {
                    Label("workspace.repository.copyPath", systemImage: "doc.on.doc")
                }

                Divider()

                Menu {
                    ForEach(ItemStatus.allCases) { status in
                        Button {
                            setStatus(status)
                        } label: {
                            HStack {
                                Circle()
                                    .fill(status.color)
                                    .frame(width: 8, height: 8)
                                Text(status.title)
                                if repositoryStatus == status {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Label("repository.setStatus", systemImage: "circle.fill")
                }

                Button {
                    showingNoteEditor = true
                } label: {
                    Label("repository.editNote", systemImage: "note.text")
                }

                Button {
                    showingPostCreateActions = true
                } label: {
                    Label("Post-Create Actions", systemImage: "gearshape.2")
                }

                Divider()

                Button(role: .destructive) {
                    showingRemoveConfirmation = true
                } label: {
                    Label("workspace.repository.remove", systemImage: "trash")
                }
            }
            .sheet(isPresented: $showingRemoveConfirmation) {
                RepositoryRemoveSheet(
                    repositoryName: repository.name ?? String(localized: "workspace.repository.unknown"),
                    alsoDeleteFromFilesystem: $alsoDeleteFromFilesystem,
                    onCancel: {
                        showingRemoveConfirmation = false
                        alsoDeleteFromFilesystem = false
                    },
                    onRemove: {
                        showingRemoveConfirmation = false
                        removeRepository()
                    }
                )
            }
            .sheet(isPresented: $showingNoteEditor) {
                NoteEditorView(
                    note: Binding(
                        get: { repository.note ?? "" },
                        set: { repository.note = $0 }
                    ),
                    title: String(localized: "repository.note.title \(repository.name ?? "")"),
                    onSave: {
                        try? repositoryManager.updateRepositoryNote(repository, note: repository.note)
                    }
                )
            }
            .sheet(isPresented: $showingPostCreateActions) {
                PostCreateActionsSheet(repository: repository)
            }
    }

    private func setStatus(_ status: ItemStatus) {
        do {
            try repositoryManager.updateRepositoryStatus(repository, status: status)
        } catch {
            logger.error("Failed to update repository status: \(error.localizedDescription)")
        }
    }

    private var repositoryStatus: ItemStatus {
        ItemStatus(rawValue: repository.status ?? "active") ?? .active
    }

    private var activeSessionCount: Int {
        let worktrees = (repository.worktrees as? Set<Worktree>) ?? []
        return worktrees.reduce(0) { total, worktree in
            guard !worktree.isDeleted else { return total }

            let chatCount = ((worktree.chatSessions as? Set<ChatSession>) ?? [])
                .filter { !$0.isDeleted }
                .count
            let terminalCount = ((worktree.terminalSessions as? Set<TerminalSession>) ?? [])
                .filter { !$0.isDeleted }
                .count
            let browserCount = ((worktree.browserSessions as? Set<BrowserSession>) ?? [])
                .filter { !$0.isDeleted }
                .count

            return total + chatCount + terminalCount + browserCount
        }
    }

    private var sessionIndicatorColor: Color {
        isSelected ? selectedForegroundColor.opacity(0.9) : .secondary
    }

    private var selectedForegroundColor: Color {
        controlActiveState == .key ? .accentColor : .accentColor.opacity(0.78)
    }

    private var selectionFillColor: Color {
        let base = NSColor.unemphasizedSelectedContentBackgroundColor
        let alpha: Double = controlActiveState == .key ? 0.26 : 0.18
        return Color(nsColor: base).opacity(alpha)
    }

    private var repositoryLabel: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "folder.badge.gearshape")
                .symbolRenderingMode(isSelected ? .monochrome : .palette)
                .foregroundStyle(isSelected ? selectedForegroundColor : repositoryStatus.color, .secondary)
                .imageScale(.medium)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(repository.name ?? String(localized: "workspace.repository.unknown"))
                    .font(.body)
                    .foregroundStyle(isSelected ? selectedForegroundColor : Color.primary)
                    .lineLimit(1)

                if let note = repository.note, !note.isEmpty {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(
                            isSelected
                                ? selectedForegroundColor.opacity(0.75)
                                : Color.secondary.opacity(0.7)
                        )
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: 8)

            if activeSessionCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 11, weight: .medium))
                    Text("\(activeSessionCount)")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(sessionIndicatorColor)
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
    }

    private var selectionBackground: some View {
        Group {
            if isSelected {
                RoundedRectangle(cornerRadius: 6)
                    .fill(selectionFillColor)
            }
        }
    }

    private func removeRepository() {
        Task {
            do {
                if alsoDeleteFromFilesystem, let path = repository.path {
                    let fileURL = URL(fileURLWithPath: path)
                    try FileManager.default.removeItem(at: fileURL)
                }

                onRemove()
                try repositoryManager.deleteRepository(repository)
                alsoDeleteFromFilesystem = false
            } catch {
                logger.error("Failed to remove repository: \(error.localizedDescription)")
                alsoDeleteFromFilesystem = false
            }
        }
    }
}
