import Foundation
import SwiftUI

extension BranchSelectorView {
    var filteredBranches: [BranchInfo] {
        if searchText.isEmpty {
            return branches
        }
        return branches.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var searchBinding: Binding<String> {
        Binding(
            get: { searchText },
            set: { newValue in
                searchText = newValue
                displayedCount = pageSize
            }
        )
    }

    func createBranch() {
        guard !searchText.isEmpty else { return }
        onCreateBranch?(searchText)
        dismiss()
    }

    func loadBranches() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let loadedBranches = try await repositoryManager.getBranches(for: repository)
                await MainActor.run {
                    branches = loadedBranches
                    displayedCount = pageSize
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = String(localized: "git.branch.loadFailed \(error.localizedDescription)")
                    isLoading = false
                }
            }
        }
    }
}
