//
//  PostCreateActionsView.swift
//  aizen
//

import SwiftUI
import CoreData

struct PostCreateActionsView: View {
    @ObservedObject var repository: Repository
    @Binding var addActionRequested: Bool
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var templateManager = PostCreateTemplateManager.shared

    @State private var showingAddAction = false
    @State private var showingTemplates = false
    @State private var editingAction: PostCreateAction?
    @State private var showGeneratedScript = false
    @State private var pendingTemplate: PostCreateTemplate?

    private var actions: [PostCreateAction] {
        get { repository.postCreateActions }
        nonmutating set {
            repository.postCreateActions = newValue
            try? viewContext.save()
        }
    }

    private var enabledCount: Int {
        actions.filter(\.enabled).count
    }

    private var disabledCount: Int {
        actions.count - enabledCount
    }

    var body: some View {
        Form {
            overviewSection
            configuredActionsSection
            templatesSection

            if !actions.isEmpty {
                advancedSection
            }
        }
        .formStyle(.grouped)
        .settingsSurface()
        .onChange(of: addActionRequested) { _, requested in
            guard requested else { return }
            showingAddAction = true
            addActionRequested = false
        }
        .alert("Replace current actions?", isPresented: Binding(
            get: { pendingTemplate != nil },
            set: { newValue in
                if !newValue {
                    pendingTemplate = nil
                }
            }
        )) {
            Button("Cancel", role: .cancel) {
                pendingTemplate = nil
            }
            Button("Replace", role: .destructive) {
                if let pendingTemplate {
                    actions = pendingTemplate.actions
                }
                pendingTemplate = nil
            }
        } message: {
            if let pendingTemplate {
                Text("Applying \"\(pendingTemplate.name)\" will replace the current action list.")
            }
        }
        .sheet(isPresented: $showingAddAction) {
            PostCreateActionEditorSheet(
                action: nil,
                onSave: { action in
                    actions = actions + [action]
                },
                onCancel: {},
                repositoryPath: repository.path
            )
        }
        .sheet(item: $editingAction) { action in
            PostCreateActionEditorSheet(
                action: action,
                onSave: { updated in
                    var updatedActions = actions
                    if let index = updatedActions.firstIndex(where: { $0.id == updated.id }) {
                        updatedActions[index] = updated
                        actions = updatedActions
                    }
                },
                onCancel: {},
                repositoryPath: repository.path
            )
        }
        .sheet(isPresented: $showingTemplates) {
            PostCreateTemplatesSheet(
                onSelect: { template in
                    applyTemplate(template)
                }
            )
        }
    }

    private var overviewSection: some View {
        Section("Overview") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Configure follow-up steps that run automatically after a new environment is created.")
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    summaryMetric(title: "Total", value: actions.count, systemImage: "list.bullet.rectangle")
                    summaryMetric(title: "Enabled", value: enabledCount, systemImage: "checkmark.circle")
                    summaryMetric(title: "Disabled", value: disabledCount, systemImage: "pause.circle")
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var configuredActionsSection: some View {
        Section("Configured Actions") {
            if actions.isEmpty {
                emptyStateView
            } else {
                ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                    actionRow(action, at: index)
                }

                Button {
                    showingAddAction = true
                } label: {
                    Label("Add Action", systemImage: "plus")
                }

                Button(role: .destructive) {
                    actions = []
                } label: {
                    Label("Clear All Actions", systemImage: "trash")
                }
            }
        }
    }

