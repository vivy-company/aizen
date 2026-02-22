//
//  WorktreeCreateSheet.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import SwiftUI

private enum EnvironmentCreationMode: String, CaseIterable {
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
    @ObservedObject var repositoryManager: RepositoryManager

    @State private var mode: EnvironmentCreationMode = .linked
    @State private var environmentName = ""
    @State private var branchName = ""
    @State private var selectedBranch: BranchInfo?
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var validationWarning: String?
    @State private var showingBranchSelector = false
    @State private var selectedTemplateIndex: Int?
    @State private var showingPostCreateActions = false
    @State private var independentMethod: RepositoryManager.IndependentEnvironmentMethod = .clone
    @State private var detectedSubmodules: [GitSubmoduleInfo] = []
    @State private var loadingSubmodules = false
    @State private var initializeSubmodules = true
    @State private var includeNestedSubmodules = true
    @State private var selectedSubmodulePaths: Set<String> = []
    @State private var matchSubmoduleBranchToEnvironment = false

    @AppStorage("branchNameTemplates") private var branchNameTemplatesData: Data = Data()

    private var branchNameTemplates: [String] {
        (try? JSONDecoder().decode([String].self, from: branchNameTemplatesData)) ?? []
    }

    private var isGitProject: Bool {
        guard let repoPath = repository.path else { return false }
        return GitUtils.isGitRepository(at: repoPath)
    }

    private var sourcePath: String? {
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

    private var existingWorktreeNames: [String] {
        let worktrees = (repository.worktrees as? Set<Worktree>) ?? []
        return worktrees.compactMap { $0.branch }
    }

    private var defaultBaseBranch: String {
        let worktrees = (repository.worktrees as? Set<Worktree>) ?? []
        if let mainWorktree = worktrees.first(where: { $0.isPrimary }) {
            return mainWorktree.branch ?? "main"
        }
        return "main"
    }

    private var hasSubmodules: Bool {
        !detectedSubmodules.isEmpty
    }

    private var selectedSubmoduleCount: Int {
        let available = Set(detectedSubmodules.map(\.path))
        return selectedSubmodulePaths.intersection(available).count
    }

    private var branchNamePrompt: String {
        let trimmedName = environmentName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            return "feature-login-auth"
        }
        return "feature/\(trimmedName)"
    }

    private func submoduleSelectionBinding(for path: String) -> Binding<Bool> {
        Binding(
            get: { selectedSubmodulePaths.contains(path) },
            set: { selected in
                if selected {
                    selectedSubmodulePaths.insert(path)
                } else {
                    selectedSubmodulePaths.remove(path)
                }
            }
        )
    }

    private var environmentNameWarning: String? {
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
        .onChange(of: initializeSubmodules) { _, newValue in
            if !newValue {
                matchSubmoduleBranchToEnvironment = false
            }
        }
        .onChange(of: selectedSubmodulePaths) { _, _ in
            if selectedSubmoduleCount == 0 {
                matchSubmoduleBranchToEnvironment = false
            }
        }
    }

