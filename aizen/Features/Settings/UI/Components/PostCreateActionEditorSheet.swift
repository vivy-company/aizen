import AppKit
import SwiftUI

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
    @State var detectedFiles: [DetectedFile] = []

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
            HStack {
                Text(action == nil ? "Add Action" : "Edit Action")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()
            }
            .padding()

            Divider()

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
            if let action {
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

    @ViewBuilder
    private var copyFilesSections: some View {
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

        if pattern.hasPrefix("/"), let repoPath = repositoryPath {
            let repoPathWithSlash = repoPath.hasSuffix("/") ? repoPath : repoPath + "/"
            if pattern.hasPrefix(repoPathWithSlash) {
                pattern = String(pattern.dropFirst(repoPathWithSlash.count))
            } else if pattern.hasPrefix(repoPath) {
                pattern = String(pattern.dropFirst(repoPath.count + 1))
            }
        }

        if pattern.hasPrefix("/") {
            pattern = String(pattern.dropFirst())
        }

        selectedFiles.insert(pattern)
        customPattern = ""
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