    private var templatesSection: some View {
        Section("Templates") {
            Button {
                showingTemplates = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "doc.on.doc")
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Apply Template")
                            .foregroundStyle(.primary)
                        Text(actions.isEmpty ? "Start from a built-in or custom action set." : "Replaces the current action list.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var advancedSection: some View {
        Section("Advanced") {
            DisclosureGroup(isExpanded: $showGeneratedScript) {
                ScrollView {
                    Text(PostCreateScriptGenerator.generateScript(from: actions))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(height: 180)
                .background(Color(.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .padding(.top, 6)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Generated Script", systemImage: "scroll")
                    Text("Preview the shell script Aizen will run for enabled actions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var emptyStateView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "gearshape.2")
                    .font(.title3)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text("No actions configured")
                        .fontWeight(.medium)
                    Text("Add individual steps or start from a template.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                Button {
                    showingAddAction = true
                } label: {
                    Label("Add Action", systemImage: "plus")
                }
                .buttonStyle(.bordered)

                Button {
                    showingTemplates = true
                } label: {
                    Label("Use Template", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.vertical, 6)
    }

    private func actionRow(_ action: PostCreateAction, at index: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Toggle("", isOn: Binding(
                    get: { action.enabled },
                    set: { newValue in
                        var updatedActions = actions
                        var updated = action
                        updated.enabled = newValue
                        updatedActions[index] = updated
                        actions = updatedActions
                    }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .padding(.top, 2)

                Image(systemName: action.type.icon)
                    .frame(width: 20)
                    .foregroundStyle(action.enabled ? Color.accentColor : .secondary)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(action.type.displayName)
                            .fontWeight(.medium)

                        if !action.enabled {
                            Text("Disabled")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.secondary.opacity(0.14), in: Capsule())
                        }
                    }

                    Text(actionDescription(action))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    if let metadata = actionMetadata(action) {
                        Text(metadata)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                HStack(spacing: 6) {
                    Button {
                        moveAction(from: index, direction: -1)
                    } label: {
                        Image(systemName: "arrow.up")
                    }
                    .buttonStyle(.borderless)
                    .disabled(index == 0)

                    Button {
                        moveAction(from: index, direction: 1)
                    } label: {
                        Image(systemName: "arrow.down")
                    }
                    .buttonStyle(.borderless)
                    .disabled(index == actions.count - 1)

                    Button {
                        editingAction = action
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.borderless)

                    Button {
                        removeAction(at: index)
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(.vertical, 4)
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

    private func actionMetadata(_ action: PostCreateAction) -> String? {
        switch action.config {
        case .copyFiles(let config):
            let count = config.patterns.count
            return "\(count) pattern\(count == 1 ? "" : "s")"
        case .runCommand(let config):
            return "Runs in \(config.workingDirectory.displayName)"
        case .symlink(let config):
            return "Links \(config.source) into \(config.target)"
        case .customScript(let config):
            let lineCount = config.script.split(whereSeparator: \.isNewline).count
            return "\(max(lineCount, 1)) line\(lineCount == 1 ? "" : "s")"
        }
    }

    private func summaryMetric(title: String, value: Int, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.title3)
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.controlBackgroundColor).opacity(0.55), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func moveAction(from index: Int, direction: Int) {
        let destination = index + direction
        guard actions.indices.contains(index), actions.indices.contains(destination) else { return }
        var updatedActions = actions
        let item = updatedActions.remove(at: index)
        updatedActions.insert(item, at: destination)
        actions = updatedActions
    }

    private func removeAction(at index: Int) {
        guard actions.indices.contains(index) else { return }
        var updatedActions = actions
        updatedActions.remove(at: index)
        actions = updatedActions
    }

    private func applyTemplate(_ template: PostCreateTemplate) {
        if actions.isEmpty {
            actions = template.actions
        } else {
            pendingTemplate = template
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
    @State private var selectedFiles: Set<String> = []
    @State private var customPattern: String = ""
    @State private var command: String = ""
    @State private var workingDirectory: WorkingDirectory = .newWorktree
    @State private var symlinkSource: String = ""
    @State private var symlinkTarget: String = ""
    @State private var customScript: String = ""
    @State private var detectedFiles: [DetectedFile] = []

    struct DetectedFile: Identifiable, Hashable {
        let id: String
        let path: String
        let name: String
        let isDirectory: Bool
        let category: FileCategory

        enum FileCategory: String, CaseIterable {
            case lfs = "Git LFS"
            case gitignored = "Gitignored"

            var order: Int {
                switch self {
                case .lfs: return 0
                case .gitignored: return 1
                }
            }

            var icon: String {
                switch self {
                case .lfs: return "externaldrive"
                case .gitignored: return "eye.slash"
                }
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(action == nil ? "Add Action" : "Edit Action")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()
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

                configSectionsForType
            }
            .formStyle(.grouped)
            .settingsSurface()

            Divider()

            // Footer
            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    saveAction()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)
            }
            .padding()
        }
        .frame(width: 480, height: 500)
        .settingsSheetChrome()
        .onAppear {
            if let action = action {
                loadAction(action)
            }
        }
    }

    @ViewBuilder
    private var configSectionsForType: some View {
        switch selectedType {
        case .copyFiles:
            copyFilesSections

        case .runCommand:
            Section {
                TextField("Command", text: $command)
                    .textFieldStyle(.roundedBorder)

                Picker("Run in", selection: $workingDirectory) {
                    ForEach(WorkingDirectory.allCases, id: \.self) { dir in
                        Text(dir.displayName).tag(dir)
                    }
                }
            } header: {
                Text(selectedType.actionDescription)
            }

        case .symlink:
            Section {
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
            } header: {
                Text(selectedType.actionDescription)
            }

        case .customScript:
            Section {
                CodeEditorView(
                    content: customScript,
                    language: "bash",
                    isEditable: true,
                    onContentChange: { newValue in
                        customScript = newValue
                    }
                )
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            } header: {
                Text(selectedType.actionDescription)
            } footer: {
                Text("Variables: $NEW (new worktree path), $MAIN (main worktree path)")
            }
        }
    }

    // MARK: - Copy Files Sections

    @ViewBuilder
    private var copyFilesSections: some View {
        // Selected files section
        Section {
            if selectedFiles.isEmpty {
                Text("No files selected")
                    .foregroundStyle(.secondary)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(Array(selectedFiles).sorted(), id: \.self) { file in
                        RemovableChip(
                            text: file,
                            onRemove: { selectedFiles.remove(file) },
                            font: .caption,
                            textColor: .primary,
                            backgroundColor: .accentColor,
                            backgroundOpacity: 0.2,
                            horizontalPadding: 8,
                            verticalPadding: 4,
                            spacing: 4,
                            closeSize: 8,
                            closeWeight: .bold
                        )
                    }
                }
            }
        } header: {
            Text("Files to Copy")
        }

        // File browser section - shows gitignored and LFS files
        Section {
            if detectedFiles.isEmpty {
                Text("No gitignored or LFS files found")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(DetectedFile.FileCategory.allCases.sorted(by: { $0.order < $1.order }), id: \.self) { category in
                            let filesInCategory = detectedFiles.filter { $0.category == category }
                            if !filesInCategory.isEmpty {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 4) {
                                        Image(systemName: category.icon)
                                            .font(.caption2)
                                        Text(category.rawValue)
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                    }
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 4)

                                    ForEach(filesInCategory) { file in
                                        fileRow(file)
                                    }
                                }
                            }
                        }
                    }
                    .padding(8)
                }
                .frame(height: 160)
                .background(Color(.controlBackgroundColor).opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        } header: {
            Text("Files Not Copied by Git")
        } footer: {
            Text("Gitignored files and Git LFS tracked files won't exist in new worktrees")
        }
        .onAppear {
            scanRepository()
        }

        // Custom pattern section
        Section {
            HStack {
                TextField("Pattern", text: $customPattern)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        addCustomPattern()
                    }

                Button {
                    addCustomPattern()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .disabled(customPattern.isEmpty)
            }
        } header: {
            Text("Custom Patterns")
        } footer: {
            Text("Add glob patterns for files in subdirectories (e.g., config/*.yml)")
        }
    }

    private func fileRow(_ file: DetectedFile) -> some View {
        Button {
            if selectedFiles.contains(file.path) {
                selectedFiles.remove(file.path)
            } else {
                selectedFiles.insert(file.path)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: selectedFiles.contains(file.path) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selectedFiles.contains(file.path) ? Color.accentColor : .secondary)

                Image(systemName: file.isDirectory ? "folder.fill" : "doc.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(file.name)
                    .font(.callout)

                Spacer()

                if file.isDirectory {
                    Text("/**")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func addCustomPattern() {
        var pattern = customPattern.trimmingCharacters(in: .whitespaces)
        guard !pattern.isEmpty else { return }

        // Convert absolute path to relative if it's inside the repo
        if pattern.hasPrefix("/"), let repoPath = repositoryPath {
            let repoPathWithSlash = repoPath.hasSuffix("/") ? repoPath : repoPath + "/"
            if pattern.hasPrefix(repoPathWithSlash) {
                pattern = String(pattern.dropFirst(repoPathWithSlash.count))
            } else if pattern.hasPrefix(repoPath) {
                pattern = String(pattern.dropFirst(repoPath.count + 1))
            }
        }

        // Remove leading slash if still present
        if pattern.hasPrefix("/") {
            pattern = String(pattern.dropFirst())
        }

        selectedFiles.insert(pattern)
        customPattern = ""
    }

    private func scanRepository() {
        guard let repoPath = repositoryPath else { return }
        detectedFiles = scanForUntrackedFiles(at: repoPath)
    }

    private func scanForUntrackedFiles(at path: String) -> [DetectedFile] {
        let fm = FileManager.default
        var result: [DetectedFile] = []

        // Parse .gitignore patterns
        let gitignorePatterns = parseGitignore(at: path)

        // Parse .gitattributes for LFS patterns (can be full paths or globs)
        let lfsPatterns = parseLFSPatterns(at: path)

        // Add LFS files first (these can be deep paths)
        for lfsPattern in lfsPatterns {
            // Check if it's a specific file path (not a glob)
            if !lfsPattern.contains("*") {
                let fullPath = (path as NSString).appendingPathComponent(lfsPattern)
                var isDirectory: ObjCBool = false
                if fm.fileExists(atPath: fullPath, isDirectory: &isDirectory) {
                    result.append(DetectedFile(
                        id: lfsPattern,
                        path: lfsPattern,
                        name: lfsPattern,
                        isDirectory: isDirectory.boolValue,
                        category: .lfs
                    ))
                }
            } else {
                // For glob patterns, show the pattern itself
                result.append(DetectedFile(
                    id: lfsPattern,
                    path: lfsPattern,
                    name: lfsPattern,
                    isDirectory: false,
                    category: .lfs
                ))
            }
        }

        // Items to always skip in listing
        let skipItems: Set<String> = [".git", ".DS_Store"]

        guard let contents = try? fm.contentsOfDirectory(atPath: path) else { return result }

        for item in contents {
            if skipItems.contains(item) { continue }

            let fullPath = (path as NSString).appendingPathComponent(item)
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: fullPath, isDirectory: &isDirectory) else { continue }

            let isDir = isDirectory.boolValue

            // Check if it's gitignored (won't be in new worktree)
            if matchesAnyPattern(item, patterns: gitignorePatterns) || matchesAnyPattern(item + "/", patterns: gitignorePatterns) {
                result.append(DetectedFile(
                    id: item,
                    path: isDir ? "\(item)/**" : item,
                    name: item,
                    isDirectory: isDir,
                    category: .gitignored
                ))
            }
        }

        // Sort: by category order, then alphabetically
        return result.sorted { lhs, rhs in
            if lhs.category.order != rhs.category.order {
                return lhs.category.order < rhs.category.order
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private func parseGitignore(at repoPath: String) -> [String] {
        let gitignorePath = (repoPath as NSString).appendingPathComponent(".gitignore")
        guard let content = try? String(contentsOfFile: gitignorePath, encoding: .utf8) else { return [] }

        return content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    private func parseLFSPatterns(at repoPath: String) -> [String] {
        let gitattributesPath = (repoPath as NSString).appendingPathComponent(".gitattributes")
        guard let content = try? String(contentsOfFile: gitattributesPath, encoding: .utf8) else { return [] }

        var patterns: [String] = []
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.contains("filter=lfs") {
                // Extract the pattern (first part before space)
                if let pattern = trimmed.components(separatedBy: .whitespaces).first {
                    patterns.append(pattern)
                }
            }
        }
        return patterns
    }

    private func matchesAnyPattern(_ name: String, patterns: [String]) -> Bool {
        for pattern in patterns {
            if matchesGitPattern(name, pattern: pattern) {
                return true
            }
        }
        return false
    }

    private func matchesGitPattern(_ name: String, pattern: String) -> Bool {
        var p = pattern

        // Handle negation (we skip negated patterns for simplicity)
        if p.hasPrefix("!") { return false }

        // Remove leading slash (anchored to root)
        if p.hasPrefix("/") {
            p = String(p.dropFirst())
        }

        // Remove trailing slash (directory indicator)
        if p.hasSuffix("/") {
            p = String(p.dropLast())
        }

        // Direct match
        if name == p { return true }

        // Simple wildcard matching
        if p.contains("*") {
            // Convert glob to simple matching
            // *.ext matches files ending with .ext
            if p.hasPrefix("*") {
                let suffix = String(p.dropFirst())
                if name.hasSuffix(suffix) { return true }
            }
            // prefix* matches files starting with prefix
            if p.hasSuffix("*") {
                let prefix = String(p.dropLast())
                if name.hasPrefix(prefix) { return true }
            }
            // ** matches everything
            if p == "**" { return true }
        }

        return false
    }

    private var isValid: Bool {
        switch selectedType {
        case .copyFiles:
            return !selectedFiles.isEmpty
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
            selectedFiles = Set(config.patterns)
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
            config = .copyFiles(CopyFilesConfig(patterns: Array(selectedFiles).sorted()))
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
                Text("Apply Template")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()
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

            Divider()

            // Footer
            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding()
        }
        .frame(width: 400, height: 450)
        .settingsSheetChrome()
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
                    PillBadge(
                        text: "Built-in",
                        color: Color(.systemGray),
                        textColor: .secondary,
                        font: .caption2,
                        horizontalPadding: 6,
                        verticalPadding: 2,
                        backgroundOpacity: 0.2
                    )
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
    @State private var addActionRequested = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            DetailHeaderBar(showsBackground: false) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Post-Create Actions")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Run automatically after environment creation")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } trailing: {
                Button {
                    addActionRequested = true
                } label: {
                    Label("Add Action", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }

            Divider()

            // Content
            PostCreateActionsView(repository: repository, addActionRequested: $addActionRequested)

            Divider()

            // Footer
            HStack {
                Text("Actions run automatically after worktree creation")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 620, height: 620)
        .settingsSheetChrome()
        .environment(\.managedObjectContext, viewContext)
    }
}