    @ViewBuilder
    private var environmentTypeSection: some View {
        Section("Environment Type") {
            Picker("Type", selection: $mode) {
                Text(EnvironmentCreationMode.linked.title)
                    .tag(EnvironmentCreationMode.linked)
                    .disabled(!isGitProject)
                Text(EnvironmentCreationMode.independent.title)
                    .tag(EnvironmentCreationMode.independent)
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            .onChange(of: mode) { _, newMode in
                if newMode == .independent && !isGitProject {
                    independentMethod = .copy
                }
            }

            if !isGitProject && mode == .linked {
                warningRow("Linked environments require a git project. Use Independent mode instead.")
            }
        }
    }

    @ViewBuilder
    private var namingSection: some View {
        Section("Naming") {
            LabeledContent("Environment Name") {
                TextField("", text: $environmentName, prompt: Text("feature-landing-redesign"))
                    .frame(maxWidth: 280)
            }

            if let warning = environmentNameWarning {
                warningRow(warning)
            }

            if mode == .linked {
                LabeledContent {
                    HStack(spacing: 8) {
                        TextField("", text: $branchName, prompt: Text(branchNamePrompt))
                            .frame(maxWidth: 260)
                            .onChange(of: branchName) { _, _ in
                                validateBranchName()
                            }
                            .onSubmit {
                                if !branchName.isEmpty && validationWarning == nil {
                                    createEnvironment()
                                }
                            }
                        Button {
                            generateRandomName()
                        } label: {
                            Image(systemName: "shuffle")
                        }
                        .buttonStyle(.borderless)
                        .help(String(localized: "worktree.create.generateRandom"))
                    }
                } label: {
                    Text(String(localized: "worktree.create.branchName", bundle: .main))
                }

                if !branchNameTemplates.isEmpty {
                    ScrollView(.horizontal) {
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
                        .padding(.vertical, 2)
                    }
                }

                if let warning = validationWarning {
                    warningRow(warning)
                }
            }
        }
    }

    @ViewBuilder
    private var linkedModeSections: some View {
        Section(String(localized: "worktree.create.baseBranch", bundle: .main)) {
            BranchSelectorButton(
                selectedBranch: selectedBranch,
                defaultBranch: defaultBaseBranch,
                isPresented: $showingBranchSelector
            )

            Text("worktree.create.baseBranchHelp", bundle: .main)
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Section("Submodules") {
            if loadingSubmodules {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Detecting submodules...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if hasSubmodules {
                Toggle("Initialize submodules after environment creation", isOn: $initializeSubmodules)
                Toggle("Include nested submodules recursively", isOn: $includeNestedSubmodules)
                    .disabled(!initializeSubmodules)

                Text("\(selectedSubmoduleCount) of \(detectedSubmodules.count) submodule\(detectedSubmodules.count == 1 ? "" : "s") selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if initializeSubmodules {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(detectedSubmodules.prefix(8)), id: \.path) { submodule in
                            Toggle(isOn: submoduleSelectionBinding(for: submodule.path)) {
                                Text(submodule.path)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .toggleStyle(.checkbox)
                            .controlSize(.small)
                        }

                        if detectedSubmodules.count > 8 {
                            Text("+\(detectedSubmodules.count - 8) more")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

                    Toggle(
                        "Checkout/create branch '\(branchName.isEmpty ? "new-environment" : branchName)' in selected submodules",
                        isOn: $matchSubmoduleBranchToEnvironment
                    )
                    .disabled(selectedSubmoduleCount == 0 || branchName.isEmpty)
                }
            } else {
                Text("No submodules detected in this repository.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var independentModeSections: some View {
        Section("Source") {
            Text(sourcePath ?? "No source path available")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)

            if !isGitProject {
                Text("Files will be copied into a separate environment.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        if isGitProject {
            Section("Method") {
                Picker("Method", selection: $independentMethod) {
                    Text("Clone")
                        .tag(RepositoryManager.IndependentEnvironmentMethod.clone)
                    Text("Copy")
                        .tag(RepositoryManager.IndependentEnvironmentMethod.copy)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }
        }
    }

    @ViewBuilder
    private var postCreateActionsSection: some View {
        let actions = repository.postCreateActions
        let enabledCount = actions.filter { $0.enabled }.count

        Section("Post-Create Actions") {
            Button {
                showingPostCreateActions = true
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    if actions.isEmpty {
                        Image(systemName: "gearshape.2")
                            .font(.body)
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("No actions configured")
                                .font(.callout)
                            Text("Tap to add actions that run after environment creation")
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
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            if enabledCount > 0 {
                Text("\(enabledCount) action\(enabledCount == 1 ? "" : "s") will run after creation")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func warningRow(_ warning: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
            Text(warning)
                .font(.caption)
        }
        .foregroundStyle(.orange)
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

    private func suggestEnvironmentName() {
        generateRandomName()
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

    private func generateRandomName() {
        let excludedNames = Set(existingWorktreeNames)
        let generated = WorkspaceNameGenerator.generateUniqueName(excluding: Array(excludedNames))
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "'", with: "")
        environmentName = generated
        branchName = generated
        validateBranchName()
    }

    private func validateBranchName() {
        guard mode == .linked else {
            validationWarning = nil
            return
        }

        guard !branchName.isEmpty else {
            validationWarning = nil
            return
        }

        if existingWorktreeNames.contains(branchName) {
            validationWarning = String(localized: "worktree.create.branchExists \(branchName)")
        } else {
            validationWarning = nil
        }
    }

    private func createEnvironment() {
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
                    let submoduleOptions: RepositoryManager.LinkedEnvironmentSubmoduleOptions
                    let selectedPaths = detectedSubmodules
                        .map(\.path)
                        .filter { selectedSubmodulePaths.contains($0) }
                    if initializeSubmodules && !selectedPaths.isEmpty {
                        submoduleOptions = RepositoryManager.LinkedEnvironmentSubmoduleOptions(
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
                        submoduleOptions: submoduleOptions
                    )
                case .independent:
                    guard let source else {
                        throw Libgit2Error.invalidPath("Source path is unavailable")
                    }
                    let method: RepositoryManager.IndependentEnvironmentMethod = isGitProject ? independentMethod : .copy
                    _ = try await repositoryManager.addIndependentEnvironment(
                        to: repository,
                        path: destinationPath,
                        sourcePath: source,
                        method: method
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
        repositoryManager: RepositoryManager(viewContext: PersistenceController.preview.container.viewContext)
    )
}
