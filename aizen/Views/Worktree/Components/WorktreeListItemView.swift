//
//  WorktreeListItemView.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import SwiftUI
import os.log

struct WorktreeListItemView: View {
    @ObservedObject var worktree: Worktree
    let isSelected: Bool
    @ObservedObject var repositoryManager: RepositoryManager
    let allWorktrees: [Worktree]
    @Binding var selectedWorktree: Worktree?
    @ObservedObject var tabStateManager: WorktreeTabStateManager

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen.app", category: "WorktreeListItemView")

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

    @State private var showingDetails = false
    @State private var showingDeleteConfirmation = false
    @State private var hasUnsavedChanges = false
    @State private var errorMessage: String?
    @State private var worktreeStatuses: [WorktreeStatusInfo] = []
    @State private var isLoadingStatuses = false
    @State private var mergeErrorMessage: String?
    @State private var mergeConflictFiles: [String] = []
    @State private var showingMergeConflict = false
    @State private var showingMergeSuccess = false
    @State private var mergeSuccessMessage = ""
    @State private var availableBranches: [BranchInfo] = []
    @State private var isLoadingBranches = false
    @State private var showingBranchSelector = false
    @State private var branchSwitchError: String?
    @State private var selectedBranchForSwitch: BranchInfo?
    @State private var showingNoteEditor = false

    private var worktreeStatus: ItemStatus {
        ItemStatus(rawValue: worktree.status ?? "active") ?? .active
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: worktree.isPrimary ? "arrow.triangle.branch" : "arrow.triangle.2.circlepath")
                .foregroundStyle(isSelected ? Color.accentColor : worktreeStatus.color)
                .imageScale(.medium)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(worktree.branch ?? String(localized: "worktree.list.unknown"))
                        .font(.headline)
                        .foregroundStyle(isSelected ? Color.accentColor : Color.primary)

