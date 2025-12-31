//
//  WorktreeDetailsTab.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 04.11.25.
//

import SwiftUI
import os.log

struct DetailsTabView: View {
    @ObservedObject var worktree: Worktree
    @ObservedObject var repositoryManager: RepositoryManager
    var onWorktreeDeleted: ((Worktree?) -> Void)?

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen", category: "DetailsTabView")
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
                        PillBadge(
                            text: String(localized: "worktree.detail.primary"),
                            color: .blue,
                            textColor: .white,
                            font: .caption,
                            fontWeight: .semibold,
                            horizontalPadding: 12,
                            verticalPadding: 4,
                            backgroundOpacity: 1.0
                        )
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
                // Get all worktrees from the repository
                guard let repository = worktree.repository else { return }
                let allWorktrees = ((repository.worktrees as? Set<Worktree>) ?? []).sorted { wt1, wt2 in
                    if wt1.isPrimary != wt2.isPrimary {
                        return wt1.isPrimary
                    }
                    return (wt1.branch ?? "") < (wt2.branch ?? "")
                }

                // Find next worktree to select
                let nextWorktree: Worktree?
                if let currentIndex = allWorktrees.firstIndex(where: { $0.id == worktree.id }) {
                    // Try next worktree, then previous, then nil
                    if currentIndex + 1 < allWorktrees.count {
                        nextWorktree = allWorktrees[currentIndex + 1]
                    } else if currentIndex > 0 {
                        nextWorktree = allWorktrees[currentIndex - 1]
                    } else {
                        nextWorktree = nil
                    }
                } else {
                    nextWorktree = nil
                }

                try await repositoryManager.deleteWorktree(worktree, force: hasUnsavedChanges)

                await MainActor.run {
                    onWorktreeDeleted?(nextWorktree)
                }
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
            logger.error("Failed to update last accessed: \(error.localizedDescription)")
        }
    }
}
