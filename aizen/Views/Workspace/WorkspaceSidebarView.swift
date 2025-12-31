//
//  WorkspaceSidebarView.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import SwiftUI
import CoreData
import UniformTypeIdentifiers
import os.log

struct WorkspaceSidebarView: View {
    private let logger = Logger.workspace
    let workspaces: [Workspace]
    @Binding var selectedWorkspace: Workspace?
    @Binding var selectedRepository: Repository?
    @Binding var selectedWorktree: Worktree?
    @Binding var searchText: String
    @Binding var showingAddRepository: Bool

    @ObservedObject var repositoryManager: RepositoryManager
    @StateObject private var licenseManager = LicenseManager.shared
    @State private var showingWorkspaceSheet = false
    @State private var showingWorkspaceSwitcher = false
    @State private var showingSupportSheet = false
    @State private var workspaceToEdit: Workspace?
    @State private var refreshTask: Task<Void, Never>?
    @State private var missingRepository: RepositoryManager.MissingRepository?
    @AppStorage("repositoryStatusFilters") private var storedStatusFilters: String = ""

    private var selectedStatusFilters: Set<ItemStatus> {
        ItemStatus.decode(storedStatusFilters)
    }

    private var selectedStatusFiltersBinding: Binding<Set<ItemStatus>> {
        Binding(
            get: { ItemStatus.decode(storedStatusFilters) },
            set: { storedStatusFilters = ItemStatus.encode($0) }
        )
    }

    private var isLicenseActive: Bool {
        switch licenseManager.status {
        case .active, .offlineGrace:
            return true
        default:
            return false
        }
    }

    private let refreshInterval: TimeInterval = 30.0

    private func colorFromHex(_ hex: String) -> Color {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)

        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0

