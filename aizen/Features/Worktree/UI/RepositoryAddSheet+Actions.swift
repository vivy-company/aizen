//
//  RepositoryAddSheet+Actions.swift
//  aizen
//

import AppKit
import SwiftUI

extension RepositoryAddSheet {
    var isValid: Bool {
        if mode == .clone {
            return !cloneURL.isEmpty && !selectedPath.isEmpty
        } else if mode == .create {
            return !selectedPath.isEmpty && !repositoryName.isEmpty
        } else {
            return !selectedPath.isEmpty
        }
    }

    var actionButtonText: String {
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

    func addRepository() {
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
