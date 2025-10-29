//
//  RepositoryAddSheet.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import SwiftUI

enum AddRepositoryMode {
    case clone
    case existing
}

struct RepositoryAddSheet: View {
    @Environment(\.dismiss) private var dismiss
    let workspace: Workspace
    @ObservedObject var repositoryManager: RepositoryManager

    @State private var mode: AddRepositoryMode = .existing
    @State private var cloneURL = ""
    @State private var selectedPath = ""
    @State private var isProcessing = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("repository.add.title", bundle: .main)
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()
            }
            .padding()

            Divider()

            // Content
            ScrollView {
                VStack(spacing: 20) {
                    // Mode picker
                    Picker(String(localized: "repository.mode"), selection: $mode) {
                        Label(String(localized: "repository.openExisting"), systemImage: "folder")
                            .tag(AddRepositoryMode.existing)
                        Label(String(localized: "repository.cloneFromURL"), systemImage: "arrow.down.circle")
                            .tag(AddRepositoryMode.clone)
                    }
                    .pickerStyle(.segmented)
                    .padding(.top)

                    if mode == .clone {
                        cloneView
                    } else {
                        existingView
                    }

                    if let error = errorMessage {
                        Text(error)
                            .font(.callout)
                            .foregroundStyle(.red)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding()
            }

            Divider()

            // Footer
            HStack {
                Spacer()

                Button(String(localized: "general.cancel")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(mode == .clone ? String(localized: "general.clone") : String(localized: "general.add")) {
                    addRepository()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(isProcessing || !isValid)
            }
            .padding()
        }
        .frame(width: 550)
        .frame(minHeight: 300, maxHeight: 500)
    }

    private var cloneView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("repository.add.url", bundle: .main)
                .font(.headline)

            TextField(String(localized: "repository.add.urlPlaceholder"), text: $cloneURL)
                .textFieldStyle(.roundedBorder)

            Text("repository.cloneLocation", bundle: .main)
                .font(.headline)
                .padding(.top, 8)

            HStack {
                TextField(String(localized: "repository.selectDestination"), text: $selectedPath)
                    .textFieldStyle(.roundedBorder)
                    .disabled(true)

                Button(String(localized: "repository.add.choose")) {
                    selectCloneDestination()
                }
            }

            Text("repository.cloneDescription", bundle: .main)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var existingView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("repository.selectLocation", bundle: .main)
                .font(.headline)

            HStack {
                TextField(String(localized: "repository.selectFolder"), text: $selectedPath)
                    .textFieldStyle(.roundedBorder)
                    .disabled(true)

                Button(String(localized: "repository.add.choose")) {
                    selectExistingRepository()
                }
            }

            Text("repository.selectGitFolder", bundle: .main)
                .font(.caption)
                .foregroundStyle(.secondary)

            if !selectedPath.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("repository.add.selected", bundle: .main)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(selectedPath)
                        .font(.caption)
                        .fontDesign(.monospaced)
                        .foregroundStyle(.primary)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                }
                .padding(.top, 8)
            }
        }
    }

    private var isValid: Bool {
        if mode == .clone {
            return !cloneURL.isEmpty && !selectedPath.isEmpty
        } else {
            return !selectedPath.isEmpty
        }
    }

    private func selectExistingRepository() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = String(localized: "repository.panelSelectGit")

        if panel.runModal() == .OK, let url = panel.url {
            selectedPath = url.path
        }
    }

    private func selectCloneDestination() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = String(localized: "repository.panelSelectClone")

        if panel.runModal() == .OK, let url = panel.url {
            selectedPath = url.path
        }
    }

    private func addRepository() {
        guard !isProcessing else { return }

        isProcessing = true
        errorMessage = nil

        Task {
            do {
                if mode == .clone {
                    _ = try await repositoryManager.cloneRepository(
                        url: cloneURL,
                        destinationPath: selectedPath,
                        workspace: workspace
                    )
                } else {
                    _ = try await repositoryManager.addExistingRepository(
                        path: selectedPath,
                        workspace: workspace
                    )
                }

                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isProcessing = false
                }
            }
        }
    }
}

#Preview {
    RepositoryAddSheet(
        workspace: Workspace(),
        repositoryManager: RepositoryManager(viewContext: PersistenceController.preview.container.viewContext)
    )
}