        return Color(red: r, green: g, blue: b)
    }

    var filteredRepositories: [Repository] {
        guard let workspace = selectedWorkspace else { return [] }
        let repos = (workspace.repositories as? Set<Repository>) ?? []

        // Filter out deleted Core Data objects
        var validRepos = repos.filter { !$0.isDeleted }

        // Apply status filter
        if !selectedStatusFilters.isEmpty && selectedStatusFilters.count < ItemStatus.allCases.count {
            validRepos = validRepos.filter { repo in
                let status = ItemStatus(rawValue: repo.status ?? "active") ?? .active
                return selectedStatusFilters.contains(status)
            }
        }

        if searchText.isEmpty {
            return validRepos.sorted { ($0.name ?? "") < ($1.name ?? "") }
        } else {
            return validRepos
                .filter { ($0.name ?? "").localizedCaseInsensitiveContains(searchText) }
                .sorted { ($0.name ?? "") < ($1.name ?? "") }
        }
    }

    private func startPeriodicRefresh() {
        // Cancel any existing refresh task
        refreshTask?.cancel()

        // Use Task-based periodic refresh instead of Timer (runs off main thread)
        refreshTask = Task {
            while !Task.isCancelled {
                // Wait for refresh interval
                try? await Task.sleep(for: .seconds(refreshInterval))

                guard !Task.isCancelled else { break }

                // Perform refresh
                await refreshAllRepositories()
            }
        }
    }

    private func stopPeriodicRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    private func refreshAllRepositories() async {
        // Prioritize selected repository for immediate refresh
        if let selected = selectedRepository {
            do {
                try await repositoryManager.refreshRepository(selected)
            } catch let error as Libgit2Error {
                if case .repositoryPathMissing(let path) = error {
                    await handleMissingRepository(selected, path: path)
                } else {
                    logger.error("Failed to refresh selected repository \(selected.name ?? "unknown"): \(error.localizedDescription)")
                }
            } catch {
                logger.error("Failed to refresh selected repository \(selected.name ?? "unknown"): \(error.localizedDescription)")
            }
        }

        // Background refresh other repos with stagger to reduce I/O contention
        for repository in filteredRepositories where repository.id != selectedRepository?.id {
            guard !Task.isCancelled else { break }
            do {
                try await repositoryManager.refreshRepository(repository)
                try await Task.sleep(for: .milliseconds(100))
            } catch let error as Libgit2Error {
                if case .repositoryPathMissing(let path) = error {
                    await handleMissingRepository(repository, path: path)
                } else {
                    logger.error("Failed to refresh repository \(repository.name ?? "unknown"): \(error.localizedDescription)")
                }
            } catch {
                logger.error("Failed to refresh repository \(repository.name ?? "unknown"): \(error.localizedDescription)")
            }
        }
    }

    @MainActor
    private func handleMissingRepository(_ repository: Repository, path: String) {
        guard let id = repository.id else { return }
        // Only show if not already showing one
        guard missingRepository == nil else { return }
        missingRepository = RepositoryManager.MissingRepository(
            id: id,
            repository: repository,
            lastKnownPath: path
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // Workspace section
            VStack(alignment: .leading, spacing: 8) {
                Text("workspace.sidebar.title")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .padding(.horizontal, 12)

                // Current workspace button
                Button {
                    showingWorkspaceSwitcher = true
                } label: {
                    HStack(spacing: 12) {
                        if let workspace = selectedWorkspace {
                            Circle()
                                .fill(colorFromHex(workspace.colorHex ?? "#0000FF"))
                                .frame(width: 8, height: 8)

                            Text(workspace.name ?? String(localized: "workspace.untitled"))
                                .font(.body)
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.primary)
                                .lineLimit(1)

                            Spacer(minLength: 8)

                            let repoCount = (workspace.repositories as? Set<Repository>)?.count ?? 0
                            PillBadge(
                                text: "\(repoCount)",
                                color: .secondary,
                                textColor: .secondary,
                                font: .caption,
                                horizontalPadding: 6,
                                verticalPadding: 2,
                                backgroundOpacity: 0.2
                            )

                            Image(systemName: "chevron.up.chevron.down")
                                .foregroundStyle(.secondary)
                                .imageScale(.small)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
            }
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            // Search field
            SearchField(
                placeholder: "workspace.search.placeholder",
                text: $searchText,
                iconColor: .secondary,
                trailing: {
                    StatusFilterDropdown(selectedStatuses: selectedStatusFiltersBinding)
                }
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Repository list
            if filteredRepositories.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    if selectedStatusFilters.count < ItemStatus.allCases.count && !selectedStatusFilters.isEmpty {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.system(size: 32))
                            .foregroundStyle(.tertiary)
                        Text("sidebar.empty.filtered")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button {
                            storedStatusFilters = ""
                        } label: {
                            Text("filter.clearAll")
                        }
                        .buttonStyle(.bordered)
                    } else if !searchText.isEmpty {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 32))
                            .foregroundStyle(.tertiary)
                        Text("sidebar.empty.search")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 32))
                            .foregroundStyle(.tertiary)
                        Text("sidebar.empty.noRepos")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button {
                            showingAddRepository = true
                        } label: {
                            Text("workspace.addRepository")
                        }
                        .buttonStyle(.bordered)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List {
                    ForEach(filteredRepositories, id: \.id) { repository in
                        RepositoryRow(
                            repository: repository,
                            isSelected: selectedRepository?.id == repository.id,
                            repositoryManager: repositoryManager,
                            onSelect: {
                                selectedRepository = repository
                                // Auto-select primary worktree if no worktree is selected
                                if selectedWorktree == nil {
                                    let worktrees = (repository.worktrees as? Set<Worktree>) ?? []
                                    selectedWorktree = worktrees.first(where: { $0.isPrimary })
                                }
                            },
                            onRemove: {
                                if selectedRepository?.id == repository.id {
                                    selectedRepository = nil
                                    selectedWorktree = nil
                                }
                            }
                        )
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .padding(.top, 12)
            }

            Divider()

            // Support Aizen (only when not licensed)
            if !isLicenseActive {
                Button {
                    SettingsWindowManager.shared.show()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        NotificationCenter.default.post(name: .openSettingsPro, object: nil)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                        Text("sidebar.supportAizen")
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .background(Color.primary.opacity(0.08))
            }

            // Footer buttons
            HStack(spacing: 0) {
                Button {
                    showingAddRepository = true
                } label: {
                    Label("workspace.addRepository", systemImage: "plus")
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Spacer()

                Button {
                    showingSupportSheet = true
                } label: {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.vertical, 8)
                .help("sidebar.support")

                Button {
                    SettingsWindowManager.shared.show()
                } label: {
                    Image(systemName: "gear")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .help("settings.title")
            }
            .background(Color.primary.opacity(0.04))
        }
        .navigationTitle(LocalizedStringKey("workspace.repositories.title"))
        .sheet(isPresented: $showingWorkspaceSheet) {
            WorkspaceCreateSheet(repositoryManager: repositoryManager)
        }
        .sheet(isPresented: $showingWorkspaceSwitcher) {
            WorkspaceSwitcherSheet(
                repositoryManager: repositoryManager,
                workspaces: workspaces,
                selectedWorkspace: $selectedWorkspace
            )
        }
        .sheet(item: $workspaceToEdit) { workspace in
            WorkspaceEditSheet(workspace: workspace, repositoryManager: repositoryManager)
        }
        .sheet(isPresented: $showingSupportSheet) {
            SupportSheet()
        }
        .sheet(item: $missingRepository) { missing in
            MissingRepositorySheet(
                missing: missing,
                repositoryManager: repositoryManager,
                selectedRepository: $selectedRepository,
                selectedWorktree: $selectedWorktree,
                onDismiss: { missingRepository = nil }
            )
        }
        .onAppear {
            startPeriodicRefresh()
        }
        .onDisappear {
            stopPeriodicRefresh()
        }
    }
}

// MARK: - Missing Repository Sheet

struct MissingRepositorySheet: View {
    let missing: RepositoryManager.MissingRepository
    @ObservedObject var repositoryManager: RepositoryManager
    @Binding var selectedRepository: Repository?
    @Binding var selectedWorktree: Worktree?
    let onDismiss: () -> Void

    @State private var showingFilePicker = false
    @State private var isRelocating = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Repository Not Found")
                .font(.headline)

            VStack(spacing: 8) {
                Text("The repository \"\(missing.repository.name ?? "Unknown")\" could not be found at:")
                    .multilineTextAlignment(.center)

                Text(missing.lastKnownPath)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(8)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))

                Text("It may have been moved or deleted.")
                    .foregroundStyle(.secondary)
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack(spacing: 12) {
                Button(role: .destructive) {
                    removeRepository()
                } label: {
                    Text("Remove from Aizen")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    showingFilePicker = true
                } label: {
                    if isRelocating {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Locate Repository...")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRelocating)
            }
        }
        .padding(24)
        .frame(width: 420)
        .interactiveDismissDisabled()
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            handleRelocateResult(result)
        }
    }

    private func removeRepository() {
        do {
            if selectedRepository?.id == missing.repository.id {
                selectedRepository = nil
                selectedWorktree = nil
            }
            try repositoryManager.deleteRepository(missing.repository)
            onDismiss()
        } catch {
            errorMessage = "Failed to remove: \(error.localizedDescription)"
        }
    }

    private func handleRelocateResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }

            isRelocating = true
            errorMessage = nil

            Task {
                do {
                    try await repositoryManager.relocateRepository(missing.repository, to: url.path)
                    onDismiss()
                } catch {
                    isRelocating = false
                    errorMessage = "Invalid repository: \(error.localizedDescription)"
                }
            }

        case .failure:
            // User cancelled file picker - stay on sheet
            break
        }
    }
}

