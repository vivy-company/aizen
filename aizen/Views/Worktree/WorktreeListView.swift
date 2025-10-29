//
//  WorktreeListView.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import SwiftUI

struct WorktreeListView: View {
    @ObservedObject var repository: Repository
    @Binding var selectedWorktree: Worktree?
    @ObservedObject var repositoryManager: RepositoryManager

    @State private var showingCreateWorktree = false
    @State private var searchText = ""

    var worktrees: [Worktree] {
        let wts = (repository.worktrees as? Set<Worktree>) ?? []
        let sorted = wts.sorted { wt1, wt2 in
            if wt1.isPrimary != wt2.isPrimary {
                return wt1.isPrimary
            }
            return (wt1.branch ?? "") < (wt2.branch ?? "")
        }

        if searchText.isEmpty {
            return sorted
        } else {
            return sorted.filter { worktree in
                (worktree.branch ?? "").localizedCaseInsensitiveContains(searchText) ||
                (worktree.path ?? "").localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(String(localized: "worktree.list.search"), text: $searchText)
                    .textFieldStyle(.plain)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            List {
                ForEach(worktrees, id: \.id) { worktree in
                    WorktreeListRowView(
                        worktree: worktree,
                        isSelected: selectedWorktree?.id == worktree.id,
                        repositoryManager: repositoryManager
                    )
                    .onTapGesture {
                        selectedWorktree = worktree
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(repository.name ?? "Unknown")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Spacer()
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    showingCreateWorktree = true
                } label: {
                    Label(String(localized: "worktree.list.add"), systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingCreateWorktree) {
            WorktreeCreateSheet(
                repository: repository,
                repositoryManager: repositoryManager
            )
        }
    }
}

struct WorktreeListRowView: View {
    @ObservedObject var worktree: Worktree
    let isSelected: Bool
    @ObservedObject var repositoryManager: RepositoryManager

    @State private var showingDetails = false
    @State private var showingDeleteConfirmation = false
    @State private var hasUnsavedChanges = false
    @State private var errorMessage: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: worktree.isPrimary ? "arrow.triangle.branch" : "arrow.triangle.2.circlepath")
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .imageScale(.medium)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(worktree.branch ?? String(localized: "worktree.list.unknown"))
                        .font(.headline)
                        .foregroundStyle(isSelected ? Color.accentColor : Color.primary)

                    if worktree.isPrimary {
                        Text("worktree.detail.main", bundle: .main)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.blue, in: Capsule())
                    }
                }

                Text(worktree.path ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let lastAccessed = worktree.lastAccessed {
                    Text(String(localized: "worktree.list.lastAccessed \(lastAccessed.formatted(.relative(presentation: .named)))"))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
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

            Button {
                if let path = worktree.path {
                    repositoryManager.openInTerminal(path)
                }
            } label: {
                Label(String(localized: "worktree.detail.openTerminal"), systemImage: "terminal")
            }

            Button {
                if let path = worktree.path {
                    repositoryManager.openInFinder(path)
                }
            } label: {
                Label(String(localized: "worktree.detail.openFinder"), systemImage: "folder")
            }

            Button {
                if let path = worktree.path {
                    repositoryManager.openInEditor(path)
                }
            } label: {
                Label(String(localized: "worktree.detail.openEditor"), systemImage: "chevron.left.forwardslash.chevron.right")
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
}

struct WorktreeDetailsSheet: View {
    @ObservedObject var worktree: Worktree
    @ObservedObject var repositoryManager: RepositoryManager
    @Environment(\.dismiss) private var dismiss

    @State private var currentBranch = ""
    @State private var ahead = 0
    @State private var behind = 0
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(worktree.branch ?? String(localized: "worktree.list.unknown"))
                        .font(.title2)
                        .fontWeight(.bold)

                    if worktree.isPrimary {
                        Text("worktree.detail.primary", bundle: .main)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.blue, in: Capsule())
                    }
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Branch status
                    if isLoading {
                        HStack {
                            ProgressView()
                            Text("worktree.detail.loadingStatus", bundle: .main)
                                .foregroundStyle(.secondary)
                        }
                    } else if ahead > 0 || behind > 0 {
                        HStack(spacing: 16) {
                            if ahead > 0 {
                                Label(String(localized: "worktree.detail.ahead \(ahead)"), systemImage: "arrow.up.circle.fill")
                                    .foregroundStyle(.green)
                            }
                            if behind > 0 {
                                Label(String(localized: "worktree.detail.behind \(behind)"), systemImage: "arrow.down.circle.fill")
                                    .foregroundStyle(.orange)
                            }
                        }
                    } else {
                        Label(String(localized: "worktree.detail.upToDate"), systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }

                    // Info
                    GroupBox(String(localized: "worktree.detail.information")) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("worktree.detail.path", bundle: .main)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 80, alignment: .leading)
                                Text(worktree.path ?? String(localized: "worktree.list.unknown"))
                                    .textSelection(.enabled)
                            }

                            Divider()

                            HStack {
                                Text("worktree.detail.branch", bundle: .main)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 80, alignment: .leading)
                                Text(currentBranch.isEmpty ? (worktree.branch ?? String(localized: "worktree.list.unknown")) : currentBranch)
                                    .textSelection(.enabled)
                            }

                            if let lastAccessed = worktree.lastAccessed {
                                Divider()
                                HStack {
                                    Text("worktree.detail.lastAccessed", bundle: .main)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 80, alignment: .leading)
                                    Text(lastAccessed.formatted(date: .abbreviated, time: .shortened))
                                }
                            }
                        }
                        .padding(8)
                    }

                    if let error = errorMessage {
                        Text(error)
                            .foregroundStyle(.red)
                            .padding()
                            .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding()
            }
        }
        .frame(width: 500, height: 400)
        .onAppear {
            refreshStatus()
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
}

#Preview {
    WorktreeListView(
        repository: Repository(),
        selectedWorktree: .constant(nil),
        repositoryManager: RepositoryManager(viewContext: PersistenceController.preview.container.viewContext)
    )
}
