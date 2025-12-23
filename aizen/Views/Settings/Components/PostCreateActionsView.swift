//
//  PostCreateActionsView.swift
//  aizen
//

import SwiftUI
import CoreData

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            totalHeight = currentY + lineHeight
        }

        return (CGSize(width: maxWidth, height: totalHeight), positions)
    }
}

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
                        HStack(spacing: 4) {
                            Text(file)
                                .font(.caption)
                            Button {
                                selectedFiles.remove(file)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.2))
                        .clipShape(Capsule())
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
        let pattern = customPattern.trimmingCharacters(in: .whitespaces)
        guard !pattern.isEmpty else { return }
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
                Text("Post-Create Actions")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()
            }
            .padding()

            Divider()

            // Content
            ScrollView {
                PostCreateActionsView(repository: repository, showHeader: false)
                    .padding()
            }

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
        .frame(width: 500, height: 420)
        .environment(\.managedObjectContext, viewContext)
    }
}