struct RepositoryRow: View {
    private let logger = Logger.workspace
    @ObservedObject var repository: Repository
    let isSelected: Bool
    @ObservedObject var repositoryManager: RepositoryManager
    let onSelect: () -> Void
    let onRemove: () -> Void

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
                // Open in Terminal (with real name and icon)
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

                // Open in Finder (with real icon)
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

                // Open in Editor (with real name and icon)
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

                // Open in... submenu
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

                // Status submenu
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

    private var repositoryLabel: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "folder.badge.gearshape")
                .symbolRenderingMode(.palette)
                .foregroundStyle(
                    repositoryStatus.color,
                    isSelected ? Color.accentColor : .secondary
                )
                .imageScale(.medium)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(repository.name ?? String(localized: "workspace.repository.unknown"))
                    .font(.body)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                    .lineLimit(1)

                if let path = repository.path {
                    Text(path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                if let note = repository.note, !note.isEmpty {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: 8)
        }
        .padding(.leading, 8)
        .padding(.trailing, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
    }

    @ViewBuilder
    private var selectionBackground: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor.opacity(0.15))
        }
    }

    private func removeRepository() {
        Task {
            do {
                // Delete from filesystem if checkbox was checked
                if alsoDeleteFromFilesystem, let path = repository.path {
                    let fileURL = URL(fileURLWithPath: path)
                    try FileManager.default.removeItem(at: fileURL)
                }

                // Clear selection before deleting
                onRemove()

                // Unlink from Core Data
                try repositoryManager.deleteRepository(repository)

                // Reset state
                alsoDeleteFromFilesystem = false
            } catch {
                logger.error("Failed to remove repository: \(error.localizedDescription)")
                alsoDeleteFromFilesystem = false
            }
        }
    }
}

struct WorkspaceRow: View {
    let workspace: Workspace
    let isSelected: Bool
    let isHovered: Bool
    let colorFromHex: (String) -> Color
    let onSelect: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(colorFromHex(workspace.colorHex ?? "#0000FF"))
                .frame(width: 8, height: 8)

