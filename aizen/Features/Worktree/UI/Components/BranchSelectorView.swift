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
}

#Preview {
    BranchSelectorView(
        repository: Repository(),
        repositoryManager: WorkspaceRepositoryStore(viewContext: PersistenceController.preview.container.viewContext),
        selectedBranch: .constant(nil)
    )
}
