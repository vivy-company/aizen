//
//  WorktreeCreateSheet.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import SwiftUI

struct WorktreeCreateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var repository: Repository
    @ObservedObject var repositoryManager: RepositoryManager

    @State private var folderName = ""
    @State private var branchName = ""
    @State private var selectedBranch: BranchInfo?
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var validationWarning: String?
    @State private var showingBranchSelector = false

    private var currentBranch: String {
        // Get main branch from repository worktrees
        let worktrees = (repository.worktrees as? Set<Worktree>) ?? []
        return worktrees.first(where: { $0.isPrimary })?.branch ?? "main"
    }

    private var existingWorktreeNames: [String] {
        let worktrees = (repository.worktrees as? Set<Worktree>) ?? []
        return worktrees.compactMap { $0.branch }
    }

    private var defaultBaseBranch: String {
        // Try to find main or master branch
        let worktrees = (repository.worktrees as? Set<Worktree>) ?? []
        if let mainWorktree = worktrees.first(where: { $0.isPrimary }) {
            return mainWorktree.branch ?? "main"
        }
        return "main"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("worktree.create.title", bundle: .main)
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()
            }
            .padding()

            Divider()

            // Content
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("worktree.create.branchName", bundle: .main)
                            .font(.headline)

                        Spacer()

                        Button {
                            generateRandomName()
                        } label: {
                            Image(systemName: "shuffle")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help(String(localized: "worktree.create.generateRandom"))
                    }

                    TextField(String(localized: "worktree.create.branchNamePlaceholder"), text: $branchName)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: branchName) { _ in
                            validateBranchName()
                        }
                        .onSubmit {
                            if !branchName.isEmpty && validationWarning == nil {
                                createWorktree()
                            }
                        }

                    if let warning = validationWarning {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption)
                            Text(warning)
                                .font(.caption)
                        }
                        .foregroundStyle(.orange)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("worktree.create.baseBranch", bundle: .main)
                        .font(.headline)

                    BranchSelectorButton(
                        selectedBranch: selectedBranch,
                        defaultBranch: defaultBaseBranch,
                        isPresented: $showingBranchSelector
                    )

                    Text("worktree.create.baseBranchHelp", bundle: .main)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let error = errorMessage {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.callout)
                            Text("worktree.create.failed", bundle: .main)
                                .font(.callout)
                                .fontWeight(.semibold)
                        }
                        Text(error)
                            .font(.system(.caption, design: .monospaced))
                    }
                    .foregroundStyle(.red)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding()

            Spacer()

            Divider()

            // Footer
            HStack {
                Spacer()

                Button(String(localized: "worktree.create.cancel")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(String(localized: "worktree.create.create")) {
                    createWorktree()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(isProcessing || branchName.isEmpty || validationWarning != nil)
            }
            .padding()
        }
        .frame(width: 450)
        .frame(minHeight: 300, maxHeight: 350)
        .sheet(isPresented: $showingBranchSelector) {
            BranchSelectorView(
                repository: repository,
                repositoryManager: repositoryManager,
                selectedBranch: $selectedBranch
            )
        }
        .onAppear {
            suggestWorktreeName()
        }
    }

    private func suggestWorktreeName() {
        generateRandomName()
    }

    private func generateRandomName() {
        let excludedNames = Set(existingWorktreeNames)
        let generated = WorkspaceNameGenerator.generateUniqueName(excluding: Array(excludedNames))
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "'", with: "")
        folderName = generated
        branchName = generated
        validateBranchName()
    }

    private func validateBranchName() {
        guard !branchName.isEmpty else {
            validationWarning = nil
            return
        }

        // Check against existing branch names
        if existingWorktreeNames.contains(branchName) {
            validationWarning = String(localized: "worktree.create.branchExists \(branchName)")
        } else {
            validationWarning = nil
        }
    }

    private func createWorktree() {
        guard !isProcessing, !branchName.isEmpty else { return }

        // Use selectedBranch if available, otherwise use default branch
        let baseBranchName: String
        if let selected = selectedBranch {
            baseBranchName = selected.name
        } else {
            baseBranchName = defaultBaseBranch
        }

        guard let repoPath = repository.path else {
            errorMessage = String(localized: "worktree.create.invalidRepoPath")
            return
        }

        isProcessing = true
        errorMessage = nil

        Task {
            do {
                // Build path: repo/.aizen/{folderName}
                let repoURL = URL(fileURLWithPath: repoPath)
                let aizenDir = repoURL.appendingPathComponent(".aizen")
                let worktreePath = aizenDir.appendingPathComponent(folderName).path

                // Create new branch from selected base branch and create worktree
                _ = try await repositoryManager.addWorktree(
                    to: repository,
                    path: worktreePath,
                    branch: branchName,
                    createBranch: true,
                    baseBranch: baseBranchName
                )

                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    if let gitError = error as? GitError {
                        errorMessage = gitError.errorDescription
                    } else {
                        errorMessage = error.localizedDescription
                    }
                    isProcessing = false
                }
            }
        }
    }
}

#Preview {
    WorktreeCreateSheet(
        repository: Repository(),
        repositoryManager: RepositoryManager(viewContext: PersistenceController.preview.container.viewContext)
    )
}
