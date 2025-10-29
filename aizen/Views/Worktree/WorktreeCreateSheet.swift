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

    @State private var worktreeName = ""
    @State private var selectedBranch: BranchInfo?
    @State private var branches: [BranchInfo] = []
    @State private var isLoadingBranches = true
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var validationWarning: String?

    private var currentBranch: String {
        // Get main branch from repository worktrees
        let worktrees = (repository.worktrees as? Set<Worktree>) ?? []
        return worktrees.first(where: { $0.isPrimary })?.branch ?? "main"
    }

    private var existingWorktreeNames: [String] {
        let worktrees = (repository.worktrees as? Set<Worktree>) ?? []
        return worktrees.compactMap { $0.branch }
    }

    private var existingBranchNames: [String] {
        branches.map { $0.name }
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

                    TextField(String(localized: "worktree.create.branchNamePlaceholder"), text: $worktreeName)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: worktreeName) { newValue in
                            // Slugify in real-time
                            let slugified = newValue
                                .replacingOccurrences(of: " ", with: "-")
                                .lowercased()

                            if slugified != newValue {
                                worktreeName = slugified
                            }

                            // Validate branch name
                            validateBranchName()
                        }
                        .onSubmit {
                            if !worktreeName.isEmpty && validationWarning == nil {
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

                    if isLoadingBranches {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Picker(String(localized: "worktree.create.baseBranch"), selection: $selectedBranch) {
                            ForEach(branches, id: \.id) { branch in
                                Text(branch.name)
                                    .tag(branch as BranchInfo?)
                            }
                        }
                        .labelsHidden()
                    }

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
                .disabled(isProcessing || worktreeName.isEmpty || validationWarning != nil)
            }
            .padding()
        }
        .frame(width: 450)
        .frame(minHeight: 300, maxHeight: 350)
        .onAppear {
            loadBranches()
            suggestWorktreeName()
        }
    }

    private func loadBranches() {
        isLoadingBranches = true

        Task {
            do {
                let loadedBranches = try await repositoryManager.getBranches(for: repository)
                await MainActor.run {
                    // Only local branches
                    branches = loadedBranches.filter { !$0.isRemote }
                    // Select current branch by default
                    selectedBranch = branches.first(where: { $0.name == currentBranch }) ?? branches.first
                    isLoadingBranches = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = String(localized: "worktree.create.failedLoadBranches \(error.localizedDescription)")
                    isLoadingBranches = false
                }
            }
        }
    }

    private func suggestWorktreeName() {
        generateRandomName()
    }

    private func generateRandomName() {
        // Combine both worktree names and branch names to avoid conflicts
        let excludedNames = Set(existingWorktreeNames + existingBranchNames)
        worktreeName = WorkspaceNameGenerator.generateUniqueName(excluding: Array(excludedNames))
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "'", with: "")
        validateBranchName()
    }

    private func validateBranchName() {
        guard !worktreeName.isEmpty else {
            validationWarning = nil
            return
        }

        if existingBranchNames.contains(worktreeName) {
            validationWarning = String(localized: "worktree.create.branchExists \(worktreeName)")
        } else {
            validationWarning = nil
        }
    }

    private func createWorktree() {
        guard !isProcessing, !worktreeName.isEmpty else { return }
        guard let selectedBranch = selectedBranch else {
            errorMessage = String(localized: "worktree.create.selectBaseBranch")
            return
        }
        guard let repoPath = repository.path else {
            errorMessage = String(localized: "worktree.create.invalidRepoPath")
            return
        }

        // Check if branch name already exists
        if existingBranchNames.contains(worktreeName) {
            errorMessage = String(localized: "worktree.create.branchExistsChooseDifferent \(worktreeName)")
            return
        }

        isProcessing = true
        errorMessage = nil

        Task {
            do {
                // Build path: repo/.aizen/{branch-name}
                let repoURL = URL(fileURLWithPath: repoPath)
                let aizenDir = repoURL.appendingPathComponent(".aizen")
                let worktreePath = aizenDir.appendingPathComponent(worktreeName).path

                // Create new branch from selected base branch and create worktree
                _ = try await repositoryManager.addWorktree(
                    to: repository,
                    path: worktreePath,
                    branch: worktreeName,
                    createBranch: true,
                    baseBranch: selectedBranch.name
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
