//
//  WorktreeCreateSheet.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import SwiftUI

enum EnvironmentCreationMode: String, CaseIterable {
    case linked
    case independent

    var title: String {
        switch self {
        case .linked:
            return "Linked (Git Environment)"
        case .independent:
            return "Independent (Clone/Copy)"
        }
    }
}

struct WorktreeCreateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var repository: Repository
    @ObservedObject var repositoryManager: WorkspaceRepositoryStore

    @State var mode: EnvironmentCreationMode = .linked
    @State var environmentName = ""
    @State var branchName = ""
    @State var selectedBranch: BranchInfo?
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State var validationWarning: String?
    @State var showingBranchSelector = false
    @State var selectedTemplateIndex: Int?
    @State var showingPostCreateActions = false
    @State var shouldRunPostCreateActions = true
    @State var independentMethod: WorkspaceRepositoryStore.IndependentEnvironmentMethod = .clone
    @State var detectedSubmodules: [GitSubmoduleInfo] = []
    @State var loadingSubmodules = false
    @State var initializeSubmodules = true
    @State var includeNestedSubmodules = true
    @State var selectedSubmodulePaths: Set<String> = []
    @State var matchSubmoduleBranchToEnvironment = false

    @AppStorage("branchNameTemplates") var branchNameTemplatesData: Data = Data()

    var branchNameTemplates: [String] {
        (try? JSONDecoder().decode([String].self, from: branchNameTemplatesData)) ?? []
    }

    var isGitProject: Bool {
        guard let repoPath = repository.path else { return false }
        return GitUtils.isGitRepository(at: repoPath)
    }

    var sourcePath: String? {
        let worktrees = (repository.worktrees as? Set<Worktree>) ?? []
        if let primary = worktrees.first(where: { $0.isPrimary }),
           let path = primary.path {
            return path
        }
        return repository.path
    }

    private var environmentRootDirectory: URL? {
        guard let repoPath = repository.path else { return nil }
        let repoName = URL(fileURLWithPath: repoPath).lastPathComponent
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("aizen/worktrees")
            .appendingPathComponent(repoName)
    }

    private var targetPath: String? {
        guard let root = environmentRootDirectory else { return nil }
        let trimmedName = environmentName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }
        return root.appendingPathComponent(trimmedName).path
    }

    var existingWorktreeNames: [String] {
        let worktrees = (repository.worktrees as? Set<Worktree>) ?? []
        return worktrees.compactMap { $0.branch }
    }

    var defaultBaseBranch: String {
        let worktrees = (repository.worktrees as? Set<Worktree>) ?? []
        if let mainWorktree = worktrees.first(where: { $0.isPrimary }) {
            return mainWorktree.branch ?? "main"
        }
        return "main"
    }

    var hasSubmodules: Bool {
        !detectedSubmodules.isEmpty
    }

    var selectedSubmoduleCount: Int {
        let available = Set(detectedSubmodules.map(\.path))
        return selectedSubmodulePaths.intersection(available).count
    }

    var branchNamePrompt: String {
        let trimmedName = environmentName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            return "feature-login-auth"
        }
        return "feature/\(trimmedName)"
    }

    var independentMethodDescription: String {
        switch independentMethod {
        case .clone:
            return "Clone creates a separate Git repository using git clone --local. It keeps .git, history, branches, and remotes."
        case .copy:
            return "Copy runs rsync and excludes .git. It only copies the current files, so the new environment is not a Git checkout."
        }
    }

    func submoduleSelectionBinding(for path: String) -> Binding<Bool> {
        Binding(
            get: { selectedSubmodulePaths.contains(path) },
            set: { selected in
                if selected {
                    selectedSubmodulePaths.insert(path)
                } else {
                    selectedSubmodulePaths.remove(path)
                    if selectedSubmodulePaths.isEmpty {
                        matchSubmoduleBranchToEnvironment = false
                    }
                }
            }
        )
    }

    var modeBinding: Binding<EnvironmentCreationMode> {
        Binding(
            get: { mode },
            set: { newMode in
                mode = newMode
                if newMode == .independent && !isGitProject {
                    independentMethod = .copy
                }
            }
        )
    }

    var branchNameBinding: Binding<String> {
        Binding(
            get: { branchName },
            set: { newValue in
                branchName = newValue
                validateBranchName()
            }
        )
    }

    var initializeSubmodulesBinding: Binding<Bool> {
        Binding(
            get: { initializeSubmodules },
            set: { newValue in
                initializeSubmodules = newValue
                if !newValue {
                    matchSubmoduleBranchToEnvironment = false
                }
            }
        )
    }

    var environmentNameWarning: String? {
        let trimmedName = environmentName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            return "Environment name is required."
        }
        if trimmedName.contains("/") {
            return "Environment name cannot contain '/'."
        }
        if let destination = targetPath, FileManager.default.fileExists(atPath: destination) {
            return "Destination already exists."
        }
        return nil
    }

    private var isValid: Bool {
        if environmentNameWarning != nil {
            return false
        }

        switch mode {
        case .linked:
            return isGitProject && !branchName.isEmpty && validationWarning == nil
        case .independent:
            return sourcePath != nil
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            DetailHeaderBar(showsBackground: false) {
                Text("Create Environment")
                    .font(.title2)
                    .fontWeight(.semibold)
            }

            Divider()

            Form {
                environmentTypeSection
                namingSection

                if mode == .linked {
                    linkedModeSections
                } else {
                    independentModeSections
                }

                postCreateActionsSection

                if let error = errorMessage {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .font(.callout)
                                Text("Environment creation failed")
                                    .font(.callout)
                                    .fontWeight(.semibold)
                            }
                            Text(error)
                                .font(.system(.caption, design: .monospaced))
                        }
                        .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            Divider()

            HStack {
                Spacer()

                Button(String(localized: "worktree.create.cancel")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Create Environment") {
                    createEnvironment()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(isProcessing || !isValid)
            }
            .padding()
        }
        .frame(width: 520)
        .frame(minHeight: 420, maxHeight: 560)
        .settingsSheetChrome()
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
            suggestEnvironmentName()
            if !isGitProject {
                mode = .independent
                independentMethod = .copy
            }
            loadSubmodules()
        }
    }

    private func loadSubmodules() {
        guard isGitProject else {
            detectedSubmodules = []
            initializeSubmodules = false
            selectedSubmodulePaths = []
            matchSubmoduleBranchToEnvironment = false
            loadingSubmodules = false
            return
        }

        loadingSubmodules = true
        Task {
            let submodules = await repositoryManager.listSubmodules(for: repository)
            await MainActor.run {
                detectedSubmodules = submodules
                initializeSubmodules = !submodules.isEmpty
                selectedSubmodulePaths = Set(submodules.map(\.path))
                if submodules.isEmpty {
                    matchSubmoduleBranchToEnvironment = false
                }
                loadingSubmodules = false
            }
        }
    }

    func createEnvironment() {
        guard !isProcessing, isValid else { return }
        guard let destinationPath = targetPath else { return }

        let baseBranchName = selectedBranch?.name ?? defaultBaseBranch
        let source = sourcePath

        isProcessing = true
        errorMessage = nil

        Task {
            do {
                switch mode {
                case .linked:
                    let submoduleOptions: WorkspaceRepositoryStore.LinkedEnvironmentSubmoduleOptions
                    let selectedPaths = detectedSubmodules
                        .map(\.path)
                        .filter { selectedSubmodulePaths.contains($0) }
                    if initializeSubmodules && !selectedPaths.isEmpty {
                        submoduleOptions = WorkspaceRepositoryStore.LinkedEnvironmentSubmoduleOptions(
                            initialize: true,
                            recursive: includeNestedSubmodules,
                            paths: selectedPaths,
                            matchBranchToEnvironment: matchSubmoduleBranchToEnvironment && !branchName.isEmpty
                        )
                    } else {
                        submoduleOptions = .disabled
                    }

                    _ = try await repositoryManager.addLinkedEnvironment(
                        to: repository,
                        path: destinationPath,
                        branch: branchName,
                        createBranch: true,
                        baseBranch: baseBranchName,
                        submoduleOptions: submoduleOptions,
                        runPostCreateActions: shouldRunPostCreateActions
                    )
                case .independent:
                    guard let source else {
                        throw Libgit2Error.invalidPath("Source path is unavailable")
                    }
                    let method: WorkspaceRepositoryStore.IndependentEnvironmentMethod = isGitProject ? independentMethod : .copy
                    _ = try await repositoryManager.addIndependentEnvironment(
                        to: repository,
                        path: destinationPath,
                        sourcePath: source,
                        method: method,
                        runPostCreateActions: shouldRunPostCreateActions
                    )
                }

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
        repositoryManager: WorkspaceRepositoryStore(viewContext: PersistenceController.preview.container.viewContext)
    )
}
