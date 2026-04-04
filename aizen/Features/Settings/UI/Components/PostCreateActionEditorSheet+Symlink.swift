import AppKit
import SwiftUI

extension PostCreateActionEditorSheet {
    @ViewBuilder
    var symlinkSection: some View {
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
    }

    func selectSymlinkSource() {
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
