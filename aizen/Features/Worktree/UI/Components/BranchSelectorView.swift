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
}

#Preview {
    BranchSelectorView(
        repository: Repository(),
        repositoryManager: WorkspaceRepositoryStore(viewContext: PersistenceController.preview.container.viewContext),
        selectedBranch: .constant(nil)
    )
}
