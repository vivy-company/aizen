//
//  RepositoryAddSheet.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import SwiftUI

enum AddRepositoryMode: CaseIterable {
    case clone
    case existing
    case create

    var title: LocalizedStringKey {
        switch self {
        case .existing:
            return "repository.openExisting"
        case .clone:
            return "repository.cloneFromURL"
        case .create:
            return "repository.createNew"
        }
    }
}

struct RepositoryAddSheet: View {
    @Environment(\.dismiss) private var dismiss
    let workspace: Workspace
    @ObservedObject var repositoryManager: RepositoryManager
    var onRepositoryAdded: ((Repository) -> Void)?

    @State private var mode: AddRepositoryMode = .existing
    @State private var cloneURL = ""
    @State private var selectedPath = ""
    @State private var repositoryName = ""
    @State private var isProcessing = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            DetailHeaderBar(showsBackground: false) {
                Text("repository.add.title", bundle: .main)
                    .font(.title2)
                    .fontWeight(.semibold)
            }

            Divider()

            Form {
                modeSection

                if mode == .clone {
                    cloneSection
                } else if mode == .create {
                    createSection
                } else {
                    existingSection
                }

                if let error = errorMessage {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .font(.callout)
                                Text("Add project failed")
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

                Button(String(localized: "general.cancel")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(actionButtonText) {
                    addRepository()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(isProcessing || !isValid)
            }
            .padding()
        }
        .frame(width: 520)
        .frame(minHeight: 360, maxHeight: 560)
    }

    @ViewBuilder
    private var modeSection: some View {
        Section("Project Source") {
            Picker("Mode", selection: $mode) {
                ForEach(AddRepositoryMode.allCases, id: \.self) { mode in
                    Text(mode.title)
                        .tag(mode)
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var cloneSection: some View {
        Section("Clone") {
            LabeledContent(String(localized: "repository.add.url", bundle: .main)) {
                TextField(String(localized: "repository.add.urlPlaceholder"), text: $cloneURL)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 280, alignment: .leading)
            }

            pathPickerRow(
                title: String(localized: "repository.cloneLocation", bundle: .main),
                placeholder: String(localized: "repository.selectDestination"),
                action: selectCloneDestination
            )

            Text("repository.cloneDescription", bundle: .main)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var existingSection: some View {
        Section("Existing Repository") {
            pathPickerRow(
                title: String(localized: "repository.selectLocation", bundle: .main),
                placeholder: String(localized: "repository.selectFolder"),
                action: selectExistingRepository
            )

            Text("repository.selectGitFolder", bundle: .main)
                .font(.caption)
                .foregroundStyle(.secondary)

            if !selectedPath.isEmpty {
                selectedPathPreview
            }
        }
    }

    @ViewBuilder
    private var createSection: some View {
        Section("Create Repository") {
            pathPickerRow(
                title: String(localized: "repository.newLocation", bundle: .main),
                placeholder: String(localized: "repository.selectFolder"),
                action: selectNewRepositoryLocation
            )

            LabeledContent(String(localized: "repository.create.name", bundle: .main)) {
                TextField(String(localized: "repository.create.namePlaceholder"), text: $repositoryName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 280, alignment: .leading)
            }

            Text("repository.create.description", bundle: .main)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var selectedPathPreview: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("repository.add.selected", bundle: .main)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(selectedPath)
                .font(.caption)
                .fontDesign(.monospaced)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        }
    }

    @ViewBuilder
    private func pathPickerRow(title: String, placeholder: String, action: @escaping () -> Void) -> some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                Text(selectedPath.isEmpty ? placeholder : selectedPath)
                    .font(selectedPath.isEmpty ? .body : .system(.body, design: .monospaced))
                    .foregroundStyle(selectedPath.isEmpty ? .tertiary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .frame(width: 280, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
                    }

                Button(String(localized: "repository.add.choose")) {
                    action()
                }
            }
        }
    }

    private var isValid: Bool {
        if mode == .clone {
            return !cloneURL.isEmpty && !selectedPath.isEmpty
        } else if mode == .create {
            return !selectedPath.isEmpty && !repositoryName.isEmpty
        } else {
            return !selectedPath.isEmpty
        }
    }

    private var actionButtonText: String {
        switch mode {
        case .clone:
            return String(localized: "general.clone")
        case .create:
            return String(localized: "general.create")
        case .existing:
            return String(localized: "general.add")
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

    private func selectNewRepositoryLocation() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = String(localized: "repository.panelSelectCreateLocation")

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
                let repository: Repository

                if mode == .clone {
                    repository = try await repositoryManager.cloneRepository(
                        url: cloneURL,
                        destinationPath: selectedPath,
                        workspace: workspace
                    )
                } else if mode == .create {
                    repository = try await repositoryManager.createNewRepository(
                        path: selectedPath,
                        name: repositoryName,
                        workspace: workspace
                    )
                } else {
                    repository = try await repositoryManager.addExistingRepository(
                        path: selectedPath,
                        workspace: workspace
                    )
                }

                await MainActor.run {
                    onRepositoryAdded?(repository)
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
