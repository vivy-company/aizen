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
    @ObservedObject var repositoryManager: WorkspaceRepositoryStore
    var onRepositoryAdded: ((Repository) -> Void)?

    @State var mode: AddRepositoryMode = .existing
    @State var cloneURL = ""
    @State var selectedPath = ""
    @State var repositoryName = ""
    @State var isProcessing = false
    @State var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            DetailHeaderBar(showsBackground: false) {
                Text("repository.add.title", bundle: .main)
                    .font(.title2)
                    .fontWeight(.semibold)
            }

            Divider()

            Form { formContent }
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
        .settingsSheetChrome()
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

    func selectExistingRepository() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = String(localized: "repository.panelSelectGit")

        if panel.runModal() == .OK, let url = panel.url {
            selectedPath = url.path
        }
    }

    func selectCloneDestination() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = String(localized: "repository.panelSelectClone")

        if panel.runModal() == .OK, let url = panel.url {
            selectedPath = url.path
        }
    }

    func selectNewRepositoryLocation() {
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
        repositoryManager: WorkspaceRepositoryStore(viewContext: PersistenceController.preview.container.viewContext)
    )
}
