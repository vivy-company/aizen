import SwiftUI

struct BranchSelectorView: View {
    let repository: Repository
    let repositoryManager: WorkspaceRepositoryStore
    @Binding var selectedBranch: BranchInfo?
    var onSelectBranch: ((BranchInfo) -> Void)? = nil

    // Optional: Allow branch creation
    var allowCreation: Bool = false
    var onCreateBranch: ((String) -> Void)?

    @State var searchText: String = ""
    @State var branches: [BranchInfo] = []
    @State var isLoading: Bool = true
    @State var errorMessage: String?

    let pageSize = 30
    @State var displayedCount = 30

    @Environment(\.dismiss) var dismiss

    var filteredBranches: [BranchInfo] {
        if searchText.isEmpty {
            return branches
        }
        return branches.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var searchBinding: Binding<String> {
        Binding(
            get: { searchText },
            set: { newValue in
                searchText = newValue
                displayedCount = pageSize
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with search and close
            HStack(spacing: 12) {
                SearchField(
                    placeholder: allowCreation ? "git.branch.searchOrCreate" : "git.branch.search",
                    text: searchBinding,
                    iconColor: .secondary,
                    onSubmit: {
                        if allowCreation && !searchText.isEmpty && filteredBranches.isEmpty {
                            createBranch()
                        }
                    },
                    trailing: { EmptyView() }
                )
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)

                DetailCloseButton(action: { dismiss() }, size: 20)
                    .symbolRenderingMode(.hierarchical)
            }
            .padding(12)

            Divider()

            listContent
        }
        .frame(width: 350, height: 400)
        .background(AppSurfaceTheme.backgroundColor())
        .onAppear {
            loadBranches()
        }
    }

    func createBranch() {
        guard !searchText.isEmpty else { return }
        onCreateBranch?(searchText)
        dismiss()
    }

    private func loadBranches() {
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

#Preview {
    BranchSelectorView(
        repository: Repository(),
        repositoryManager: WorkspaceRepositoryStore(viewContext: PersistenceController.preview.container.viewContext),
        selectedBranch: .constant(nil)
    )
}
