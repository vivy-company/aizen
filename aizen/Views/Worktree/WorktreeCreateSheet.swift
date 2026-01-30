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
    @State private var selectedTemplateIndex: Int?
    @State private var showingPostCreateActions = false

    @AppStorage("branchNameTemplates") private var branchNameTemplatesData: Data = Data()

    private var branchNameTemplates: [String] {
        (try? JSONDecoder().decode([String].self, from: branchNameTemplatesData)) ?? []
    }

    private var currentPlaceholder: String {
        if let index = selectedTemplateIndex, index < branchNameTemplates.count {
            return branchNameTemplates[index]
        }
        return String(localized: "worktree.create.branchNamePlaceholder")
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
            DetailHeaderBar(showsBackground: false) {
                Text("worktree.create.title", bundle: .main)
                    .font(.title2)
                    .fontWeight(.semibold)
            }

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

                    TextField(currentPlaceholder, text: $branchName)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: branchName) { _, _ in
                            validateBranchName()
                        }
                        .onSubmit {
                            if !branchName.isEmpty && validationWarning == nil {
                                createWorktree()
                            }
                        }

                    if !branchNameTemplates.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(Array(branchNameTemplates.enumerated()), id: \.offset) { index, template in
                                Button {
                                    if selectedTemplateIndex == index {
                                        selectedTemplateIndex = nil
                                    } else {
                                        selectedTemplateIndex = index
                                        branchName = template
                                    }
                                    validateBranchName()
                                } label: {
                                    Text(template)
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(
                                            selectedTemplateIndex == index
                                                ? Color.accentColor.opacity(0.3)
                                                : Color.secondary.opacity(0.2),
                                            in: Capsule()
                                        )
                                }
                                .buttonStyle(.plain)
                            }
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

                // Post-create actions section
                postCreateActionsSection

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
        .frame(minHeight: 380, maxHeight: 480)
        .sheet(isPresented: $showingBranchSelector) {
            BranchSelectorView(
                repository: repository,
                repositoryManager: repositoryManager,
                selectedBranch: $selectedBranch
            )
        }
        .sheet(isPresented: $showingPostCreateActions) {
            PostCreateActionsSheet(repository: repository)
        }
        .onAppear {
            suggestWorktreeName()
        }
    }

    @ViewBuilder
    private var postCreateActionsSection: some View {
        let actions = repository.postCreateActions
        let enabledCount = actions.filter { $0.enabled }.count

        VStack(alignment: .leading, spacing: 8) {
            Text("Post-Create Actions")
                .font(.headline)

            Button {
                showingPostCreateActions = true
            } label: {
                HStack {
                    if actions.isEmpty {
                        Image(systemName: "gearshape.2")
                            .font(.title3)
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("No actions configured")
                                .font(.subheadline)
                            Text("Tap to add actions that run after worktree creation")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(actions.prefix(3)) { action in
                                HStack(spacing: 6) {
                                    Image(systemName: action.enabled ? "checkmark.circle.fill" : "circle")
                                        .font(.caption)
                                        .foregroundStyle(action.enabled ? .green : .secondary)
                                    Image(systemName: action.type.icon)
                                        .font(.caption)
                                        .frame(width: 14)
                                    Text(actionSummary(action))
                                        .font(.caption)
                                        .lineLimit(1)
                                }
                                .foregroundStyle(action.enabled ? .primary : .secondary)
                            }

                            if actions.count > 3 {
                                Text("+\(actions.count - 3) more")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.controlBackgroundColor).opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            if enabledCount > 0 {
                Text("\(enabledCount) action\(enabledCount == 1 ? "" : "s") will run after creation")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func actionSummary(_ action: PostCreateAction) -> String {
        switch action.config {
        case .copyFiles(let config):
            return config.displayPatterns
        case .runCommand(let config):
            return config.command
        case .symlink(let config):
            return "Link \(config.source)"
        case .customScript:
            return "Custom script"
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
                // Build path: ~/aizen/worktrees/{repoName}/{folderName}
                let repoName = URL(fileURLWithPath: repoPath).lastPathComponent
                let worktreesDir = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("aizen/worktrees")
                    .appendingPathComponent(repoName)
                let worktreePath = worktreesDir.appendingPathComponent(folderName).path

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
                    if let libgit2Error = error as? Libgit2Error {
                        errorMessage = libgit2Error.errorDescription
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
