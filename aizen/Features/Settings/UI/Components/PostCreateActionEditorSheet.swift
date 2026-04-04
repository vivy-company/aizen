import AppKit
import SwiftUI

struct PostCreateActionEditorSheet: View {
    let action: PostCreateAction?
    let onSave: (PostCreateAction) -> Void
    let onCancel: () -> Void
    var repositoryPath: String?

    @Environment(\.dismiss) var dismiss

    @State var selectedType: PostCreateActionType = .copyFiles
    @State var selectedFiles: Set<String> = []
    @State var customPattern: String = ""
    @State var command: String = ""
    @State var workingDirectory: WorkingDirectory = .newWorktree
    @State var symlinkSource: String = ""
    @State var symlinkTarget: String = ""
    @State var customScript: String = ""
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
}