                    if worktree.isPrimary {
                        PillBadge(
                            text: String(localized: "worktree.detail.main"),
                            color: .blue,
                            textColor: .white,
                            font: .caption2,
                            fontWeight: .semibold,
                            horizontalPadding: 6,
                            verticalPadding: 2,
                            backgroundOpacity: 1.0
                        )
                    }
                }

                Text(worktree.path ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let note = worktree.note, !note.isEmpty {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                if let lastAccessed = worktree.lastAccessed {
                    Text(String(localized: "worktree.list.lastAccessed \(lastAccessed.formatted(.relative(presentation: .named)))"))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                ActiveTabIndicatorView(
                    worktree: worktree,
                    tabStateManager: tabStateManager
                )
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            isSelected
                ? RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor.opacity(0.15))
                : nil
        )
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                showingDetails = true
            } label: {
                Label(String(localized: "worktree.detail.showDetails"), systemImage: "info.circle")
            }

            Divider()

            // Open in Terminal (with real name and icon)
            Button {
                if let path = worktree.path {
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
                    Label(String(localized: "worktree.detail.openTerminal"), systemImage: "terminal")
                }
            }

            // Open in Finder (with real icon)
            Button {
                if let path = worktree.path {
                    repositoryManager.openInFinder(path)
                }
            } label: {
                if let finder = finderApp {
                    AppMenuLabel(app: finder)
                } else {
                    Label(String(localized: "worktree.detail.openFinder"), systemImage: "folder")
                }
            }

            // Open in Editor (with real name and icon)
            Button {
                if let path = worktree.path {
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
                    Label(String(localized: "worktree.detail.openEditor"), systemImage: "chevron.left.forwardslash.chevron.right")
                }
            }

            // Open in... submenu
            Menu {
                Text(String(localized: "worktree.openIn.terminals"))
                    .font(.caption)

                ForEach(sortedApps(AppDetector.shared.getTerminals(), defaultBundleId: defaultTerminalBundleId)) { terminal in
                    Button {
                        if let path = worktree.path {
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

                Text(String(localized: "worktree.openIn.editors"))
                    .font(.caption)

                ForEach(sortedApps(AppDetector.shared.getEditors(), defaultBundleId: defaultEditorBundleId)) { editor in
                    Button {
                        if let path = worktree.path {
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
                Label(String(localized: "worktree.openIn.title"), systemImage: "arrow.up.forward.app")
            }

            Button {
                if let branch = worktree.branch {
                    Clipboard.copy(branch)
                }
            } label: {
                Label(String(localized: "worktree.detail.copyBranchName"), systemImage: "doc.on.doc")
            }

            Button {
                if let path = worktree.path {
                    Clipboard.copy(path)
                }
            } label: {
                Label(String(localized: "worktree.detail.copyPath"), systemImage: "doc.on.clipboard")
            }

            Divider()

            Menu {
                ForEach(worktreeStatuses.filter { $0.worktree.id != worktree.id }, id: \.worktree.id) { statusInfo in
                    Button {
                        performMerge(from: statusInfo.worktree, to: worktree)
                    } label: {
                        HStack {
                            Text(statusInfo.branch)
                            if statusInfo.hasUncommittedChanges {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
            } label: {
                Label(String(localized: "worktree.merge.pullFrom"), systemImage: "arrow.down.circle")
            }

            Divider()

            Menu {
                if availableBranches.isEmpty && !isLoadingBranches {
                    Text(String(localized: "general.loading"))
                        .foregroundStyle(.secondary)
                        .onAppear { loadAvailableBranches() }
                } else if isLoadingBranches {
                    Text(String(localized: "general.loading"))
                        .foregroundStyle(.secondary)
                } else {
                    // Show top local branches (excluding current)
                    ForEach(availableBranches.filter { !$0.isRemote && $0.name != worktree.branch }) { branch in
                        Button {
                            switchToBranch(branch)
                        } label: {
                            HStack {
                                Image(systemName: "arrow.triangle.branch")
                                    .font(.caption)
                                Text(branch.name)
                            }
                        }
                    }

                    // Show remote branches that can be tracked
                    if !availableBranches.filter({ $0.isRemote }).isEmpty {
                        Divider()

                        ForEach(availableBranches.filter { $0.isRemote }) { branch in
                            Button {
                                switchToBranch(branch)
                            } label: {
                                HStack {
                                    Image(systemName: "arrow.triangle.branch")
                                        .font(.caption)
                                    Text(branch.name)
                                    Text(String(localized: "worktree.branch.remote"))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    Divider()

                    Button {
                        showingBranchSelector = true
                    } label: {
                        Label(String(localized: "worktree.branch.browseOrCreate"), systemImage: "ellipsis.circle")
                    }
                }
            } label: {
                Label(String(localized: "worktree.branch.switch"), systemImage: "arrow.triangle.swap")
            }

            Divider()

            // Status submenu
            Menu {
                ForEach(ItemStatus.allCases) { status in
                    Button {
                        setWorktreeStatus(status)
                    } label: {
                        HStack {
                            Circle()
                                .fill(status.color)
                                .frame(width: 8, height: 8)
                            Text(status.title)
                            if worktreeStatus == status {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Label("worktree.setStatus", systemImage: "circle.fill")
            }

            Button {
                showingNoteEditor = true
            } label: {
                Label("worktree.editNote", systemImage: "note.text")
            }

            if !worktree.isPrimary {
                Divider()

                Button(role: .destructive) {
                    checkUnsavedChanges()
                } label: {
                    Label(String(localized: "worktree.detail.delete"), systemImage: "trash")
                }
            }
        }
        .sheet(isPresented: $showingDetails) {
            WorktreeDetailsSheet(worktree: worktree, repositoryManager: repositoryManager)
        }
        .sheet(isPresented: $showingBranchSelector) {
            if let repo = worktree.repository {
                BranchSelectorView(
                    repository: repo,
                    repositoryManager: repositoryManager,
                    selectedBranch: $selectedBranchForSwitch,
                    allowCreation: true,
                    onCreateBranch: { branchName in
                        createNewBranch(name: branchName)
                    }
                )
            }
        }
        .sheet(isPresented: $showingNoteEditor) {
            NoteEditorView(
                note: Binding(
                    get: { worktree.note ?? "" },
                    set: { worktree.note = $0 }
                ),
                title: String(localized: "worktree.note.title \(worktree.branch ?? "")"),
                onSave: {
                    try? repositoryManager.updateWorktreeNote(worktree, note: worktree.note)
                }
            )
        }
        .onChange(of: selectedBranchForSwitch) { newBranch in
            if let branch = newBranch {
                switchToBranch(branch)
                selectedBranchForSwitch = nil
            }
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
                Text(String(localized: "worktree.detail.deleteConfirmMessageWithName \(worktree.branch ?? String(localized: "worktree.list.unknown"))"))
            }
        }
        .alert(String(localized: "worktree.list.error"), isPresented: .constant(errorMessage != nil)) {
            Button(String(localized: "worktree.list.ok")) {
                errorMessage = nil
            }
        } message: {
            if let error = errorMessage {
                Text(error)
            }
        }
        .alert(String(localized: "worktree.merge.conflict"), isPresented: $showingMergeConflict) {
            Button(String(localized: "worktree.list.ok")) {
                mergeConflictFiles = []
            }
        } message: {
            VStack(alignment: .leading) {
                Text(String(localized: "worktree.merge.conflictMessage"))
                ForEach(mergeConflictFiles, id: \.self) { file in
                    Text("• \(file)")
                }
                Text(String(localized: "worktree.merge.resolveHint"))
            }
        }
        .alert(String(localized: "worktree.merge.successful"), isPresented: $showingMergeSuccess) {
            Button(String(localized: "worktree.list.ok")) {}
        } message: {
            Text(mergeSuccessMessage)
        }
        .alert(String(localized: "worktree.merge.error"), isPresented: .constant(mergeErrorMessage != nil)) {
            Button(String(localized: "worktree.list.ok")) {
                mergeErrorMessage = nil
            }
        } message: {
            if let error = mergeErrorMessage {
                Text(error)
            }
        }
        .alert(String(localized: "worktree.branch.switchError"), isPresented: .constant(branchSwitchError != nil)) {
            Button(String(localized: "worktree.list.ok")) {
                branchSwitchError = nil
            }
        } message: {
            if let error = branchSwitchError {
                Text(error)
            }
        }
        .onAppear {
            loadWorktreeStatuses()
        }
    }

    // MARK: - Private Methods

    private func setWorktreeStatus(_ status: ItemStatus) {
        do {
            try repositoryManager.updateWorktreeStatus(worktree, status: status)
        } catch {
            logger.error("Failed to update worktree status: \(error.localizedDescription)")
        }
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
                // Find closest worktree to select after deletion
                if let currentIndex = allWorktrees.firstIndex(where: { $0.id == worktree.id }) {
                    let nextWorktree: Worktree?

                    // Try next worktree, then previous, then nil
                    if currentIndex + 1 < allWorktrees.count {
                        nextWorktree = allWorktrees[currentIndex + 1]
                    } else if currentIndex > 0 {
                        nextWorktree = allWorktrees[currentIndex - 1]
                    } else {
                        nextWorktree = nil
                    }

                    try await repositoryManager.deleteWorktree(worktree, force: hasUnsavedChanges)

                    await MainActor.run {
                        selectedWorktree = nextWorktree
                    }
                } else {
                    try await repositoryManager.deleteWorktree(worktree, force: hasUnsavedChanges)
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func loadWorktreeStatuses() {
        guard !isLoadingStatuses else { return }

        Task {
            await MainActor.run {
                isLoadingStatuses = true
            }

            var statuses: [WorktreeStatusInfo] = []

            for wt in allWorktrees {
                do {
                    let hasChanges = try await repositoryManager.hasUnsavedChanges(wt)
                    let branch = wt.branch ?? "unknown"
                    statuses.append(WorktreeStatusInfo(
                        worktree: wt,
                        hasUncommittedChanges: hasChanges,
                        branch: branch
                    ))
                } catch {
                    // Skip worktrees with errors
                    continue
                }
            }

            await MainActor.run {
                worktreeStatuses = statuses
                isLoadingStatuses = false
            }
        }
    }

    private func performMerge(from source: Worktree, to target: Worktree) {
        Task {
            do {
                let result = try await repositoryManager.mergeFromWorktree(target: target, source: source)

                await MainActor.run {
                    switch result {
                    case .success:
                        mergeSuccessMessage = "Successfully merged \(source.branch ?? "unknown") into \(target.branch ?? "unknown")"
                        showingMergeSuccess = true

                    case .conflict(let files):
                        mergeConflictFiles = files
                        showingMergeConflict = true

                    case .alreadyUpToDate:
                        mergeSuccessMessage = "Already up to date with \(source.branch ?? "unknown")"
                        showingMergeSuccess = true
                    }

                    // Reload statuses after merge
                    loadWorktreeStatuses()
                }
            } catch {
                await MainActor.run {
                    mergeErrorMessage = error.localizedDescription
                }
            }
        }
    }

    private func loadAvailableBranches() {
        guard !isLoadingBranches else { return }

        Task {
            await MainActor.run {
                isLoadingBranches = true
            }

            do {
                guard let repo = worktree.repository else {
                    logger.warning("Cannot load branches: worktree has no repository")
                    await MainActor.run { isLoadingBranches = false }
                    return
                }
                let branches = try await repositoryManager.getBranches(for: repo)

                await MainActor.run {
                    // Show top 5 local branches + top 3 remote branches
                    let localBranches = branches
                        .filter { !$0.isRemote && $0.name != worktree.branch }
                        .prefix(5)

                    let remoteBranches = branches
                        .filter { $0.isRemote }
                        .prefix(3)

                    availableBranches = Array(localBranches) + Array(remoteBranches)
                    isLoadingBranches = false
                }
            } catch {
                logger.error("Failed to load available branches: \(error.localizedDescription)")
                await MainActor.run { isLoadingBranches = false }
            }
        }
    }

    private func switchToBranch(_ branch: BranchInfo) {
        Task {
            do {
                // Handle remote branches by creating local tracking branch
                if branch.isRemote {
                    // Extract local branch name (e.g., "origin/feature" -> "feature")
                    let localName = branch.name.split(separator: "/").dropFirst().joined(separator: "/")

                    // Create and checkout new local branch tracking the remote
                    try await repositoryManager.createAndSwitchBranch(
                        worktree,
                        name: localName,
                        from: branch.name
                    )
                } else {
                    // Switch to existing local branch
                    try await repositoryManager.switchBranch(worktree, to: branch.name)
                }

                await MainActor.run {
                    loadAvailableBranches()
                }
            } catch {
                await MainActor.run {
                    branchSwitchError = error.localizedDescription
                }
            }
        }
    }

    private func createNewBranch(name: String) {
        Task {
            do {
                // Create new branch from current branch
                guard let currentBranch = worktree.branch else {
                    throw Libgit2Error.branchNotFound("No current branch")
                }

                try await repositoryManager.createAndSwitchBranch(
                    worktree,
                    name: name,
                    from: currentBranch
                )

                await MainActor.run {
                    loadAvailableBranches()
                }
            } catch {
                await MainActor.run {
                    branchSwitchError = error.localizedDescription
                }
            }
        }
    }
}
