//
//  PostCreateActionsView.swift
//  aizen
//

import SwiftUI
import CoreData

struct PostCreateActionsView: View {
    @ObservedObject var repository: Repository
    var showHeader: Bool = true
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var templateManager = PostCreateTemplateManager.shared

    @State private var actions: [PostCreateAction] = []
    @State private var showingAddAction = false
    @State private var showingTemplates = false
    @State private var editingAction: PostCreateAction?
    @State private var showGeneratedScript = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if showHeader {
                headerSection
            } else {
                inlineAddMenu
            }
            actionsListSection
            if !actions.isEmpty {
                scriptPreviewSection
            }
        }
        .onAppear {
            actions = repository.postCreateActions
        }
        .onChange(of: actions) { newValue in
            repository.postCreateActions = newValue
            try? viewContext.save()
        }
        .sheet(isPresented: $showingAddAction) {
            PostCreateActionEditorSheet(
                action: nil,
                onSave: { action in
                    actions.append(action)
                },
                onCancel: {},
                repositoryPath: repository.path
            )
        }
        .sheet(item: $editingAction) { action in
            PostCreateActionEditorSheet(
                action: action,
                onSave: { updated in
                    if let index = actions.firstIndex(where: { $0.id == updated.id }) {
                        actions[index] = updated
                    }
                },
                onCancel: {},
                repositoryPath: repository.path
            )
        }
        .sheet(isPresented: $showingTemplates) {
            PostCreateTemplatesSheet(
                onSelect: { template in
                    actions = template.actions
                }
            )
        }
    }

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Post-Create Actions")
                    .font(.headline)
                Text("Run after creating new worktrees")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            addMenuButton
        }
    }

    private var inlineAddMenu: some View {
        HStack {
            Spacer()
            addMenuButton
        }
    }

    private var addMenuButton: some View {
        Menu {
            Button {
                showingAddAction = true
            } label: {
                Label("Add Action", systemImage: "plus")
            }

            Divider()

            Button {
                showingTemplates = true
            } label: {
                Label("Apply Template", systemImage: "doc.on.doc")
            }

            if !actions.isEmpty {
                Divider()

                Button(role: .destructive) {
                    actions.removeAll()
                } label: {
                    Label("Clear All", systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: "plus.circle.fill")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
    }

    private var actionsListSection: some View {
        Group {
            if actions.isEmpty {
                emptyStateView
            } else {
                actionsList
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "gearshape.2")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)

            Text("No Actions Configured")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button("Add Action") {
                    showingAddAction = true
                }
                .buttonStyle(.bordered)

                Button("Use Template") {
                    showingTemplates = true
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(Color(.controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var actionsList: some View {
        VStack(spacing: 0) {
            ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                actionRow(action, at: index)

                if index < actions.count - 1 {
                    Divider()
                        .padding(.leading, 44)
                }
            }
        }
        .background(Color(.controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func actionRow(_ action: PostCreateAction, at index: Int) -> some View {
        HStack(spacing: 12) {
            // Drag handle
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .font(.system(size: 12))

            // Toggle
            Toggle("", isOn: Binding(
                get: { action.enabled },
                set: { newValue in
                    var updated = action
                    updated.enabled = newValue
                    actions[index] = updated
                }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()

            // Icon
            Image(systemName: action.type.icon)
                .frame(width: 20)
                .foregroundStyle(action.enabled ? .primary : .tertiary)

            // Content
            VStack(alignment: .leading, spacing: 2) {
                Text(action.type.displayName)
                    .fontWeight(.medium)
                    .foregroundStyle(action.enabled ? .primary : .secondary)

                Text(actionDescription(action))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Actions
            HStack(spacing: 8) {
                Button {
                    editingAction = action
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)

                Button {
                    actions.remove(at: index)
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private func actionDescription(_ action: PostCreateAction) -> String {
        switch action.config {
        case .copyFiles(let config):
            return config.displayPatterns
        case .runCommand(let config):
            return config.command
        case .symlink(let config):
            return "\(config.target) → \(config.source)"
        case .customScript(let config):
            let firstLine = config.script.split(separator: "\n").first ?? ""
            return String(firstLine.prefix(50))
        }
    }

    @ViewBuilder
    private var scriptPreviewSection: some View {
        DisclosureGroup(isExpanded: $showGeneratedScript) {
            ScrollView {
                Text(PostCreateScriptGenerator.generateScript(from: actions))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(height: 150)
            .background(Color(.textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        } label: {
            Label("Generated Script", systemImage: "scroll")
                .font(.subheadline)
        }
    }
}

// MARK: - Action Editor Sheet

struct PostCreateActionEditorSheet: View {
    let action: PostCreateAction?
    let onSave: (PostCreateAction) -> Void
    let onCancel: () -> Void
    var repositoryPath: String?

    @Environment(\.dismiss) private var dismiss

    @State private var selectedType: PostCreateActionType = .copyFiles
    @State private var patterns: String = ""
    @State private var command: String = ""
    @State private var workingDirectory: WorkingDirectory = .newWorktree
    @State private var symlinkSource: String = ""
    @State private var symlinkTarget: String = ""
    @State private var customScript: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Cancel") {
                    dismiss()
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Text(action == nil ? "Add Action" : "Edit Action")
                    .fontWeight(.semibold)

                Spacer()

                Button("Save") {
                    saveAction()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
            .padding()

            Divider()

            // Content
            Form {
                Section {
                    Picker("Action Type", selection: $selectedType) {
                        ForEach(PostCreateActionType.allCases, id: \.self) { type in
                            Label(type.displayName, systemImage: type.icon)
                                .tag(type)
                        }
                    }
                }

                Section {
                    configEditorForType
                } header: {
                    Text(selectedType.actionDescription)
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 450, height: 350)
        .onAppear {
            if let action = action {
                loadAction(action)
            }
        }
    }

    @ViewBuilder
    private var configEditorForType: some View {
        switch selectedType {
        case .copyFiles:
            TextField("Patterns (comma separated)", text: $patterns)
                .textFieldStyle(.roundedBorder)
            Text("e.g., .env, .env.local, .vscode/**")
                .font(.caption)
                .foregroundStyle(.secondary)

        case .runCommand:
            TextField("Command", text: $command)
                .textFieldStyle(.roundedBorder)

            Picker("Run in", selection: $workingDirectory) {
                ForEach(WorkingDirectory.allCases, id: \.self) { dir in
                    Text(dir.displayName).tag(dir)
                }
            }

        case .symlink:
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    TextField("Path relative to worktree root", text: $symlinkSource)
                        .textFieldStyle(.roundedBorder)

                    Button {
                        selectSymlinkSource()
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.bordered)
                }

                if !symlinkSource.isEmpty {
                    Text("Will create: \(effectiveSymlinkTarget)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

        case .customScript:
            TextEditor(text: $customScript)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 100)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(.separatorColor), lineWidth: 1)
                )
        }
    }

    private var isValid: Bool {
        switch selectedType {
        case .copyFiles:
            return !patterns.trimmingCharacters(in: .whitespaces).isEmpty
        case .runCommand:
            return !command.trimmingCharacters(in: .whitespaces).isEmpty
        case .symlink:
            return !symlinkSource.trimmingCharacters(in: .whitespaces).isEmpty
        case .customScript:
            return !customScript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var effectiveSymlinkTarget: String {
        symlinkTarget.isEmpty ? symlinkSource : symlinkTarget
    }

    private func selectSymlinkSource() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select file or folder to symlink"

        if let repoPath = repositoryPath {
            panel.directoryURL = URL(fileURLWithPath: repoPath)
        }

        if panel.runModal() == .OK, let url = panel.url {
            // Convert to relative path if inside repository
            if let repoPath = repositoryPath {
                let repoURL = URL(fileURLWithPath: repoPath)
                if url.path.hasPrefix(repoURL.path) {
                    var relativePath = String(url.path.dropFirst(repoURL.path.count))
                    if relativePath.hasPrefix("/") {
                        relativePath = String(relativePath.dropFirst())
                    }
                    symlinkSource = relativePath
                    return
                }
            }
            symlinkSource = url.lastPathComponent
        }
    }

    private func loadAction(_ action: PostCreateAction) {
        selectedType = action.type
        switch action.config {
        case .copyFiles(let config):
            patterns = config.patterns.joined(separator: ", ")
        case .runCommand(let config):
            command = config.command
            workingDirectory = config.workingDirectory
        case .symlink(let config):
            symlinkSource = config.source
            symlinkTarget = config.target
        case .customScript(let config):
            customScript = config.script
        }
    }

    private func saveAction() {
        let config: ActionConfig
        switch selectedType {
        case .copyFiles:
            let patternList = patterns.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            config = .copyFiles(CopyFilesConfig(patterns: patternList))
        case .runCommand:
            config = .runCommand(RunCommandConfig(command: command, workingDirectory: workingDirectory))
        case .symlink:
            config = .symlink(SymlinkConfig(source: symlinkSource, target: effectiveSymlinkTarget))
        case .customScript:
            config = .customScript(CustomScriptConfig(script: customScript))
        }

        let newAction = PostCreateAction(
            id: action?.id ?? UUID(),
            type: selectedType,
            enabled: action?.enabled ?? true,
            config: config
        )

        onSave(newAction)
        dismiss()
    }
}

// MARK: - Templates Sheet

struct PostCreateTemplatesSheet: View {
    let onSelect: (PostCreateTemplate) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var templateManager = PostCreateTemplateManager.shared

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Text("Apply Template")
                    .fontWeight(.semibold)

                Spacer()

                Color.clear.frame(width: 60)
            }
            .padding()

            Divider()

            // Templates list
            ScrollView {
                LazyVStack(spacing: 8) {
                    Section {
                        ForEach(PostCreateTemplate.builtInTemplates) { template in
                            templateRow(template, isBuiltIn: true)
                        }
                    } header: {
                        sectionHeader("Built-in Templates")
                    }

                    if !templateManager.customTemplates.isEmpty {
                        Section {
                            ForEach(templateManager.customTemplates) { template in
                                templateRow(template, isBuiltIn: false)
                            }
                        } header: {
                            sectionHeader("Custom Templates")
                        }
                    }
                }
                .padding()
            }
        }
        .frame(width: 400, height: 450)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
    }

    private func templateRow(_ template: PostCreateTemplate, isBuiltIn: Bool) -> some View {
        Button {
            onSelect(template)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: template.icon)
                    .font(.title2)
                    .frame(width: 32)
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(template.name)
                        .fontWeight(.medium)

                    Text("\(template.actions.count) action\(template.actions.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isBuiltIn {
                    Text("Built-in")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(.systemGray).opacity(0.2))
                        .clipShape(Capsule())
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(.controlBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Actions Sheet (for Repository context menu)

struct PostCreateActionsSheet: View {
    @ObservedObject var repository: Repository
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)

                Spacer()

                Text("Post-Create Actions")
                    .fontWeight(.semibold)

                Spacer()

                Color.clear.frame(width: 50)
            }
            .padding(.horizontal)
            .padding(.vertical, 12)

            Divider()

            // Content
            ScrollView {
                PostCreateActionsView(repository: repository, showHeader: false)
                    .padding()
            }
        }
        .frame(width: 480, height: 400)
        .environment(\.managedObjectContext, viewContext)
    }
}
