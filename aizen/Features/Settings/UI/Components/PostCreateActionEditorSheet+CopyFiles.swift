import SwiftUI

extension PostCreateActionEditorSheet {
    @ViewBuilder
    var copyFilesSections: some View {
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

    func fileRow(_ file: DetectedFile) -> some View {
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

    func addCustomPattern() {
        var pattern = customPattern.trimmingCharacters(in: CharacterSet.whitespaces)
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
}