            Text(workspace.name ?? String(localized: "workspace.untitled"))
                .font(.body)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                .lineLimit(1)

            Spacer(minLength: 8)

            let repoCount = (workspace.repositories as? Set<Repository>)?.count ?? 0
            PillBadge(
                text: "\(repoCount)",
                color: .secondary,
                textColor: .secondary,
                font: .caption,
                horizontalPadding: 6,
                verticalPadding: 2,
                backgroundOpacity: 0.2
            )

            if isHovered || isSelected {
                Button {
                    onEdit()
                } label: {
                    Image(systemName: "pencil.circle.fill")
                        .foregroundStyle(.secondary)
                        .imageScale(.medium)
                }
                .buttonStyle(.plain)
                .help("workspace.edit")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
    }
}

struct RepositoryRemoveSheet: View {
    let repositoryName: String
    @Binding var alsoDeleteFromFilesystem: Bool
    let onCancel: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.minus")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text("workspace.repository.removeTitle")
                .font(.headline)

            Text("workspace.repository.removeMessage")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Toggle(isOn: $alsoDeleteFromFilesystem) {
                Label("workspace.repository.alsoDelete", systemImage: "trash")
                    .foregroundStyle(alsoDeleteFromFilesystem ? .red : .primary)
            }
            .toggleStyle(.checkbox)
            .padding(.top, 8)

            HStack(spacing: 12) {
                Button(String(localized: "worktree.create.cancel")) {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button(String(localized: "workspace.repository.removeButton"), role: .destructive) {
                    onRemove()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 8)
        }
        .padding(24)
        .frame(width: 340)
    }
}

struct SupportSheet: View {
    @Environment(\.dismiss) private var dismiss

    private struct ContactOption: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String
        let icon: String
        let iconImage: String?
        let iconText: String?
        let color: Color
        let url: String
    }

    private let contactOptions: [ContactOption] = [
        ContactOption(title: "Aizen", subtitle: "@aizenwin", icon: "", iconImage: nil, iconText: "𝕏", color: .primary, url: "https://x.com/aizenwin"),
        ContactOption(title: "Developer", subtitle: "@wiedymi", icon: "", iconImage: nil, iconText: "𝕏", color: .primary, url: "https://x.com/wiedymi"),
        ContactOption(title: "Discord", subtitle: "Join Community", icon: "", iconImage: "DiscordLogo", iconText: nil, color: Color(red: 0.345, green: 0.396, blue: 0.949), url: "https://discord.gg/eKW7GNesuS"),
        ContactOption(title: "Email", subtitle: "dev@aizen.win", icon: "envelope.fill", iconImage: nil, iconText: nil, color: .orange, url: "mailto:dev@aizen.win"),
        ContactOption(title: "GitHub", subtitle: "Report Issue", icon: "exclamationmark.triangle.fill", iconImage: nil, iconText: nil, color: .red, url: "https://github.com/vivy-company/aizen/issues")
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 8) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.blue)

                    Text("sidebar.support.title")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("sidebar.support.subtitle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 24)
                .padding(.bottom, 20)

                DetailCloseButton { dismiss() }
                    .padding(12)
            }

            Divider()

            // Options
            VStack(spacing: 0) {
                ForEach(contactOptions) { option in
                    Button {
                        if let url = URL(string: option.url) {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 14) {
                            Group {
                                if let imageName = option.iconImage {
                                    Image(imageName)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                } else if let text = option.iconText {
                                    Text(text)
                                        .font(.system(size: 18, weight: .bold))
                                } else {
                                    Image(systemName: option.icon)
                                }
                            }
                            .frame(width: 24, height: 24)
                            .foregroundStyle(option.color)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.title)
                                    .font(.body)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.primary)

                                Text(option.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if option.id != contactOptions.last?.id {
                        Divider()
                            .padding(.leading, 58)
                    }
                }
            }

            // Company footer
            Button {
                if let url = URL(string: "https://x.com/vivytech") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                HStack(spacing: 6) {
                    Text("Vivy Technologies Co., Limited")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9))
                        .foregroundStyle(.quaternary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
        }
        .frame(width: 340)
    }
}

#Preview {
    WorkspaceSidebarView(
        workspaces: [],
        selectedWorkspace: .constant(nil),
        selectedRepository: .constant(nil),
        selectedWorktree: .constant(nil),
        searchText: .constant(""),
        showingAddRepository: .constant(false),
        repositoryManager: RepositoryManager(viewContext: PersistenceController.preview.container.viewContext)
    )
}
